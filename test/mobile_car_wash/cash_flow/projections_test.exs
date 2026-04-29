defmodule MobileCarWash.CashFlow.ProjectionsTest do
  @moduledoc """
  Regression tests for Projections.compute/1. Locks in current math
  shape (not specific values) so refactors don't accidentally change
  the contract.

  `compute/1` is a pure function (no DB), so this uses plain ExUnit.Case.
  """
  use ExUnit.Case, async: true

  alias MobileCarWash.CashFlow.Projections

  describe "compute/1" do
    test "returns a result with the documented shape" do
      inputs = %{
        plans: [
          %{id: "plan-basic", name: "Basic", price_cents: 4_999, subscriber_count: 10}
        ],
        services: [
          %{id: "svc-wash", name: "Standard Wash", avg_monthly_count: 20.0, price_cents: 5_000}
        ],
        monthly_fixed_costs: 5_000_00,
        avg_variable_costs: 1_000_00,
        months: 6,
        growth_rate: 0.0
      }

      result = Projections.compute(inputs)

      assert is_map(result)

      for key <- [
            :plans,
            :mrr,
            :services,
            :avg_one_time_income,
            :avg_wash_price,
            :monthly_fixed_costs,
            :avg_variable_costs,
            :months,
            :growth_rate,
            :monthly,
            :break_even
          ] do
        assert Map.has_key?(result, key), "expected compute/1 result to have key #{inspect(key)}"
      end

      # `monthly` should be a list with one row per projected month.
      assert is_list(result.monthly)
      assert length(result.monthly) == 6

      # Each monthly row carries the per-month projection contract.
      first_row = hd(result.monthly)

      for row_key <- [
            :month_label,
            :month_start,
            :projected_income,
            :mrr_component,
            :one_time_component,
            :projected_expenses,
            :fixed_costs,
            :variable_costs,
            :net_profit,
            :margin_pct,
            :cumulative_profit
          ] do
        assert Map.has_key?(first_row, row_key),
               "expected monthly row to have key #{inspect(row_key)}"
      end

      # Break-even sub-map shape.
      assert is_map(result.break_even)

      for be_key <- [
            :total_monthly_costs,
            :wash_revenue_needed,
            :washes_needed_per_month,
            :avg_wash_price,
            :mrr_coverage_pct,
            :revenue_needed
          ] do
        assert Map.has_key?(result.break_even, be_key),
               "expected break_even to have key #{inspect(be_key)}"
      end
    end

    test "doubling growth_rate changes the result" do
      base_inputs = %{
        plans: [
          %{id: "plan-basic", name: "Basic", price_cents: 4_999, subscriber_count: 10}
        ],
        services: [
          # Non-zero one-time revenue is required for growth_rate to bite,
          # since growth compounds against avg_one_time (services × count).
          %{id: "svc-wash", name: "Standard Wash", avg_monthly_count: 20.0, price_cents: 5_000}
        ],
        monthly_fixed_costs: 5_000_00,
        avg_variable_costs: 1_000_00,
        months: 6,
        growth_rate: 0.0
      }

      grown_inputs = %{base_inputs | growth_rate: 0.10}

      base_result = Projections.compute(base_inputs)
      grown_result = Projections.compute(grown_inputs)

      refute base_result == grown_result

      # Tighten the assertion: the later months should have higher projected
      # one-time income with growth applied. This guards against compute/1
      # silently swallowing growth_rate.
      base_last = List.last(base_result.monthly)
      grown_last = List.last(grown_result.monthly)
      assert grown_last.one_time_component > base_last.one_time_component
    end
  end
end
