defmodule MobileCarWash.Billing.PricingTest do
  use ExUnit.Case, async: true

  alias MobileCarWash.Billing.Pricing

  describe "calculate/2" do
    test "car gets base price (1.0x)" do
      assert Pricing.calculate(5000, :car) == 5000
      assert Pricing.calculate(20000, :car) == 20000
    end

    test "suv_van gets 1.2x multiplier" do
      assert Pricing.calculate(5000, :suv_van) == 6000
      assert Pricing.calculate(20000, :suv_van) == 24000
    end

    test "pickup gets 1.5x multiplier" do
      assert Pricing.calculate(5000, :pickup) == 7500
      assert Pricing.calculate(20000, :pickup) == 30000
    end

    test "unknown size defaults to 1.0x" do
      assert Pricing.calculate(5000, :unknown) == 5000
    end
  end

  describe "multiplier/1" do
    test "returns correct multipliers" do
      assert Pricing.multiplier(:car) == 1.0
      assert Pricing.multiplier(:suv_van) == 1.2
      assert Pricing.multiplier(:pickup) == 1.5
    end
  end

  describe "size_label/1" do
    test "returns human labels" do
      assert Pricing.size_label(:car) == "Car"
      assert Pricing.size_label(:suv_van) == "SUV / Van"
      assert Pricing.size_label(:pickup) == "Pickup Truck"
    end
  end

  describe "size_options/0" do
    test "returns all three options" do
      opts = Pricing.size_options()
      assert length(opts) == 3
      assert Enum.map(opts, & &1.value) == [:car, :suv_van, :pickup]
    end
  end

  describe "breakdown/1" do
    test "service only (no vehicle yet) has no size delta" do
      b = Pricing.breakdown(%{base_price_cents: 5000})
      assert b.base_cents == 5000
      assert b.size_label == nil
      assert b.size_delta_cents == 0
      assert b.addons_total_cents == 0
      assert b.discount_cents == 0
      assert b.subtotal_cents == 5000
      assert b.total_cents == 5000
    end

    test "suv adds a 20% size delta on top of base" do
      b = Pricing.breakdown(%{base_price_cents: 5000, vehicle_size: :suv_van})
      assert b.size_label == "SUV / Van"
      assert b.size_delta_cents == 1000
      assert b.total_cents == 6000
    end

    test "add-on lines stack flat and total" do
      b =
        Pricing.breakdown(%{
          base_price_cents: 5000,
          vehicle_size: :suv_van,
          addon_lines: [
            %{label: "Wax & shine", amount_cents: 1500},
            %{label: "Pet hair removal", amount_cents: 1000}
          ]
        })

      assert b.addons_total_cents == 2500
      assert b.subtotal_cents == 8500
      assert b.total_cents == 8500
    end

    test "discount subtracts and floors at zero" do
      b = Pricing.breakdown(%{base_price_cents: 5000, discount_cents: 9000})
      assert b.subtotal_cents == 5000
      assert b.total_cents == 0
    end
  end

  describe "format_cents/1" do
    test "format_cents renders dollars" do
      assert Pricing.format_cents(6000) == "$60.00"
      assert Pricing.format_cents(7550) == "$75.50"
      assert Pricing.format_cents(0) == "$0.00"
    end

    test "format_cents handles awkward cent values" do
      assert Pricing.format_cents(999) == "$9.99"
      assert Pricing.format_cents(101) == "$1.01"
      assert Pricing.format_cents(5) == "$0.05"
    end
  end

  describe "subscription_discount_cents/3" do
    test "covered basic wash discounts the full base price" do
      plan = %{basic_washes_per_month: 4, deep_clean_discount_percent: 0}
      assert Pricing.subscription_discount_cents(5000, "basic_wash", plan) == 5000
    end

    test "deep clean discounts by the plan percentage of base" do
      plan = %{basic_washes_per_month: 0, deep_clean_discount_percent: 50}
      assert Pricing.subscription_discount_cents(20000, "deep_clean", plan) == 10000
    end

    test "no discount when the plan does not cover the service" do
      plan = %{basic_washes_per_month: 0, deep_clean_discount_percent: 0}
      assert Pricing.subscription_discount_cents(5000, "basic_wash", plan) == 0
      assert Pricing.subscription_discount_cents(20000, "deep_clean", plan) == 0
    end

    test "no discount when there is no plan" do
      assert Pricing.subscription_discount_cents(5000, "basic_wash", nil) == 0
    end
  end
end
