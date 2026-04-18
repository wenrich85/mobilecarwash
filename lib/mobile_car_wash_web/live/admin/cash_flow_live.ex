defmodule MobileCarWashWeb.Admin.CashFlowLive do
  @moduledoc """
  Admin page for cash flow management.
  Displays the 5-account system with animated SVG bucket diagram and real-time balance updates.
  """
  use MobileCarWashWeb, :live_view

  import MobileCarWashWeb.Admin.CashFlowComponents

  alias MobileCarWash.CashFlow
  alias MobileCarWash.CashFlow.{Engine, Projections}

  @impl true
  def mount(_params, _session, socket) do
    # Subscribe to cash flow updates
    if connected?(socket) do
      CashFlow.Broadcaster.subscribe()
    end

    socket =
      socket
      |> assign(page_title: "Cash Flow")
      |> assign(animations_enabled: true)
      |> assign(page: 1)
      |> assign(active_view: :dashboard)
      |> assign(proj_actuals: nil)
      |> assign(proj_inputs: nil)
      |> assign(projections: nil)
      |> assign(editing_field: nil)
      |> reload_data()

    {:ok, socket}
  end

  @impl true
  def handle_event("switch_view", %{"view" => view}, socket) do
    view_atom = String.to_existing_atom(view)

    socket =
      if view_atom == :projections and is_nil(socket.assigns.proj_actuals) do
        actuals = Projections.project()
        inputs = inputs_from_actuals(actuals)
        assign(socket,
          proj_actuals: actuals,
          proj_inputs: inputs,
          projections: Projections.compute(inputs),
          active_view: view_atom
        )
      else
        assign(socket, active_view: view_atom)
      end

    {:noreply, socket}
  end

  # Handles months + growth rate form (range slider + month select)
  def handle_event("adjust_projection", params, socket) do
    prev = socket.assigns.proj_inputs

    inputs = %{prev |
      months: parse_months_input(params["months"], prev.months),
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
     assign(socket, editing_field: nil, proj_inputs: inputs, projections: Projections.compute(inputs))}
  end

  def handle_event("reset_projection", _params, socket) do
    inputs = inputs_from_actuals(socket.assigns.proj_actuals)
    {:noreply, assign(socket, proj_inputs: inputs, projections: Projections.compute(inputs))}
  end

  def handle_event("open_modal", %{"modal" => modal}, socket) do
    {:noreply, assign(socket, active_modal: String.to_existing_atom(modal), form_error: nil)}
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply, assign(socket, active_modal: nil, form_error: nil)}
  end

  def handle_event("toggle_animations", _params, socket) do
    new_state = !socket.assigns.animations_enabled
    {:noreply, assign(socket, animations_enabled: new_state)}
  end

  def handle_event("next_page", _params, socket) do
    page = socket.assigns.page + 1
    {:noreply, socket |> assign(page: page) |> reload_data()}
  end

  def handle_event("prev_page", _params, socket) do
    page = max(1, socket.assigns.page - 1)
    {:noreply, socket |> assign(page: page) |> reload_data()}
  end

  def handle_event("transfer", %{"amount" => amount, "description" => description}, socket) do
    case parse_dollars_to_cents(amount) do
      {:ok, amount_cents} ->
        # Split 50/50 between Tax and Business Savings
        half = div(amount_cents, 2)
        other_half = amount_cents - half

        case Engine.manual_transfer(:business_savings, :expense, half, description) do
          {:ok, _} ->
            case Engine.manual_transfer(:tax, :expense, other_half, description) do
              {:ok, _} ->
                socket =
                  socket
                  |> reload_data()
                  |> assign(active_modal: nil, form_error: nil)
                  |> assign(animating_flows: [:savings_to_expense, :tax_to_expense])
                  |> put_flash(:info, "Transferred $#{amount} to Expense (50% each from Savings & Tax)")

                Process.send_after(self(), :clear_animations, 2500)
                {:noreply, socket}

              {:error, :insufficient_funds} ->
                {:noreply, assign(socket, form_error: "Insufficient funds in Tax Account")}

              {:error, reason} ->
                {:noreply, assign(socket, form_error: format_error(reason))}
            end

          {:error, :insufficient_funds} ->
            {:noreply, assign(socket, form_error: "Insufficient funds in Business Savings Account")}

          {:error, reason} ->
            {:noreply, assign(socket, form_error: format_error(reason))}
        end

      {:error, msg} ->
        {:noreply, assign(socket, form_error: msg)}
    end
  end

  def handle_event("deposit", %{"amount" => amount, "description" => description}, socket) do
    case parse_dollars_to_cents(amount) do
      {:ok, amount_cents} ->
        case Engine.record_deposit(amount_cents, description) do
          {:ok, _} ->
            socket =
              socket
              |> reload_data()
              |> assign(
                active_modal: nil,
                form_error: nil,
                animating_flows: [:expense_to_savings, :expense_to_tax]
              )
              |> put_flash(:info, "Income recorded: $#{amount}")

            # Clear animation after 2.5 seconds
            Process.send_after(self(), :clear_animations, 2500)

            {:noreply, socket}

          {:error, reason} ->
            {:noreply, assign(socket, form_error: format_error(reason))}
        end

      {:error, msg} ->
        {:noreply, assign(socket, form_error: msg)}
    end
  end

  def handle_event("withdraw", %{"amount" => amount, "description" => description}, socket) do
    case parse_dollars_to_cents(amount) do
      {:ok, amount_cents} ->
        case Engine.record_expense(amount_cents, description) do
          {:ok, _} ->
            {:noreply,
             socket
             |> reload_data()
             |> assign(active_modal: nil, form_error: nil)
             |> put_flash(:info, "Expense recorded: $#{amount}")}

          {:error, :insufficient_funds} ->
            {:noreply, assign(socket, form_error: "Insufficient funds in Expense Account")}

          {:error, reason} ->
            {:noreply, assign(socket, form_error: format_error(reason))}
        end

      {:error, msg} ->
        {:noreply, assign(socket, form_error: msg)}
    end
  end

  def handle_event("pay_salary", _params, socket) do
    case Engine.pay_salary() do
      {:ok, msg} ->
        {:noreply,
         socket
         |> reload_data()
         |> assign(active_modal: nil, animating_flows: [:expense_to_salary])
         |> put_flash(:info, msg)}

      {:error, :insufficient_funds} ->
        {:noreply, assign(socket, form_error: "Insufficient funds for salary")}

      {:error, reason} ->
        {:noreply, assign(socket, form_error: format_error(reason))}
    end
  end

  def handle_event(
        "update_config",
        %{"config" => config_params},
        socket
      ) do
    # Parse currency fields to cents
    attrs = %{
      monthly_opex_cents: parse_to_cents(config_params["monthly_opex_cents"]),
      salary_cents: parse_to_cents(config_params["salary_cents"]),
      investment_target_cents: parse_to_cents(config_params["investment_target_cents"])
    }

    case Engine.update_config(attrs) do
      {:ok, _config} ->
        {:noreply,
         socket
         |> reload_data()
         |> assign(active_modal: nil, form_error: nil)
         |> put_flash(:info, "Settings updated")}

      {:error, reason} ->
        {:noreply, assign(socket, form_error: format_error(reason))}
    end
  end

  @impl true
  def handle_info(:cash_flow_updated, socket) do
    socket = reload_data(socket)

    # Refresh projections if the tab is open — reload actuals and reset inputs
    socket =
      if socket.assigns.active_view == :projections and not is_nil(socket.assigns.proj_actuals) do
        actuals = Projections.project()
        inputs = inputs_from_actuals(actuals)
        assign(socket,
          proj_actuals: actuals,
          proj_inputs: inputs,
          projections: Projections.compute(inputs)
        )
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_info(:clear_animations, socket) do
    {:noreply, assign(socket, animating_flows: [])}
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
        <span :if={@value_cents != @actual_cents} class="text-warning text-xs font-semibold normal-case">
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
            @value_cents != @actual_cents && "text-warning" || "text-#{@color}"
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
            @plan.subscriber_count != @actual.subscriber_count && "text-warning" || ""
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
            @plan.price_cents != @actual.price_cents && "text-warning" || ""
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
            @plan.price_cents != @actual.price_cents && "text-warning"
        ]}>
          ${format_cents(@plan.subscriber_count * @plan.price_cents)}
        </span>
      </td>

      <!-- actual note -->
      <td class="py-3 pl-4 text-xs text-base-content/30 whitespace-nowrap">
        <span :if={@plan.subscriber_count != @actual.subscriber_count || @plan.price_cents != @actual.price_cents}>
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
            @service.avg_monthly_count != @actual.avg_monthly_count && "text-warning" || ""
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
            @service.price_cents != @actual.price_cents && "text-warning" || ""
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
            @service.price_cents != @actual.price_cents && "text-warning"
        ]}>
          ${format_cents(round(@service.avg_monthly_count * @service.price_cents))}
        </span>
      </td>

      <!-- "actual" note if modified -->
      <td class="py-3 pl-4 text-xs text-base-content/30 whitespace-nowrap">
        <span :if={@service.avg_monthly_count != @actual.avg_monthly_count || @service.price_cents != @actual.price_cents}>
          actual: {format_count(@actual.avg_monthly_count)} × ${cents_to_dollars_str(@actual.price_cents)}
        </span>
      </td>
    </tr>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto py-8 px-4">
      <!-- Header -->
      <div class="mb-6 bg-gradient-to-r from-primary-700 to-primary-900 text-secondary-50 rounded-2xl p-8 shadow-lg">
        <h1 class="text-4xl font-bold mb-2">💰 Cash Flow Management</h1>
        <p class="text-secondary-100 text-base">
          Donald Miller's 5-bucket system: Expense → Tax, Business Savings, Investment, Personal Salary
        </p>
      </div>

      <!-- View Tab Bar -->
      <div class="tabs tabs-boxed mb-6">
        <button
          class={["tab tab-lg font-semibold", @active_view == :dashboard && "tab-active"]}
          phx-click="switch_view"
          phx-value-view="dashboard"
        >
          Dashboard
        </button>
        <button
          class={["tab tab-lg font-semibold", @active_view == :projections && "tab-active"]}
          phx-click="switch_view"
          phx-value-view="projections"
        >
          Projections
        </button>
      </div>

      <!-- ============================================================ -->
      <!-- DASHBOARD VIEW -->
      <!-- ============================================================ -->
      <div :if={@active_view == :dashboard}>

      <!-- SVG Diagram with Toggle -->
      <div class="card bg-gradient-to-br from-secondary-50 to-tertiary-50 shadow-2xl mb-6 border border-tertiary-200 rounded-2xl">
        <div class="card-body">
          <div class="flex justify-between items-center mb-4">
            <h2 class="card-title text-2xl text-primary-700">5-Bucket Cash Flow System</h2>
            <label class="label cursor-pointer gap-3">
              <span class="label-text font-semibold text-primary-700">Enable Animations</span>
              <input
                type="checkbox"
                class="toggle toggle-primary"
                checked={@animations_enabled}
                phx-click="toggle_animations"
              />
            </label>
          </div>
          <.bucket_diagram
            accounts={@accounts}
            thresholds={@thresholds}
            config={@config}
            animating_flows={@animating_flows}
            animations_enabled={@animations_enabled}
          />
        </div>
      </div>

      <!-- Action Buttons -->
      <div class="flex gap-3 mb-8 flex-wrap">
        <button
          type="button"
          class="btn btn-sm text-white font-semibold shadow-lg hover:shadow-xl transition-all"
          style="background-color: #27AE60; border-color: #27AE60;"
          phx-click="open_modal"
          phx-value-modal="deposit"
        >
          + Record Income
        </button>

        <button
          type="button"
          class="btn btn-sm text-white font-semibold shadow-lg hover:shadow-xl transition-all"
          style="background-color: #E74C3C; border-color: #E74C3C;"
          phx-click="open_modal"
          phx-value-modal="withdrawal"
        >
          - Record Expense
        </button>

        <button
          type="button"
          class="btn btn-sm text-white font-semibold shadow-lg hover:shadow-xl transition-all"
          style="background-color: #E8A03C; border-color: #E8A03C;"
          phx-click="open_modal"
          phx-value-modal="transfer"
        >
          ↩ Rebalance to Expense
        </button>

        <button
          type="button"
          class="btn btn-sm text-white font-semibold shadow-lg hover:shadow-xl transition-all"
          style="background-color: #3A7CA5; border-color: #3A7CA5;"
          phx-click="pay_salary"
        >
          💰 Pay Salary
        </button>

        <button
          type="button"
          class="btn btn-sm text-white font-semibold shadow-lg hover:shadow-xl transition-all"
          style="background-color: #1E2A38; border-color: #1E2A38;"
          phx-click="open_modal"
          phx-value-modal="config"
        >
          ⚙️ Settings
        </button>
      </div>

      <!-- Thresholds Info -->
      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4 mb-8">
        <div class="stat bg-gradient-to-br from-green-50 to-emerald-50 shadow-lg rounded-xl border border-green-200 p-6">
          <div class="stat-title text-sm font-semibold text-green-900">Expense Threshold</div>
          <div class="stat-value text-green-600 text-2xl font-bold">
            ${format_cents(@thresholds.expense)}
          </div>
          <div class="stat-desc text-xs text-green-700">= Monthly Opex × 1.25</div>
        </div>

        <div class="stat bg-gradient-to-br from-blue-50 to-cyan-50 shadow-lg rounded-xl border border-blue-200 p-6">
          <div class="stat-title text-sm font-semibold text-blue-900">Savings Threshold</div>
          <div class="stat-value text-blue-600 text-2xl font-bold">
            ${format_cents(@thresholds.business_savings)}
          </div>
          <div class="stat-desc text-xs text-blue-700">= Expense Threshold × 4</div>
        </div>

        <div class="stat bg-gradient-to-br from-amber-50 to-yellow-50 shadow-lg rounded-xl border border-amber-200 p-6">
          <div class="stat-title text-sm font-semibold text-amber-900">Investment Target</div>
          <div class="stat-value text-amber-600 text-2xl font-bold">
            ${format_cents(@config.investment_target_cents)}
          </div>
          <div class="stat-desc text-xs text-amber-700">User-defined goal</div>
        </div>
      </div>

      <!-- Recent Transactions -->
      <div class="card bg-gradient-to-br from-secondary-50 to-base-100 shadow-2xl border border-secondary-200 rounded-2xl">
        <div class="card-body">
          <h2 class="card-title text-2xl text-primary-700 mb-4">📋 Recent Transactions</h2>

          <div class="overflow-x-auto">
            <table class="table table-sm">
              <thead class="bg-primary-100 text-primary-900">
                <tr>
                  <th class="text-sm font-bold">Type</th>
                  <th class="text-sm font-bold">Amount</th>
                  <th class="text-sm font-bold">Description</th>
                  <th class="text-sm font-bold">Date</th>
                </tr>
              </thead>

              <tbody>
                <tr :for={txn <- @recent_txns} class="hover:bg-primary-50 border-b border-secondary-200">
                  <td class="text-sm">
                    <span class={["badge badge-sm font-bold", type_badge_class(txn.type)]}>
                      {format_type(txn.type)}
                    </span>
                  </td>
                  <td class="text-sm font-mono font-bold text-primary-700">${format_cents(txn.amount_cents)}</td>
                  <td class="text-xs text-base-content/70">{txn.description}</td>
                  <td class="text-xs text-base-content/80">
                    {Calendar.strftime(txn.inserted_at, "%m/%d %H:%M")}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <p :if={@recent_txns == []} class="text-center text-base-content/70 py-8 text-lg">
            No transactions yet
          </p>

          <!-- Pagination -->
          <div :if={@total_txn_count > 0} class="flex items-center justify-between mt-6 pt-4 border-t border-secondary-200">
            <span class="text-sm text-base-content/70">
              Page {[@page]} of {[@max_page]} ({[@total_txn_count]} total)
            </span>
            <div class="flex gap-2">
              <button
                class="btn btn-sm btn-outline"
                phx-click="prev_page"
                disabled={@page == 1}
              >
                ← Previous
              </button>
              <button
                class="btn btn-sm btn-outline"
                phx-click="next_page"
                disabled={@page >= @max_page}
              >
                Next →
              </button>
            </div>
          </div>
        </div>
      </div>

      <!-- Modals -->
      <.deposit_modal active_modal={@active_modal} form_error={@form_error} config={@config} />
      <.withdraw_modal active_modal={@active_modal} form_error={@form_error} config={@config} />
      <.transfer_modal active_modal={@active_modal} form_error={@form_error} accounts={@accounts} />
      <.config_modal active_modal={@active_modal} form_error={@form_error} config={@config} />

      </div><!-- end :dashboard -->

      <!-- ============================================================ -->
      <!-- PROJECTIONS VIEW -->
      <!-- ============================================================ -->
      <div :if={@active_view == :projections}>

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
                  <p class="text-2xl font-bold">${format_cents(@projections.break_even.total_monthly_costs)}</p>
                </div>
                <div>
                  <p class="text-xs text-base-content/70 mb-1">MRR covers</p>
                  <div class="flex items-center gap-3">
                    <p class="text-2xl font-bold text-primary">{@projections.break_even.mrr_coverage_pct}%</p>
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
                    do: "#{@proj_inputs.months}-Month Projection (#{round(@proj_inputs.growth_rate * 100)}% monthly growth)",
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
                    <tr :for={row <- @projections.monthly}
                        class={["border-b border-base-200",
                          row.net_profit >= 0 && "hover:bg-success/5" || "hover:bg-error/5"]}>
                      <td class="font-semibold text-sm">{row.month_label}</td>
                      <td class="text-right text-sm font-mono">${format_cents(row.projected_income)}</td>
                      <td class="text-right text-sm font-mono text-primary">${format_cents(row.mrr_component)}</td>
                      <td class="text-right text-sm font-mono text-base-content/80">${format_cents(row.one_time_component)}</td>
                      <td class="text-right text-sm font-mono text-error">${format_cents(row.fixed_costs)}</td>
                      <td class="text-right text-sm font-mono text-warning">${format_cents(row.variable_costs)}</td>
                      <td class={["text-right text-sm font-bold font-mono",
                        row.net_profit >= 0 && "text-success" || "text-error"]}>
                        {if row.net_profit < 0, do: "-"}${format_cents(abs(row.net_profit))}
                      </td>
                      <td class={["text-right text-sm",
                        row.margin_pct >= 0 && "text-success" || "text-error"]}>
                        {row.margin_pct}%
                      </td>
                      <td class={["text-right text-sm font-mono",
                        row.cumulative_profit >= 0 && "text-success/70" || "text-error/70"]}>
                        {if row.cumulative_profit < 0, do: "-"}${format_cents(abs(row.cumulative_profit))}
                      </td>
                    </tr>
                  </tbody>
                  <tfoot class="bg-base-200 font-bold">
                    <tr>
                      <td colspan="6" class="text-sm">Total ({@proj_inputs.months} months)</td>
                      <td class={["text-right text-sm font-mono",
                        List.last(@projections.monthly).cumulative_profit >= 0 && "text-success" || "text-error"]}>
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
        </div><!-- end :if proj_inputs loaded -->
      </div><!-- end :projections -->

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

  defp reload_data(socket) do
    config = CashFlow.get_config!()
    thresholds = Engine.compute_thresholds(config)

    accounts = Engine.get_all_accounts!()

    account_map =
      accounts
      |> Enum.map(&{&1.account_type, &1})
      |> Map.new()

    page = socket.assigns[:page] || 1
    per_page = 20
    offset = (page - 1) * per_page

    # Get total transaction count for pagination
    total_txn_count =
      CashFlow.Transaction
      |> Ash.Query.select([:id])
      |> Ash.read!()
      |> length()

    recent_txns =
      CashFlow.Transaction
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.Query.limit(per_page)
      |> Ash.Query.offset(offset)
      |> Ash.read!()

    max_page = ceil(total_txn_count / per_page)

    assign(socket,
      accounts: account_map,
      config: config,
      thresholds: thresholds,
      recent_txns: recent_txns,
      total_txn_count: total_txn_count,
      page: page,
      max_page: max_page,
      active_modal: nil,
      form_error: nil,
      animating_flows: []
    )
  end

  defp parse_dollars_to_cents(amount_str) when is_binary(amount_str) do
    case Float.parse(amount_str) do
      {amount, _} ->
        cents = trunc(amount * 100)

        if cents > 0 do
          {:ok, cents}
        else
          {:error, "Amount must be greater than 0"}
        end

      :error ->
        {:error, "Invalid amount"}
    end
  end

  defp parse_to_cents(value) when is_binary(value) do
    case Float.parse(value) do
      {amount, _} -> trunc(amount * 100)
      :error -> 0
    end
  end

  defp parse_to_cents(value) when is_nil(value), do: 0

  defp format_cents(cents) when is_integer(cents) do
    dollars = div(cents, 100)
    remainder = rem(cents, 100)
    "#{dollars}.#{String.pad_leading("#{remainder}", 2, "0")}"
  end

  defp format_cents(_), do: "0.00"

  defp format_type(:deposit), do: "Deposit"
  defp format_type(:withdrawal), do: "Withdrawal"
  defp format_type(:transfer), do: "Transfer"
  defp format_type(:salary_draw), do: "Salary"
  defp format_type(:tax_reserve), do: "Tax Reserve"
  defp format_type(:savings_overflow), do: "Cascade"
  defp format_type(type), do: to_string(type)

  defp type_badge_class(:deposit), do: "badge-success"
  defp type_badge_class(:withdrawal), do: "badge-error"
  defp type_badge_class(:salary_draw), do: "badge-info"
  defp type_badge_class(:transfer), do: "badge-primary"
  defp type_badge_class(:tax_reserve), do: "badge-warning"
  defp type_badge_class(:savings_overflow), do: "badge-warning"
  defp type_badge_class(_), do: "badge-ghost"

  defp format_error(reason) do
    case reason do
      :insufficient_funds -> "Insufficient funds"
      msg when is_binary(msg) -> msg
      _ -> "An error occurred"
    end
  end
end
