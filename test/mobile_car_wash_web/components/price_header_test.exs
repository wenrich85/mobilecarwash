defmodule MobileCarWashWeb.PriceHeaderTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest
  alias MobileCarWashWeb.PriceHeader

  defp render_price_header(assigns), do: render_component(&PriceHeader.price_header/1, assigns)

  test "prompts to pick a service when breakdown is nil" do
    html = render_price_header(%{breakdown: nil})
    assert html =~ "Select a service"
  end

  test "shows the total prominently" do
    bd = MobileCarWash.Billing.Pricing.breakdown(%{base_price_cents: 5000, vehicle_size: :suv_van})
    html = render_price_header(%{breakdown: bd})
    assert html =~ "$60.00"
    assert html =~ "data-cents=\"6000\""
  end

  test "expanded shows itemized receipt lines" do
    bd =
      MobileCarWash.Billing.Pricing.breakdown(%{
        base_price_cents: 5000,
        vehicle_size: :suv_van,
        addon_lines: [%{label: "Wax & shine", amount_cents: 1500}]
      })

    html = render_price_header(%{breakdown: bd, expanded: true})
    assert html =~ "Wax &amp; shine"
    assert html =~ "SUV / Van"
    assert html =~ "$75.00"
  end
end
