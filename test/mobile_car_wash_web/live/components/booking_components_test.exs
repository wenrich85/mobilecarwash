defmodule MobileCarWashWeb.BookingComponentsTest do
  use ExUnit.Case, async: true
  import Phoenix.Component
  import Phoenix.LiveViewTest
  import MobileCarWashWeb.BookingComponents

  describe "step_indicator/1" do
    test "renders progress bar with current step number, label, and percent" do
      assigns = %{}
      html = rendered_to_string(~H|<.step_indicator current_step={:vehicle} />|)
      assert html =~ "Step 3 of 8"
      assert html =~ "Vehicle"
      assert html =~ "38%"
      assert html =~ "width: 38%"
    end

    test "shows next step hint when not on last step" do
      assigns = %{}
      html = rendered_to_string(~H|<.step_indicator current_step={:vehicle} />|)
      assert html =~ "Next: Address"
    end

    test "omits next step hint on last step" do
      assigns = %{}
      html = rendered_to_string(~H|<.step_indicator current_step={:confirmed} />|)
      refute html =~ "Next:"
    end
  end

  describe "service_card/1" do
    setup do
      service = %{
        slug: "basic_wash",
        name: "Basic Wash",
        description: "Exterior hand wash and quick interior",
        base_price_cents: 5000,
        duration_minutes: 45
      }
      %{service: service}
    end

    test "renders selected state with cyan border and check badge", %{service: service} do
      assigns = %{service: service}
      html = rendered_to_string(~H|<.service_card service={@service} selected={true} />|)
      assert html =~ "border-cyan-500"
      assert html =~ "✓" or html =~ "hero-check"
    end

    test "unselected state has no check badge", %{service: service} do
      assigns = %{service: service}
      html = rendered_to_string(~H|<.service_card service={@service} selected={false} />|)
      refute html =~ "border-cyan-500"
    end

    test "click emits select_service event with slug", %{service: service} do
      assigns = %{service: service}
      html = rendered_to_string(~H|<.service_card service={@service} />|)
      assert html =~ ~s(phx-click="select_service")
      assert html =~ ~s(phx-value-slug="basic_wash")
    end

    test "renders price in mono font with dollar amount", %{service: service} do
      assigns = %{service: service}
      html = rendered_to_string(~H|<.service_card service={@service} />|)
      assert html =~ "$50"
      assert html =~ "font-mono"
    end
  end
end
