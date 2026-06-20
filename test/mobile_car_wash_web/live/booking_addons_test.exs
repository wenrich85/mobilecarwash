defmodule MobileCarWashWeb.BookingAddonsTest do
  use MobileCarWashWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias MobileCarWash.Scheduling.{ServiceType, AddOn}

  setup do
    ServiceType
    |> Ash.Changeset.for_create(:create, %{
      name: "Basic Wash",
      slug: "basic_wash",
      description: "x",
      base_price_cents: 5_000,
      duration_minutes: 45
    })
    |> Ash.create!()

    AddOn
    |> Ash.Changeset.for_create(:create, %{
      name: "Wax & Shine",
      slug: "wax_shine",
      price_cents: 1_500,
      icon: "sparkles"
    })
    |> Ash.create!()

    :ok
  end

  test "add-ons step lists add-ons and toggling one raises the hero total", %{conn: conn} do
    {:ok, view, _} = live(conn, "/book")
    render_click(view, "select_service", %{"slug" => "basic_wash"})

    html = render_click(view, "next_step", %{})
    assert html =~ "Wax &amp; Shine"
    # base only so far
    assert html =~ "$50.00"

    addon = MobileCarWash.Scheduling.AddOn |> Ash.read!() |> hd()
    html = render_click(view, "toggle_add_on", %{"id" => addon.id})

    # base + wax
    assert html =~ "$65.00"
  end

  test "add-ons step renders exactly one Back button (global back, no inline duplicate)", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, "/book")
    render_click(view, "select_service", %{"slug" => "basic_wash"})
    html = render_click(view, "next_step", %{})

    # Count occurrences of phx-click="prev_step" — must be exactly one (the global back)
    back_count = html |> String.split(~s(phx-click="prev_step")) |> length() |> Kernel.-(1)
    assert back_count == 1, "Expected exactly 1 Back button on :add_ons step, got #{back_count}"
  end

  test "toggling an unknown add-on id is a no-op", %{conn: conn} do
    {:ok, view, _} = live(conn, "/book")
    render_click(view, "select_service", %{"slug" => "basic_wash"})
    html_before = render_click(view, "next_step", %{})

    html_after =
      render_click(view, "toggle_add_on", %{"id" => "00000000-0000-0000-0000-000000000000"})

    # Price unchanged — no nil add-on appended
    assert html_after =~ "$50.00"
    # Rendered output is stable
    assert html_before =~ "$50.00"
  end
end
