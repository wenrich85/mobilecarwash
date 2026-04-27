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
end
