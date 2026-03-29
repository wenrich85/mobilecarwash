defmodule MobileCarWash.Operations.TechEarnings do
  @moduledoc """
  Calculates technician earnings and wash history for pay periods.
  Pay period is configurable per technician (default Monday-Sunday).
  Rate is per-wash, configurable per technician.
  """

  alias MobileCarWash.Scheduling.Appointment
  alias MobileCarWash.Scheduling.ServiceType
  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Operations.{Technician, AppointmentChecklist, ChecklistItem}

  require Ash.Query

  @doc """
  Returns the current pay period date range for a technician.
  Based on `pay_period_start_day` (1=Monday..7=Sunday).
  """
  def pay_period_range(technician) do
    today = Date.utc_today()
    start_day = technician.pay_period_start_day || 1
    current_day = Date.day_of_week(today)

    # Calculate how many days back to the start of the period
    days_back = rem(current_day - start_day + 7, 7)
    period_start = Date.add(today, -days_back)
    period_end = Date.add(period_start, 6)

    {period_start, period_end}
  end

  @doc """
  Returns completed washes for a technician in a date range.
  """
  def completed_washes(technician_id, start_date, end_date) do
    {:ok, start_dt} = DateTime.new(start_date, ~T[00:00:00])
    {:ok, end_dt} = DateTime.new(Date.add(end_date, 1), ~T[00:00:00])

    appointments =
      Appointment
      |> Ash.Query.filter(
        technician_id == ^technician_id and
          status == :completed and
          scheduled_at >= ^start_dt and
          scheduled_at < ^end_dt
      )
      |> Ash.Query.sort(scheduled_at: :desc)
      |> Ash.read!()

    # Load related data
    service_map = load_service_map(appointments)
    customer_map = load_customer_map(appointments)
    checklist_times = load_checklist_times(appointments)

    Enum.map(appointments, fn appt ->
      %{
        id: appt.id,
        date: DateTime.to_date(appt.scheduled_at),
        scheduled_at: appt.scheduled_at,
        service_name: Map.get(service_map, appt.service_type_id, "Service"),
        customer_name: Map.get(customer_map, appt.customer_id, "Customer"),
        duration_minutes: appt.duration_minutes,
        actual_minutes: Map.get(checklist_times, appt.id),
        price_cents: appt.price_cents
      }
    end)
  end

  @doc """
  Returns a complete earnings summary for the current pay period.
  """
  def earnings_summary(technician) do
    {period_start, period_end} = pay_period_range(technician)
    washes = completed_washes(technician.id, period_start, period_end)
    rate = technician.pay_rate_cents || 2500

    %{
      washes_count: length(washes),
      total_cents: length(washes) * rate,
      rate_cents: rate,
      period_start: period_start,
      period_end: period_end,
      washes: washes
    }
  end

  @doc """
  Returns all completed washes for a technician (no date filter), most recent first.
  """
  def all_completed_washes(technician_id, limit \\ 20) do
    appointments =
      Appointment
      |> Ash.Query.filter(technician_id == ^technician_id and status == :completed)
      |> Ash.Query.sort(scheduled_at: :desc)
      |> Ash.Query.limit(limit)
      |> Ash.read!()

    service_map = load_service_map(appointments)
    customer_map = load_customer_map(appointments)
    checklist_times = load_checklist_times(appointments)

    Enum.map(appointments, fn appt ->
      %{
        id: appt.id,
        date: DateTime.to_date(appt.scheduled_at),
        scheduled_at: appt.scheduled_at,
        service_name: Map.get(service_map, appt.service_type_id, "Service"),
        customer_name: Map.get(customer_map, appt.customer_id, "Customer"),
        duration_minutes: appt.duration_minutes,
        actual_minutes: Map.get(checklist_times, appt.id),
        price_cents: appt.price_cents
      }
    end)
  end

  # --- Private ---

  defp load_service_map(appointments) do
    ids = appointments |> Enum.map(& &1.service_type_id) |> Enum.uniq()
    if ids == [], do: %{}, else:
      ServiceType |> Ash.Query.filter(id in ^ids) |> Ash.read!() |> Map.new(&{&1.id, &1.name})
  end

  defp load_customer_map(appointments) do
    ids = appointments |> Enum.map(& &1.customer_id) |> Enum.uniq()
    if ids == [], do: %{}, else:
      Customer |> Ash.Query.filter(id in ^ids) |> Ash.read!() |> Map.new(&{&1.id, &1.name})
  end

  defp load_checklist_times(appointments) do
    ids = Enum.map(appointments, & &1.id)
    if ids == [], do: %{}, else: do_load_checklist_times(ids)
  end

  defp do_load_checklist_times(appointment_ids) do
    checklists =
      AppointmentChecklist
      |> Ash.Query.filter(appointment_id in ^appointment_ids)
      |> Ash.read!()

    checklist_ids = Enum.map(checklists, & &1.id)

    if checklist_ids == [] do
      %{}
    else
      items =
        ChecklistItem
        |> Ash.Query.filter(checklist_id in ^checklist_ids and completed == true)
        |> Ash.read!()

      # Sum actual_seconds per checklist, convert to minutes
      items_by_checklist =
        items
        |> Enum.group_by(& &1.checklist_id)
        |> Map.new(fn {cl_id, items} ->
          total_seconds = items |> Enum.map(& &1.actual_seconds || 0) |> Enum.sum()
          {cl_id, div(total_seconds, 60)}
        end)

      # Map checklist → appointment
      checklists
      |> Map.new(fn cl ->
        {cl.appointment_id, Map.get(items_by_checklist, cl.id, 0)}
      end)
    end
  end
end
