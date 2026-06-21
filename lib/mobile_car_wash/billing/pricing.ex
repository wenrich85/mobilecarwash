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

  @doc """
  Pure price breakdown for the live hero header and the persisted total.

  Input keys: `:base_price_cents` (required), `:vehicle_size` (atom | nil),
  `:addon_lines` (list of `%{label, amount_cents}`), `:discount_cents`.
  """
  def breakdown(input) when is_map(input) do
    base = Map.fetch!(input, :base_price_cents)
    size = Map.get(input, :vehicle_size)
    addon_lines = Map.get(input, :addon_lines, [])
    discount = Map.get(input, :discount_cents, 0)

    sized = if size, do: calculate(base, size), else: base
    size_delta = sized - base
    addons_total = Enum.sum(Enum.map(addon_lines, & &1.amount_cents))
    subtotal = sized + addons_total
    total = max(subtotal - discount, 0)

    %{
      base_cents: base,
      size_label: size && size_label(size),
      size_delta_cents: size_delta,
      addon_lines: addon_lines,
      addons_total_cents: addons_total,
      discount_cents: discount,
      subtotal_cents: subtotal,
      total_cents: total
    }
  end

  @doc "Sum of add-on prices in cents, scaled by the vehicle-size multiplier."
  def addons_total_cents(add_ons, vehicle_size \\ nil) do
    Enum.sum(Enum.map(add_ons, &calculate(&1.price_cents, vehicle_size)))
  end

  @doc "Maps add-ons to receipt line items, each scaled by the vehicle-size multiplier."
  def addon_lines(add_ons, vehicle_size \\ nil) do
    Enum.map(add_ons, &%{label: &1.name, amount_cents: calculate(&1.price_cents, vehicle_size)})
  end

  @doc "Formats integer cents as a dollar string, e.g. 6050 -> \"$60.50\"."
  def format_cents(cents) when is_integer(cents) do
    "$#{div(cents, 100)}.#{String.pad_leading(Integer.to_string(rem(cents, 100)), 2, "0")}"
  end

  @doc """
  Subscription discount (in cents) for a service under a plan. Mirrors the
  charge logic so the live price hero matches what is actually billed:
  a covered basic wash is free (full base price off), a deep clean gets the
  plan's percentage off the base. Returns 0 with no plan / no coverage.

  Note: the discount is computed off the *base* price, so a larger vehicle's
  size upcharge is still owed by a subscriber — matching the server.
  """
  def subscription_discount_cents(_base_price_cents, _service_slug, nil), do: 0

  def subscription_discount_cents(base_price_cents, service_slug, plan) do
    cond do
      service_slug == "basic_wash" and plan.basic_washes_per_month > 0 ->
        base_price_cents

      service_slug == "deep_clean" and plan.deep_clean_discount_percent > 0 ->
        div(base_price_cents * plan.deep_clean_discount_percent, 100)

      true ->
        0
    end
  end
end
