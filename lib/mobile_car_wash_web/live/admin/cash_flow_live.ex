defmodule MobileCarWashWeb.Admin.CashFlowLive do
  @moduledoc """
  Admin page for cash flow management.
  Displays the 5-account system with animated SVG bucket diagram and real-time balance updates.
  """
  use MobileCarWashWeb, :live_view

  import MobileCarWashWeb.Admin.CashFlowComponents

  alias MobileCarWash.CashFlow
  alias MobileCarWash.CashFlow.Engine

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
      |> reload_data()

    {:ok, socket}
  end

  @impl true
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
    {:noreply, reload_data(socket)}
  end

  def handle_info(:clear_animations, socket) do
    {:noreply, assign(socket, animating_flows: [])}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto py-8 px-4">
      <!-- Header -->
      <div class="mb-8 bg-gradient-to-r from-primary-700 to-primary-900 text-secondary-50 rounded-2xl p-8 shadow-lg">
        <h1 class="text-4xl font-bold mb-2">💰 Cash Flow Management</h1>
        <p class="text-secondary-100 text-base">
          Donald Miller's 5-bucket system: Expense → Tax, Business Savings, Investment, Personal Salary
        </p>
      </div>

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
                  <td class="text-xs text-base-content/60">
                    {Calendar.strftime(txn.inserted_at, "%m/%d %H:%M")}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <p :if={@recent_txns == []} class="text-center text-base-content/50 py-8 text-lg">
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
    </div>
    """
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

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
