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

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 py-8">
      <h1 class="text-2xl font-bold">Projections</h1>
      <p class="text-base-content/70">Coming soon — implementation in Task 2.</p>
      <.link navigate={~p"/admin/cash-flow"} class="btn btn-ghost btn-sm mt-4">
        ← Back to Dashboard
      </.link>
    </div>
    """
  end

  # === Private helpers ===

  # Mirrors the helper of the same name in cash_flow_live.ex. Keep these in
  # sync until Task 2 moves the projections logic over fully.
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
end
