defmodule MobileCarWash.CashFlow.Projections do
  @moduledoc """
  Forward-looking income and profitability projections.

  Data sources:
    - Last 90 days of cash_flow_transactions — actual income/expense baseline
    - Active subscriptions × plan price — live MRR
    - CashFlow config — configured fixed monthly costs (opex + salary)
    - Active service types + appointment history — per-service revenue breakdown

  The projection model:
    - MRR stays flat (existing subscriber count) unless growth_rate is applied
    - One-time wash revenue is derived from per-service (count × price) and grows
      by `growth_rate` compounded each month
    - Fixed costs stay constant at config values
    - Variable costs stay at the 90-day historical average
  """

  alias MobileCarWash.CashFlow.Transaction
  alias MobileCarWash.Billing.{Subscription, SubscriptionPlan}
  alias MobileCarWash.Scheduling.{Appointment, ServiceType}

  require Ash.Query

  @lookback_days 90
  # How many months the lookback window represents
  @lookback_months @lookback_days / 30.0

  @doc """
  Builds a full projection report by loading actuals from DB then calling `compute/1`.

  Options:
    - `:months`      — how many months to project forward (default 6)
    - `:growth_rate` — expected monthly revenue growth as a decimal, e.g. 0.05 = 5% (default 0.0)

  Returns the `compute/1` result merged with DB-only fields:
  `active_subscription_count`, `avg_monthly_income`, `avg_monthly_expenses`, `lookback_days`.
  """
  def project(opts \\ []) do
    months = Keyword.get(opts, :months, 6)
    growth_rate = Keyword.get(opts, :growth_rate, 0.0)

    config = MobileCarWash.CashFlow.Engine.get_config!()

    plans = plan_actuals()
    cutoff = DateTime.add(DateTime.utc_now(), -@lookback_days * 86_400)
    services = service_actuals(cutoff)

    {avg_monthly_income, avg_monthly_expenses} = compute_monthly_averages()

    fixed_monthly = config.monthly_opex_cents + config.salary_cents
    avg_variable = Kernel.max(avg_monthly_expenses - fixed_monthly, 0)

    inputs = %{
      plans: plans,
      services: services,
      monthly_fixed_costs: fixed_monthly,
      avg_variable_costs: avg_variable,
      months: months,
      growth_rate: growth_rate
    }

    result = compute(inputs)

    sub_count = Enum.sum(Enum.map(plans, & &1.subscriber_count))

    Map.merge(result, %{
      active_subscription_count: sub_count,
      avg_monthly_income: avg_monthly_income,
      avg_monthly_expenses: avg_monthly_expenses,
      lookback_days: @lookback_days
    })
  end

  @doc """
  Pure projection computation — no DB queries.

  Accepts an inputs map:
    - `mrr`                — monthly recurring revenue in cents
    - `services`           — list of `%{id, name, avg_monthly_count, price_cents}`
    - `monthly_fixed_costs`— fixed monthly costs in cents (opex + salary)
    - `avg_variable_costs` — avg monthly variable costs in cents
    - `months`             — how many months to project (integer)
    - `growth_rate`        — monthly growth rate as decimal (0.05 = 5%)

  Derives `avg_one_time_income` and `avg_wash_price` from the `services` list.
  """
  def compute(%{} = inputs) do
    %{
      plans: plans,
      services: services,
      monthly_fixed_costs: fixed_monthly,
      avg_variable_costs: avg_variable,
      months: months,
      growth_rate: growth_rate
    } = inputs

    # MRR derived from per-plan subscriber counts and prices
    mrr = Enum.reduce(plans, 0, fn p, acc -> acc + p.subscriber_count * p.price_cents end)

    # Total one-time income = sum of (count × price) across all services
    avg_one_time =
      services
      |> Enum.reduce(0.0, fn s, acc -> acc + s.avg_monthly_count * s.price_cents end)
      |> round()

    # Weighted average wash price for break-even analysis
    total_count = Enum.sum(Enum.map(services, & &1.avg_monthly_count))

    avg_wash_price =
      if total_count > 0 and avg_one_time > 0 do
        div(avg_one_time, max(round(total_count), 1))
      else
        5000
      end

    today = Date.utc_today()

    {monthly, _} =
      Enum.map_reduce(1..months, 0, fn offset, cumulative ->
        month_start = shift_months(today, offset)

        compound = :math.pow(1.0 + growth_rate, offset)
        projected_one_time = round(avg_one_time * compound)
        projected_income = mrr + projected_one_time
        projected_expenses = fixed_monthly + avg_variable
        net_profit = projected_income - projected_expenses
        new_cumulative = cumulative + net_profit

        margin_pct =
          if projected_income > 0,
            do: Float.round(net_profit / projected_income * 100, 1),
            else: 0.0

        row = %{
          month_label: month_label(month_start),
          month_start: month_start,
          projected_income: projected_income,
          mrr_component: mrr,
          one_time_component: projected_one_time,
          projected_expenses: projected_expenses,
          fixed_costs: fixed_monthly,
          variable_costs: avg_variable,
          net_profit: net_profit,
          margin_pct: margin_pct,
          cumulative_profit: new_cumulative
        }

        {row, new_cumulative}
      end)

    break_even = break_even_analysis(fixed_monthly, avg_variable, mrr, avg_wash_price)

    %{
      plans: plans,
      mrr: mrr,
      services: services,
      avg_one_time_income: avg_one_time,
      avg_wash_price: avg_wash_price,
      monthly_fixed_costs: fixed_monthly,
      avg_variable_costs: avg_variable,
      months: months,
      growth_rate: growth_rate,
      monthly: monthly,
      break_even: break_even
    }
  end

  @doc "Live MRR: sum of active subscription plan prices."
  def compute_mrr do
    subs = Subscription |> Ash.Query.filter(status == :active) |> Ash.read!(authorize?: false)

    plan_ids = subs |> Enum.map(& &1.plan_id) |> Enum.uniq()

    plans =
      if plan_ids != [] do
        SubscriptionPlan
        |> Ash.Query.filter(id in ^plan_ids)
        |> Ash.read!()
        |> Map.new(&{&1.id, &1})
      else
        %{}
      end

    Enum.reduce(subs, 0, fn sub, acc ->
      plan = Map.get(plans, sub.plan_id)
      acc + (plan && plan.price_cents || 0)
    end)
  end

  # --- Private ---

  defp plan_actuals do
    plans =
      SubscriptionPlan
      |> Ash.Query.filter(active == true)
      |> Ash.Query.sort(:name)
      |> Ash.read!(authorize?: false)

    subs =
      Subscription
      |> Ash.Query.filter(status == :active)
      |> Ash.read!(authorize?: false)

    counts = Enum.frequencies_by(subs, & &1.plan_id)

    Enum.map(plans, fn plan ->
      %{
        id: plan.id,
        name: plan.name,
        price_cents: plan.price_cents,
        subscriber_count: Map.get(counts, plan.id, 0)
      }
    end)
  end

  defp service_actuals(cutoff) do
    service_types =
      ServiceType
      |> Ash.Query.filter(active == true)
      |> Ash.Query.sort(:name)
      |> Ash.read!(authorize?: false)

    appointments =
      Appointment
      |> Ash.Query.filter(status == :completed and scheduled_at >= ^cutoff and price_cents > 0)
      |> Ash.read!(authorize?: false)

    grouped = Enum.group_by(appointments, & &1.service_type_id)

    Enum.map(service_types, fn st ->
      appts = Map.get(grouped, st.id, [])
      avg_monthly_count = Float.round(length(appts) / @lookback_months, 1)

      %{
        id: st.id,
        name: st.name,
        avg_monthly_count: avg_monthly_count,
        price_cents: st.base_price_cents
      }
    end)
  end

  defp compute_monthly_averages do
    cutoff = DateTime.add(DateTime.utc_now(), -@lookback_days * 86_400)

    transactions =
      Transaction
      |> Ash.Query.filter(occurred_at >= ^cutoff)
      |> Ash.read!(authorize?: false)

    total_deposits =
      transactions
      |> Enum.filter(&(&1.type == :deposit))
      |> Enum.reduce(0, fn t, acc -> acc + t.amount_cents end)

    total_withdrawals =
      transactions
      |> Enum.filter(&(&1.type == :withdrawal))
      |> Enum.reduce(0, fn t, acc -> acc + t.amount_cents end)

    avg_income = round(total_deposits / @lookback_months)
    avg_expenses = round(total_withdrawals / @lookback_months)

    {avg_income, avg_expenses}
  end

  defp break_even_analysis(fixed_monthly, avg_variable, mrr, avg_wash_price) do
    total_monthly_costs = fixed_monthly + avg_variable

    wash_revenue_needed = Kernel.max(total_monthly_costs - mrr, 0)

    washes_needed =
      if avg_wash_price > 0,
        do: Float.ceil(wash_revenue_needed / avg_wash_price) |> trunc(),
        else: nil

    mrr_coverage_pct =
      if total_monthly_costs > 0,
        do: Float.round(mrr / total_monthly_costs * 100, 1),
        else: 0.0

    %{
      total_monthly_costs: total_monthly_costs,
      wash_revenue_needed: wash_revenue_needed,
      washes_needed_per_month: washes_needed,
      avg_wash_price: avg_wash_price,
      mrr_coverage_pct: mrr_coverage_pct,
      revenue_needed: total_monthly_costs
    }
  end

  defp shift_months(date, n), do: Date.add(date, n * 30)

  defp month_label(date), do: Calendar.strftime(date, "%b %Y")
end
