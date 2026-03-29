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
end
