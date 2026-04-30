defmodule MobileCarWashWeb.Admin.CashFlowProjectionsLive do
  @moduledoc """
  Cash-flow Projections page. Lets the admin override input numbers
  (income, expense, allocation percentages) and see the projected
  end-of-period balances per bucket.

  Lives at /admin/cash-flow/projections. Pairs with the Dashboard at
  /admin/cash-flow.
  """
  use MobileCarWashWeb, :live_view

  alias MobileCarWash.CashFlow
  alias MobileCarWash.CashFlow.Projections

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      CashFlow.Broadcaster.subscribe()
    end

    actuals = Projections.project()
    inputs = inputs_from_actuals(actuals)

    {:ok,
     assign(socket,
       page_title: "Cash Flow Projections",
       proj_actuals: actuals,
       proj_inputs: inputs,
       projections: Projections.compute(inputs),
       editing_field: nil
     )}
  end

  # Handles months + growth rate form (range slider + month select)
  @impl true
  def handle_event("adjust_projection", params, socket) do
    prev = socket.assigns.proj_inputs

    inputs = %{
      prev
      | months: parse_months_input(params["months"], prev.months),
        growth_rate: parse_growth_rate_input(params["growth_rate"], prev.growth_rate)
    }

    {:noreply, assign(socket, proj_inputs: inputs, projections: Projections.compute(inputs))}
  end

  # Enter edit mode for a stat field (click to edit)
  def handle_event("edit_field", %{"field" => field}, socket) do
    {:noreply, assign(socket, editing_field: field)}
  end

  # Commit the edited value (blur or Enter)
  def handle_event("commit_field", %{"field" => field, "value" => value}, socket) do
    prev = socket.assigns.proj_inputs

    inputs =
      case field do
        "plan_count_" <> plan_id ->
          updated =
            Enum.map(prev.plans, fn p ->
              if to_string(p.id) == plan_id,
                do: %{p | subscriber_count: parse_subscriber_count(value, p.subscriber_count)},
                else: p
            end)

          %{prev | plans: updated}

        "plan_price_" <> plan_id ->
          updated =
            Enum.map(prev.plans, fn p ->
              if to_string(p.id) == plan_id,
                do: %{p | price_cents: parse_dollar_input(value, p.price_cents)},
                else: p
            end)

          %{prev | plans: updated}

        "monthly_fixed_costs" ->
          %{prev | monthly_fixed_costs: parse_dollar_input(value, prev.monthly_fixed_costs)}

        "avg_variable_costs" ->
          %{prev | avg_variable_costs: parse_dollar_input(value, prev.avg_variable_costs)}

        "service_count_" <> svc_id ->
          updated =
            Enum.map(prev.services, fn s ->
              if to_string(s.id) == svc_id,
                do: %{s | avg_monthly_count: parse_count_input(value, s.avg_monthly_count)},
                else: s
            end)

          %{prev | services: updated}

        "service_price_" <> svc_id ->
          updated =
            Enum.map(prev.services, fn s ->
              if to_string(s.id) == svc_id,
                do: %{s | price_cents: parse_dollar_input(value, s.price_cents)},
                else: s
            end)

          %{prev | services: updated}

        _ ->
          prev
      end

    {:noreply,
     assign(socket,
       editing_field: nil,
       proj_inputs: inputs,
       projections: Projections.compute(inputs)
     )}
  end

  def handle_event("reset_projection", _params, socket) do
    inputs = inputs_from_actuals(socket.assigns.proj_actuals)
    {:noreply, assign(socket, proj_inputs: inputs, projections: Projections.compute(inputs))}
  end

  @impl true
  def handle_info(:cash_flow_updated, socket) do
    actuals = Projections.project()
    inputs = inputs_from_actuals(actuals)

    {:noreply,
     assign(socket,
       proj_actuals: actuals,
       proj_inputs: inputs,
       projections: Projections.compute(inputs)
     )}
  end

  attr :field, :string, required: true
  attr :label, :string, required: true
  attr :value_cents, :integer, required: true
  attr :actual_cents, :integer, required: true
  attr :editing_field, :string, default: nil
  attr :color, :string, default: "base-content"
  attr :desc, :string, default: nil
  attr :editable, :boolean, default: true

  defp proj_stat(assigns) do
    ~H"""
    <div class={[
      "stat bg-base-100 shadow rounded-xl p-4",
      @editable && @editing_field == @field && "ring-2 ring-primary ring-offset-1"
    ]}>
      <div class="stat-title text-xs flex items-center justify-between">
        <span>{@label}</span>
        <span
          :if={@value_cents != @actual_cents}
          class="text-warning text-xs font-semibold normal-case"
        >
          {if @editable, do: "edited", else: "modified"}
        </span>
      </div>
      <div class="stat-value text-2xl leading-tight mt-1">
        <!-- Display mode -->
        <span
          :if={!@editable || @editing_field != @field}
          phx-click={if @editable, do: "edit_field"}
          phx-value-field={if @editable, do: @field}
          class={[
            @editable && "cursor-text hover:opacity-60",
            "transition-opacity",
            (@value_cents != @actual_cents && "text-warning") || "text-#{@color}"
          ]}
          title={if @editable, do: "Click to edit"}
        >
          ${cents_to_dollars_str(@value_cents)}
        </span>
        <!-- Edit mode (only when editable) -->
        <form
          :if={@editable && @editing_field == @field}
          id={"proj-field-#{@field}"}
          phx-submit="commit_field"
          class="flex items-center gap-0.5"
        >
          <input type="hidden" name="field" value={@field} />
          <span class="text-base-content/30 text-lg font-normal">$</span>
          <input
            type="number"
            name="value"
            value={cents_to_dollars_str(@value_cents)}
            min="0"
            step="1"
            autofocus
            phx-blur={JS.dispatch("submit", to: "#proj-field-#{@field}")}
            class="input input-ghost input-sm w-28 font-bold text-xl p-0 h-auto focus:outline-none"
          />
        </form>
      </div>
      <div class="stat-desc text-xs mt-1">
        <span :if={@desc}>{@desc}</span>
        <span :if={@value_cents != @actual_cents} class="text-warning/80">
          {if @desc, do: " · "}actual: ${cents_to_dollars_str(@actual_cents)}
        </span>
      </div>
    </div>
    """
  end

  attr :plan, :map, required: true
  attr :actual, :map, required: true
  attr :editing_field, :string, default: nil

  defp proj_plan_row(assigns) do
    ~H"""
    <tr class="border-b border-base-200 last:border-0">
      <td class="py-3 font-semibold text-sm">{@plan.name}</td>
      
    <!-- Subscriber count -->
      <td class="py-3 text-right">
        <span
          :if={@editing_field != "plan_count_#{@plan.id}"}
          phx-click="edit_field"
          phx-value-field={"plan_count_#{@plan.id}"}
          class={[
            "cursor-text font-mono text-sm transition-opacity hover:opacity-60",
            (@plan.subscriber_count != @actual.subscriber_count && "text-warning") || ""
          ]}
          title="Click to edit"
        >
          {@plan.subscriber_count}
        </span>
        <form
          :if={@editing_field == "plan_count_#{@plan.id}"}
          id={"proj-field-plan_count_#{@plan.id}"}
          phx-submit="commit_field"
          class="inline-flex items-center gap-1 justify-end"
        >
          <input type="hidden" name="field" value={"plan_count_#{@plan.id}"} />
          <input
            type="number"
            name="value"
            value={@plan.subscriber_count}
            min="0"
            step="1"
            autofocus
            phx-blur={JS.dispatch("submit", to: "#proj-field-plan_count_#{@plan.id}")}
            class="input input-ghost input-xs w-14 font-mono text-sm p-0 text-right focus:outline-none"
          />
        </form>
        <span class="text-base-content/70 text-xs ml-1">subs</span>
      </td>

      <td class="py-3 text-center text-base-content/30 text-sm px-1">×</td>
      
    <!-- Price per month -->
      <td class="py-3">
        <span
          :if={@editing_field != "plan_price_#{@plan.id}"}
          phx-click="edit_field"
          phx-value-field={"plan_price_#{@plan.id}"}
          class={[
            "cursor-text font-mono text-sm transition-opacity hover:opacity-60",
            (@plan.price_cents != @actual.price_cents && "text-warning") || ""
          ]}
          title="Click to edit"
        >
          ${cents_to_dollars_str(@plan.price_cents)} / mo
        </span>
        <form
          :if={@editing_field == "plan_price_#{@plan.id}"}
          id={"proj-field-plan_price_#{@plan.id}"}
          phx-submit="commit_field"
          class="inline-flex items-center gap-0.5"
        >
          <input type="hidden" name="field" value={"plan_price_#{@plan.id}"} />
          <span class="text-base-content/30 text-xs">$</span>
          <input
            type="number"
            name="value"
            value={cents_to_dollars_str(@plan.price_cents)}
            min="0"
            step="1"
            autofocus
            phx-blur={JS.dispatch("submit", to: "#proj-field-plan_price_#{@plan.id}")}
            class="input input-ghost input-xs w-14 font-mono text-sm p-0 focus:outline-none"
          />
          <span class="text-base-content/30 text-xs">/ mo</span>
        </form>
      </td>

      <td class="py-3 text-center text-base-content/30 text-sm px-1">=</td>
      
    <!-- Monthly MRR contribution -->
      <td class="py-3 text-right font-mono text-sm font-semibold">
        <span class={[
          @plan.subscriber_count != @actual.subscriber_count ||
            (@plan.price_cents != @actual.price_cents && "text-warning")
        ]}>
          ${format_cents(@plan.subscriber_count * @plan.price_cents)}
        </span>
      </td>
      
    <!-- actual note -->
      <td class="py-3 pl-4 text-xs text-base-content/30 whitespace-nowrap">
        <span :if={
          @plan.subscriber_count != @actual.subscriber_count ||
            @plan.price_cents != @actual.price_cents
        }>
          actual: {@actual.subscriber_count} × ${cents_to_dollars_str(@actual.price_cents)}
        </span>
      </td>
    </tr>
    """
  end

  attr :service, :map, required: true
  attr :actual, :map, required: true
  attr :editing_field, :string, default: nil

  defp proj_service_row(assigns) do
    ~H"""
    <tr class="border-b border-base-200 last:border-0">
      <td class="py-3 font-semibold text-sm">{@service.name}</td>
      
    <!-- Count/month -->
      <td class="py-3 text-right">
        <span
          :if={@editing_field != "service_count_#{@service.id}"}
          phx-click="edit_field"
          phx-value-field={"service_count_#{@service.id}"}
          class={[
            "cursor-text font-mono text-sm transition-opacity hover:opacity-60",
            (@service.avg_monthly_count != @actual.avg_monthly_count && "text-warning") || ""
          ]}
          title="Click to edit"
        >
          {format_count(@service.avg_monthly_count)} / mo
        </span>
        <form
          :if={@editing_field == "service_count_#{@service.id}"}
          id={"proj-field-service_count_#{@service.id}"}
          phx-submit="commit_field"
          class="inline-flex items-center gap-1 justify-end"
        >
          <input type="hidden" name="field" value={"service_count_#{@service.id}"} />
          <input
            type="number"
            name="value"
            value={@service.avg_monthly_count}
            min="0"
            step="0.1"
            autofocus
            phx-blur={JS.dispatch("submit", to: "#proj-field-service_count_#{@service.id}")}
            class="input input-ghost input-xs w-16 font-mono text-sm p-0 text-right focus:outline-none"
          />
          <span class="text-base-content/70 text-xs">/ mo</span>
        </form>
      </td>

      <td class="py-3 text-center text-base-content/30 text-sm px-1">×</td>
      
    <!-- Price per wash -->
      <td class="py-3">
        <span
          :if={@editing_field != "service_price_#{@service.id}"}
          phx-click="edit_field"
          phx-value-field={"service_price_#{@service.id}"}
          class={[
            "cursor-text font-mono text-sm transition-opacity hover:opacity-60",
            (@service.price_cents != @actual.price_cents && "text-warning") || ""
          ]}
          title="Click to edit"
        >
          ${cents_to_dollars_str(@service.price_cents)}
        </span>
        <form
          :if={@editing_field == "service_price_#{@service.id}"}
          id={"proj-field-service_price_#{@service.id}"}
          phx-submit="commit_field"
          class="inline-flex items-center gap-0.5"
        >
          <input type="hidden" name="field" value={"service_price_#{@service.id}"} />
          <span class="text-base-content/30 text-xs">$</span>
          <input
            type="number"
            name="value"
            value={cents_to_dollars_str(@service.price_cents)}
            min="0"
            step="1"
            autofocus
            phx-blur={JS.dispatch("submit", to: "#proj-field-service_price_#{@service.id}")}
            class="input input-ghost input-xs w-16 font-mono text-sm p-0 focus:outline-none"
          />
        </form>
      </td>

      <td class="py-3 text-center text-base-content/30 text-sm px-1">=</td>
      
    <!-- Monthly revenue contribution -->
      <td class="py-3 text-right font-mono text-sm font-semibold">
        <span class={[
          @service.avg_monthly_count != @actual.avg_monthly_count ||
            (@service.price_cents != @actual.price_cents && "text-warning")
        ]}>
          ${format_cents(round(@service.avg_monthly_count * @service.price_cents))}
        </span>
      </td>
      
    <!-- "actual" note if modified -->
      <td class="py-3 pl-4 text-xs text-base-content/30 whitespace-nowrap">
        <span :if={
          @service.avg_monthly_count != @actual.avg_monthly_count ||
            @service.price_cents != @actual.price_cents
        }>
          actual: {format_count(@actual.avg_monthly_count)} × ${cents_to_dollars_str(
            @actual.price_cents
          )}
        </span>
      </td>
    </tr>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto py-8 px-4">
      <div class="bg-base-300 border-b border-cyan-500/30 -mx-4 mb-6 sm:mb-8">
        <div class="max-w-7xl mx-auto px-4 py-5 flex items-center justify-between">
          <div class="flex items-center gap-3">
            <.icon name="hero-banknotes" class="h-6 w-6 text-cyan-500" />
            <div>
              <h1 class="text-2xl font-bold text-base-content">Projections</h1>
              <p class="text-xs text-base-content/60">12-month forward look</p>
            </div>
          </div>
          <.link navigate={~p"/admin/cash-flow"} class="btn btn-ghost btn-sm">
            ← Back to Dashboard
          </.link>
        </div>
      </div>
      
    <!-- Loading state (before first switch) -->
      <div :if={is_nil(@proj_inputs)} class="text-center py-12 text-base-content/70">
        Loading projections…
      </div>

      <div :if={@proj_inputs}>
        <!-- Projection Settings (months + growth rate) -->
        <form phx-change="adjust_projection" class="card bg-base-100 shadow mb-6">
          <div class="card-body p-5">
            <div class="flex flex-wrap gap-6 items-end justify-between">
              <div class="flex flex-wrap gap-6 items-end">
                <div>
                  <label class="label text-sm font-semibold pb-1">Months to project</label>
                  <div class="tabs tabs-boxed">
                    <button
                      :for={m <- [3, 6, 12]}
                      type="button"
                      class={["tab", @proj_inputs.months == m && "tab-active"]}
                      phx-click="adjust_projection"
                      phx-value-months={m}
                      phx-value-growth_rate={round(@proj_inputs.growth_rate * 100)}
                    >
                      {m}mo
                    </button>
                  </div>
                </div>
                <div>
                  <label class="label text-sm font-semibold pb-1">
                    Monthly growth rate
                    <span class="label-text-alt text-base-content/70 ml-1">(0 = flat)</span>
                  </label>
                  <div class="flex items-center gap-2">
                    <input
                      type="range"
                      name="growth_rate"
                      min="0"
                      max="20"
                      step="1"
                      value={round(@proj_inputs.growth_rate * 100)}
                      class="range range-primary range-sm w-36"
                      phx-debounce="200"
                    />
                    <span class="font-bold w-10 text-right">
                      {round(@proj_inputs.growth_rate * 100)}%
                    </span>
                  </div>
                </div>
              </div>
              <div class="flex items-end gap-3">
                <p :if={@proj_actuals} class="text-xs text-base-content/70 mb-1">
                  {@proj_actuals.active_subscription_count} active subs ·
                  last {@proj_actuals.lookback_days}d avg
                </p>
                <button
                  :if={inputs_modified?(@proj_inputs, @proj_actuals)}
                  type="button"
                  phx-click="reset_projection"
                  class="btn btn-ghost btn-xs text-warning"
                >
                  Reset to actual
                </button>
              </div>
            </div>
          </div>
        </form>
        
    <!-- Key Metrics — click editable values to change them -->
        <div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-5 gap-4 mb-6">
          <.proj_stat
            field="mrr"
            label="Monthly MRR"
            value_cents={@projections.mrr}
            actual_cents={@proj_actuals.mrr}
            editing_field={@editing_field}
            color="primary"
            desc="from plans below"
            editable={false}
          />
          <.proj_stat
            field="avg_one_time_income"
            label="One-Time Income / mo"
            value_cents={@projections.avg_one_time_income}
            actual_cents={@proj_actuals.avg_one_time_income}
            editing_field={@editing_field}
            color="success"
            desc="from services below"
            editable={false}
          />
          <.proj_stat
            field="monthly_fixed_costs"
            label="Fixed Costs / mo"
            value_cents={@proj_inputs.monthly_fixed_costs}
            actual_cents={@proj_actuals.monthly_fixed_costs}
            editing_field={@editing_field}
            color="error"
            desc="opex + salary"
          />
          <.proj_stat
            field="avg_variable_costs"
            label="Variable Costs / mo"
            value_cents={@proj_inputs.avg_variable_costs}
            actual_cents={@proj_actuals.avg_variable_costs}
            editing_field={@editing_field}
            color="warning"
            desc="supplies & misc"
          />
          <.proj_stat
            field="avg_wash_price"
            label="Avg Wash Price"
            value_cents={@projections.avg_wash_price}
            actual_cents={@proj_actuals.avg_wash_price}
            editing_field={@editing_field}
            color="info"
            desc="weighted avg"
            editable={false}
          />
        </div>
        
    <!-- Subscription Plan Breakdown — click subscriber count or price to edit -->
        <div class="card bg-base-100 shadow mb-6">
          <div class="card-body p-5">
            <h3 class="font-semibold text-sm mb-3">
              Subscription Plans
              <span class="text-base-content/70 text-xs font-normal ml-1">
                — click subscriber count or price to edit
              </span>
            </h3>
            <table class="table table-sm">
              <thead>
                <tr class="text-xs text-base-content/70 uppercase tracking-wide">
                  <th>Plan</th>
                  <th class="text-right">Subscribers</th>
                  <th></th>
                  <th>Price / mo</th>
                  <th></th>
                  <th class="text-right">Monthly MRR</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                <.proj_plan_row
                  :for={plan <- @proj_inputs.plans}
                  plan={plan}
                  actual={Enum.find(@proj_actuals.plans, &(&1.id == plan.id)) || plan}
                  editing_field={@editing_field}
                />
              </tbody>
              <tfoot>
                <tr class="border-t-2 border-base-300 font-semibold">
                  <td colspan="5" class="pt-3 text-sm text-base-content/80">
                    Total MRR
                  </td>
                  <td class="pt-3 text-right font-mono text-sm">
                    ${format_cents(@projections.mrr)}
                  </td>
                  <td></td>
                </tr>
              </tfoot>
            </table>
          </div>
        </div>
        
    <!-- Service Breakdown — click count or price to edit -->
        <div class="card bg-base-100 shadow mb-6">
          <div class="card-body p-5">
            <h3 class="font-semibold text-sm mb-3">
              Service Revenue Breakdown
              <span class="text-base-content/70 text-xs font-normal ml-1">
                — click count or price to edit
              </span>
            </h3>
            <table class="table table-sm">
              <thead>
                <tr class="text-xs text-base-content/70 uppercase tracking-wide">
                  <th>Service</th>
                  <th class="text-right">Avg / mo</th>
                  <th></th>
                  <th>Price / wash</th>
                  <th></th>
                  <th class="text-right">Monthly Revenue</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                <.proj_service_row
                  :for={svc <- @proj_inputs.services}
                  service={svc}
                  actual={Enum.find(@proj_actuals.services, &(&1.id == svc.id)) || svc}
                  editing_field={@editing_field}
                />
              </tbody>
              <tfoot>
                <tr class="border-t-2 border-base-300 font-semibold">
                  <td colspan="5" class="pt-3 text-sm text-base-content/80">
                    Total one-time revenue
                  </td>
                  <td class="pt-3 text-right font-mono text-sm">
                    ${format_cents(@projections.avg_one_time_income)}
                  </td>
                  <td></td>
                </tr>
              </tfoot>
            </table>
          </div>
        </div>
        
    <!-- Break-Even Card -->
        <div class="card bg-base-100 shadow mb-6">
          <div class="card-body p-5">
            <h3 class="font-bold text-base mb-3">Break-Even Analysis</h3>
            <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
              <div>
                <p class="text-xs text-base-content/70 mb-1">Total monthly costs to cover</p>
                <p class="text-2xl font-bold">
                  ${format_cents(@projections.break_even.total_monthly_costs)}
                </p>
              </div>
              <div>
                <p class="text-xs text-base-content/70 mb-1">MRR covers</p>
                <div class="flex items-center gap-3">
                  <p class="text-2xl font-bold text-primary">
                    {@projections.break_even.mrr_coverage_pct}%
                  </p>
                  <div class="flex-1">
                    <progress
                      class="progress progress-primary w-full"
                      value={min(trunc(@projections.break_even.mrr_coverage_pct), 100)}
                      max="100"
                    />
                  </div>
                </div>
              </div>
              <div>
                <p class="text-xs text-base-content/70 mb-1">Additional washes needed/month</p>
                <p class="text-2xl font-bold text-warning">
                  {if @projections.break_even.washes_needed_per_month,
                    do: @projections.break_even.washes_needed_per_month,
                    else: "—"}
                </p>
                <p class="text-xs text-base-content/70 mt-1">
                  at avg ${format_cents(@projections.avg_wash_price)} / wash
                </p>
              </div>
            </div>
          </div>
        </div>
        
    <!-- Month-by-Month Projection Table -->
        <div class="card bg-base-100 shadow">
          <div class="card-body p-0">
            <div class="p-5 pb-2">
              <h3 class="font-bold text-base">
                {if @proj_inputs.growth_rate > 0,
                  do:
                    "#{@proj_inputs.months}-Month Projection (#{round(@proj_inputs.growth_rate * 100)}% monthly growth)",
                  else: "#{@proj_inputs.months}-Month Projection (flat baseline)"}
              </h3>
              <p class="text-xs text-base-content/70 mt-1">
                MRR stays flat; one-time wash revenue grows by the growth rate compounded monthly.
              </p>
            </div>
            <div class="overflow-x-auto">
              <table class="table table-sm">
                <thead class="bg-base-200">
                  <tr>
                    <th>Month</th>
                    <th class="text-right">Revenue</th>
                    <th class="text-right text-primary">MRR</th>
                    <th class="text-right">One-time</th>
                    <th class="text-right text-error">Fixed</th>
                    <th class="text-right text-warning">Variable</th>
                    <th class="text-right font-bold">Net Profit</th>
                    <th class="text-right">Margin</th>
                    <th class="text-right text-base-content/70">Cumulative</th>
                  </tr>
                </thead>
                <tbody>
                  <tr
                    :for={row <- @projections.monthly}
                    class={[
                      "border-b border-base-200",
                      (row.net_profit >= 0 && "hover:bg-success/5") || "hover:bg-error/5"
                    ]}
                  >
                    <td class="font-semibold text-sm">{row.month_label}</td>
                    <td class="text-right text-sm font-mono">
                      ${format_cents(row.projected_income)}
                    </td>
                    <td class="text-right text-sm font-mono text-primary">
                      ${format_cents(row.mrr_component)}
                    </td>
                    <td class="text-right text-sm font-mono text-base-content/80">
                      ${format_cents(row.one_time_component)}
                    </td>
                    <td class="text-right text-sm font-mono text-error">
                      ${format_cents(row.fixed_costs)}
                    </td>
                    <td class="text-right text-sm font-mono text-warning">
                      ${format_cents(row.variable_costs)}
                    </td>
                    <td class={[
                      "text-right text-sm font-bold font-mono",
                      (row.net_profit >= 0 && "text-success") || "text-error"
                    ]}>
                      {if row.net_profit < 0, do: "-"}${format_cents(abs(row.net_profit))}
                    </td>
                    <td class={[
                      "text-right text-sm",
                      (row.margin_pct >= 0 && "text-success") || "text-error"
                    ]}>
                      {row.margin_pct}%
                    </td>
                    <td class={[
                      "text-right text-sm font-mono",
                      (row.cumulative_profit >= 0 && "text-success/70") || "text-error/70"
                    ]}>
                      {if row.cumulative_profit < 0, do: "-"}${format_cents(
                        abs(row.cumulative_profit)
                      )}
                    </td>
                  </tr>
                </tbody>
                <tfoot class="bg-base-200 font-bold">
                  <tr>
                    <td colspan="6" class="text-sm">Total ({@proj_inputs.months} months)</td>
                    <td class={[
                      "text-right text-sm font-mono",
                      (List.last(@projections.monthly).cumulative_profit >= 0 && "text-success") ||
                        "text-error"
                    ]}>
                      <% final = List.last(@projections.monthly).cumulative_profit %>
                      {if final < 0, do: "-"}${format_cents(abs(final))}
                    </td>
                    <td colspan="2"></td>
                  </tr>
                </tfoot>
              </table>
            </div>
          </div>
        </div>
      </div>
      <!-- end :if proj_inputs loaded -->
    </div>
    """
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp inputs_from_actuals(actuals) do
    %{
      plans: actuals.plans,
      services: actuals.services,
      monthly_fixed_costs: actuals.monthly_fixed_costs,
      avg_variable_costs: actuals.avg_variable_costs,
      months: 6,
      growth_rate: 0.0
    }
  end

  defp inputs_modified?(inputs, actuals) when is_map(inputs) and is_map(actuals) do
    inputs.monthly_fixed_costs != actuals.monthly_fixed_costs or
      inputs.avg_variable_costs != actuals.avg_variable_costs or
      inputs.months != 6 or
      inputs.growth_rate != 0.0 or
      plans_modified?(inputs.plans, actuals.plans) or
      services_modified?(inputs.services, actuals.services)
  end

  defp inputs_modified?(_, _), do: false

  defp plans_modified?(a, b) when length(a) == length(b) do
    Enum.any?(Enum.zip(a, b), fn {ia, ib} ->
      ia.subscriber_count != ib.subscriber_count or ia.price_cents != ib.price_cents
    end)
  end

  defp plans_modified?(_, _), do: true

  defp services_modified?(a, b) when length(a) == length(b) do
    Enum.any?(Enum.zip(a, b), fn {ia, ib} ->
      ia.avg_monthly_count != ib.avg_monthly_count or ia.price_cents != ib.price_cents
    end)
  end

  defp services_modified?(_, _), do: true

  defp parse_dollar_input(str, fallback) when is_binary(str) do
    case Float.parse(str) do
      {n, _} when n >= 0 -> trunc(n * 100)
      _ -> fallback
    end
  end

  defp parse_dollar_input(_, fallback), do: fallback

  defp parse_months_input(str, fallback) when is_binary(str) do
    case Integer.parse(str) do
      {n, ""} when n in [3, 6, 12] -> n
      _ -> fallback
    end
  end

  defp parse_months_input(_, fallback), do: fallback

  defp parse_growth_rate_input(str, fallback) when is_binary(str) do
    case Float.parse(str) do
      {r, _} when r >= 0.0 and r <= 20.0 -> r / 100.0
      _ -> fallback
    end
  end

  defp parse_growth_rate_input(_, fallback), do: fallback

  defp parse_count_input(str, fallback) when is_binary(str) do
    case Float.parse(str) do
      {n, _} when n >= 0 -> Float.round(n, 1)
      _ -> fallback
    end
  end

  defp parse_count_input(_, fallback), do: fallback

  defp parse_subscriber_count(str, fallback) when is_binary(str) do
    case Integer.parse(str) do
      {n, ""} when n >= 0 -> n
      _ -> fallback
    end
  end

  defp parse_subscriber_count(_, fallback), do: fallback

  defp format_count(n) when is_float(n) do
    if n == trunc(n) * 1.0, do: to_string(trunc(n)), else: Float.to_string(Float.round(n, 1))
  end

  defp format_count(n) when is_integer(n), do: to_string(n)
  defp format_count(_), do: "0"

  defp cents_to_dollars_str(cents) when is_integer(cents), do: to_string(div(cents, 100))
  defp cents_to_dollars_str(_), do: "0"

  defp format_cents(cents) when is_integer(cents) do
    dollars = div(cents, 100)
    remainder = rem(cents, 100)
    "#{dollars}.#{String.pad_leading("#{remainder}", 2, "0")}"
  end

  defp format_cents(_), do: "0.00"
end
