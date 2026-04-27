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

  describe "block_window_picker/1" do
    test "renders 7 date chips when available_dates not provided" do
      assigns = %{date: Date.utc_today(), blocks: [], selected_block: nil}
      html = rendered_to_string(~H|<.block_window_picker date={@date} blocks={@blocks} selected_block={@selected_block} />|)
      today = Date.utc_today()
      assert html =~ "#{today.day}"
      future = Date.add(today, 6)
      assert html =~ "#{future.day}"
    end

    test "highlights selected date chip with cyan" do
      today = Date.utc_today()
      assigns = %{date: today, blocks: [], selected_block: nil}
      html = rendered_to_string(~H|<.block_window_picker date={@date} blocks={@blocks} selected_block={@selected_block} />|)
      assert html =~ "bg-cyan-500"
    end

    test "renders blocks list when provided" do
      block = %{id: "block-1", starts_at: ~U[2026-04-30 09:00:00Z], ends_at: ~U[2026-04-30 11:00:00Z], capacity: 3, appointment_count: 1}
      assigns = %{date: ~D[2026-04-30], blocks: [block], selected_block: nil}
      html = rendered_to_string(~H|<.block_window_picker date={@date} blocks={@blocks} selected_block={@selected_block} />|)
      assert html =~ "9:00"
      assert html =~ "11:00"
      assert html =~ "2 of 3 spots left"
    end

    test "selected block has cyan-500 background" do
      block = %{id: "block-1", starts_at: ~U[2026-04-30 09:00:00Z], ends_at: ~U[2026-04-30 11:00:00Z], capacity: 3, appointment_count: 1}
      assigns = %{date: ~D[2026-04-30], blocks: [block], selected_block: block}
      html = rendered_to_string(~H|<.block_window_picker date={@date} blocks={@blocks} selected_block={@selected_block} />|)
      assert html =~ "bg-cyan-500"
    end

    test "shows warning when blocks empty for selected date" do
      assigns = %{date: ~D[2026-04-30], blocks: [], selected_block: nil}
      html = rendered_to_string(~H|<.block_window_picker date={@date} blocks={@blocks} selected_block={@selected_block} />|)
      assert html =~ "No available windows"
    end
  end
end
