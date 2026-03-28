defmodule MobileCarWash.Billing.Pricing do
  @moduledoc """
  Vehicle-based pricing calculations.

  Base prices are for cars (sedans, coupes, compacts).
  Larger vehicles get a multiplier:
  - Car: 1.0x (base price)
  - SUV/Van: 1.2x
  - Pickup: 1.5x
  """

  @multipliers %{
    car: 1.0,
    suv_van: 1.2,
    pickup: 1.5
  }

  @doc """
  Calculate the price for a service + vehicle size combination.
  Returns price in cents (integer).
  """
  def calculate(base_price_cents, vehicle_size) do
    multiplier = Map.get(@multipliers, vehicle_size, 1.0)
    round(base_price_cents * multiplier)
  end

  @doc "Returns the multiplier for a vehicle size."
  def multiplier(vehicle_size), do: Map.get(@multipliers, vehicle_size, 1.0)

  @doc "Returns a human-readable label for the vehicle size."
  def size_label(:car), do: "Car"
  def size_label(:suv_van), do: "SUV / Van"
  def size_label(:pickup), do: "Pickup Truck"
  def size_label(_), do: "Vehicle"

  @doc "Returns all size options with labels and multipliers for display."
  def size_options do
    [
      %{value: :car, label: "Car (Sedan, Coupe, Compact)", multiplier: 1.0, extra: nil},
      %{value: :suv_van, label: "SUV / Van", multiplier: 1.2, extra: "+20%"},
      %{value: :pickup, label: "Pickup Truck", multiplier: 1.5, extra: "+50%"}
    ]
  end
end
