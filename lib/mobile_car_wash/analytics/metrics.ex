defmodule MobileCarWash.Analytics.Metrics do
  @moduledoc """
  Aggregate metrics queries for the admin dashboard.
  The validated learning engine — every metric here drives a persevere/pivot decision.

  All functions accept a `period` parameter:
  - `:last_7_days`
  - `:last_30_days`
  - `:this_week` (Monday to now)
  """

  alias MobileCarWash.Repo
  import Ecto.Query

  # --- KPIs (Top Row) ---

  @doc "Returns key performance indicators for the dashboard top row."
  def kpis(period \\ :last_7_days) do
    {start_date, end_date} = date_range(period)

    %{
      revenue: revenue(start_date, end_date),
      active_subscribers: active_subscribers(),
      bookings: bookings_count(start_date, end_date),
      conversion_rate: conversion_rate(start_date, end_date),
      period: period
    }
  end

  @doc "Revenue from succeeded payments in the period."
  def revenue(start_date, end_date) do
    query =
      from p in "payments",
        where: p.status == "succeeded",
        where: p.inserted_at >= ^start_date,
        where: p.inserted_at < ^end_date,
        select: %{
          total_cents: coalesce(sum(p.amount_cents), 0),
          count: count(p.id)
        }

    Repo.one(query)
  end

  @doc "Count of active subscriptions (all time — not period-dependent)."
  def active_subscribers do
    query =
      from s in "subscriptions",
        where: s.status == "active",
        select: count(s.id)

    Repo.one(query)
  end

  @doc "Count of appointments created in the period."
  def bookings_count(start_date, end_date) do
    query =
      from a in "appointments",
        where: a.inserted_at >= ^start_date,
        where: a.inserted_at < ^end_date,
        select: count(a.id)

    Repo.one(query)
  end

  @doc "Visit → Booking conversion rate for the period."
  def conversion_rate(start_date, end_date) do
    visitors = event_count("page.viewed", start_date, end_date)
    bookings = event_count("booking.completed", start_date, end_date)

    if visitors > 0, do: Float.round(bookings / visitors * 100, 1), else: 0.0
  end

  # --- AARRR Funnel ---

  @doc "Returns AARRR pirate metrics funnel for the period."
  def funnel(period \\ :last_7_days) do
    {start_date, end_date} = date_range(period)

    visitors = event_count("page.viewed", start_date, end_date)
    signups = event_count("signup.completed", start_date, end_date)
    bookings_started = event_count("booking.started", start_date, end_date)
    bookings_completed = event_count("booking.completed", start_date, end_date)
    payments = succeeded_payment_count(start_date, end_date)
    returning = returning_customers(start_date, end_date)

    steps = [
      %{name: "Visitors", count: visitors, rate: 100.0},
      %{name: "Signups", count: signups, rate: safe_rate(signups, visitors)},
      %{name: "Bookings Started", count: bookings_started, rate: safe_rate(bookings_started, signups)},
      %{name: "Bookings Completed", count: bookings_completed, rate: safe_rate(bookings_completed, bookings_started)},
      %{name: "Payments", count: payments, rate: safe_rate(payments, bookings_completed)},
      %{name: "Returning", count: returning, rate: safe_rate(returning, payments)}
    ]

    %{steps: steps, period: period}
  end

  # --- Revenue Breakdown ---

  @doc "Revenue broken down by day for charting."
  def daily_revenue(period \\ :last_7_days) do
    {start_date, end_date} = date_range(period)

    query =
      from p in "payments",
        where: p.status == "succeeded",
        where: p.inserted_at >= ^start_date,
        where: p.inserted_at < ^end_date,
        group_by: fragment("DATE(?)", p.inserted_at),
        order_by: fragment("DATE(?)", p.inserted_at),
        select: %{
          date: fragment("DATE(?)", p.inserted_at),
          total_cents: coalesce(sum(p.amount_cents), 0),
          count: count(p.id)
        }

    Repo.all(query)
  end

  @doc "Compare revenue between current period and previous period of same length."
  def compare_revenue(period \\ :last_7_days) do
    {current_start, current_end} = date_range(period)
    {previous_start, previous_end} = previous_date_range(period)

    current = revenue(current_start, current_end)
    previous = revenue(previous_start, previous_end)

    current_cents = to_cents(current.total_cents)
    previous_cents = to_cents(previous.total_cents)

    delta_pct =
      if previous_cents > 0 do
        Float.round((current_cents - previous_cents) / previous_cents * 100, 1)
      else
        if current_cents > 0, do: 100.0, else: 0.0
      end

    %{
      current: current_cents,
      previous: previous_cents,
      delta_pct: delta_pct
    }
  end

  defp to_cents(nil), do: 0
  defp to_cents(%Decimal{} = d), do: Decimal.to_integer(d)
  defp to_cents(n) when is_integer(n), do: n
  defp to_cents(_), do: 0

  defp previous_date_range(:last_7_days) do
    now = DateTime.utc_now()
    current_start = DateTime.add(now, -7, :day)
    previous_end = current_start
    previous_start = DateTime.add(previous_end, -7, :day)
    {previous_start, previous_end}
  end

  defp previous_date_range(:last_30_days) do
    now = DateTime.utc_now()
    current_start = DateTime.add(now, -30, :day)
    previous_end = current_start
    previous_start = DateTime.add(previous_end, -30, :day)
    {previous_start, previous_end}
  end

  defp previous_date_range(:this_week) do
    today = Date.utc_today()
    days_since_monday = Date.day_of_week(today) - 1
    this_monday = Date.add(today, -days_since_monday)
    last_monday = Date.add(this_monday, -7)
    {:ok, start_date} = DateTime.new(last_monday, ~T[00:00:00])
    {:ok, end_date} = DateTime.new(this_monday, ~T[00:00:00])
    {start_date, end_date}
  end

  # --- Booking Stats ---

  @doc "Booking funnel stats — abandonment by step."
  def booking_stats(period \\ :last_7_days) do
    {start_date, end_date} = date_range(period)

    started = event_count("booking.started", start_date, end_date)
    completed = event_count("booking.completed", start_date, end_date)
    abandoned = started - completed

    # Abandonment by step
    steps_query =
      from e in "events",
        where: e.event_name == "booking.step_completed",
        where: e.inserted_at >= ^start_date,
        where: e.inserted_at < ^end_date,
        group_by: fragment("?->>'step'", e.properties),
        select: %{
          step: fragment("?->>'step'", e.properties),
          count: count(e.id)
        }

    step_counts = Repo.all(steps_query)

    %{
      started: started,
      completed: completed,
      abandoned: abandoned,
      abandonment_rate: if(started > 0, do: Float.round(abandoned / started * 100, 1), else: 0.0),
      by_step: step_counts
    }
  end

  # --- Pivot Signals ---

  @doc """
  Evaluates all pivot signal thresholds.
  Returns a list of signals with :green, :yellow, or :red status.
  """
  def pivot_signals do
    {start_7d, end_7d} = date_range(:last_7_days)
    {start_30d, end_30d} = date_range(:last_30_days)

    visitors_7d = event_count("page.viewed", start_7d, end_7d)
    signups_7d = event_count("signup.completed", start_7d, end_7d)
    bookings_started_7d = event_count("booking.started", start_7d, end_7d)
    bookings_completed_7d = event_count("booking.completed", start_7d, end_7d)

    visit_to_signup = if visitors_7d > 0, do: signups_7d / visitors_7d * 100.0, else: 0.0
    signup_to_booking = if signups_7d > 0, do: bookings_started_7d / signups_7d * 100.0, else: 0.0

    abandonment =
      if bookings_started_7d > 0,
        do: (bookings_started_7d - bookings_completed_7d) / bookings_started_7d * 100.0,
        else: 0.0

    churn_30d = monthly_churn_rate(start_30d, end_30d)

    [
      %{
        name: "Weekly Traffic",
        metric: visitors_7d,
        threshold: 50,
        comparison: :gte,
        unit: "visitors",
        status: signal_status(visitors_7d, 50, :gte),
        action: "Pivot marketing channel"
      },
      %{
        name: "Visit → Signup",
        metric: Float.round(visit_to_signup, 1),
        threshold: 5.0,
        comparison: :gte,
        unit: "%",
        status: signal_status(visit_to_signup, 5.0, :gte),
        action: "Pivot landing page / value prop"
      },
      %{
        name: "Signup → Booking",
        metric: Float.round(signup_to_booking, 1),
        threshold: 30.0,
        comparison: :gte,
        unit: "%",
        status: signal_status(signup_to_booking, 30.0, :gte),
        action: "Reduce booking friction"
      },
      %{
        name: "Booking Abandonment",
        metric: Float.round(abandonment, 1),
        threshold: 60.0,
        comparison: :lte,
        unit: "%",
        status: signal_status(abandonment, 60.0, :lte),
        action: "Pivot payment flow / add trust signals"
      },
      %{
        name: "Monthly Churn",
        metric: Float.round(churn_30d, 1),
        threshold: 15.0,
        comparison: :lte,
        unit: "%",
        status: signal_status(churn_30d, 15.0, :lte),
        action: "Pivot pricing / add value"
      }
    ]
  end

  # --- Recent Events Feed ---

  @doc "Returns the most recent events for the event feed."
  def recent_events(limit \\ 50, offset \\ 0) do
    query =
      from e in "events",
        order_by: [desc: e.inserted_at],
        limit: ^limit,
        offset: ^offset,
        select: %{
          id: e.id,
          event_name: e.event_name,
          session_id: e.session_id,
          source: e.source,
          properties: e.properties,
          customer_id: e.customer_id,
          inserted_at: e.inserted_at
        }

    Repo.all(query)
  end

  @doc "Returns total event count for pagination."
  def event_total do
    Repo.one(from e in "events", select: count(e.id))
  end

  @doc "Returns distinct event names for filtering."
  def event_names do
    query =
      from e in "events",
        distinct: true,
        order_by: e.event_name,
        select: e.event_name

    Repo.all(query)
  end

  @doc "Returns events filtered by name."
  def events_by_name(event_name, limit \\ 50, offset \\ 0) do
    query =
      from e in "events",
        where: e.event_name == ^event_name,
        order_by: [desc: e.inserted_at],
        limit: ^limit,
        offset: ^offset,
        select: %{
          id: e.id,
          event_name: e.event_name,
          session_id: e.session_id,
          source: e.source,
          properties: e.properties,
          customer_id: e.customer_id,
          inserted_at: e.inserted_at
        }

    Repo.all(query)
  end

  # --- Private Helpers ---

  defp event_count(event_name, start_date, end_date) do
    query =
      from e in "events",
        where: e.event_name == ^event_name,
        where: e.inserted_at >= ^start_date,
        where: e.inserted_at < ^end_date,
        select: count(e.id)

    Repo.one(query)
  end

  defp succeeded_payment_count(start_date, end_date) do
    query =
      from p in "payments",
        where: p.status == "succeeded",
        where: p.inserted_at >= ^start_date,
        where: p.inserted_at < ^end_date,
        select: count(p.id)

    Repo.one(query)
  end

  defp returning_customers(start_date, end_date) do
    # Customers who have more than 1 completed booking in the period
    query =
      from a in "appointments",
        where: a.status in ["confirmed", "completed"],
        where: a.inserted_at >= ^start_date,
        where: a.inserted_at < ^end_date,
        group_by: a.customer_id,
        having: count(a.id) > 1,
        select: a.customer_id

    length(Repo.all(query))
  end

  @doc """
  Returns performance metrics for each technician in the period.
  Groups completed appointments by technician and calculates revenue metrics.
  """
  def technician_performance(period \\ :last_7_days) do
    {start_date, end_date} = date_range(period)

    # Get completed appointments grouped by technician
    query =
      from a in "appointments",
        left_join: t in "technicians",
        on: a.technician_id == t.id,
        where: a.status == "completed",
        where: a.inserted_at >= ^start_date,
        where: a.inserted_at < ^end_date,
        where: not is_nil(a.technician_id),
        group_by: [a.technician_id, t.name],
        select: %{
          technician_id: a.technician_id,
          technician_name: coalesce(t.name, "Unknown"),
          washes_count: count(a.id),
          total_revenue_cents: coalesce(sum(a.price_cents), 0)
        }

    results = Repo.all(query)

    # Map results and calculate efficiency as revenue per wash
    Enum.map(results, fn tech ->
      revenue_per_wash =
        if tech.washes_count > 0 do
          total = tech.total_revenue_cents |> Decimal.to_integer()
          Float.round(total / tech.washes_count / 100, 2)
        else
          0.0
        end

      Map.merge(tech, %{
        avg_actual_minutes: 0,
        avg_estimated_minutes: 0,
        efficiency_pct: revenue_per_wash * 10
      })
    end)
    |> Enum.sort_by(& &1.washes_count, :desc)
  end

  defp monthly_churn_rate(start_date, end_date) do
    cancelled =
      Repo.one(
        from s in "subscriptions",
          where: s.status == "cancelled",
          where: s.updated_at >= ^start_date,
          where: s.updated_at < ^end_date,
          select: count(s.id)
      )

    total_active =
      Repo.one(
        from s in "subscriptions",
          where: s.status == "active",
          select: count(s.id)
      )

    total = total_active + cancelled
    if total > 0, do: cancelled / total * 100, else: 0.0
  end

  defp safe_rate(_num, 0), do: 0.0
  defp safe_rate(num, denom), do: Float.round(num / denom * 100, 1)

  defp date_range(:last_7_days) do
    now = DateTime.utc_now()
    start_date = DateTime.add(now, -7, :day)
    {start_date, now}
  end

  defp date_range(:last_30_days) do
    now = DateTime.utc_now()
    start_date = DateTime.add(now, -30, :day)
    {start_date, now}
  end

  defp date_range(:this_week) do
    today = Date.utc_today()
    days_since_monday = Date.day_of_week(today) - 1
    monday = Date.add(today, -days_since_monday)
    {:ok, start_date} = DateTime.new(monday, ~T[00:00:00])
    {start_date, DateTime.utc_now()}
  end

  defp signal_status(value, threshold, :gte) do
    cond do
      value >= threshold -> :green
      value >= threshold * 0.7 -> :yellow
      true -> :red
    end
  end

  defp signal_status(value, threshold, :lte) do
    cond do
      value <= threshold -> :green
      value <= threshold * 1.3 -> :yellow
      true -> :red
    end
  end
end
