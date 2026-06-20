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

  test "add-ons section lists add-ons and toggling one raises the hero total", %{conn: conn} do
    {:ok, view, _} = live(conn, "/book")

    html = render_click(view, "select_service", %{"slug" => "basic_wash"})
    assert html =~ "Wax &amp; Shine"
    # base only so far
    assert html =~ "$50.00"

    addon = MobileCarWash.Scheduling.AddOn |> Ash.read!() |> hd()
    html = render_click(view, "toggle_add_on", %{"id" => addon.id})

    # base + wax
    assert html =~ "$65.00"
  end

  test "toggling an unknown add-on id is a no-op", %{conn: conn} do
    {:ok, view, _} = live(conn, "/book")
    html_before = render_click(view, "select_service", %{"slug" => "basic_wash"})

    html_after =
      render_click(view, "toggle_add_on", %{"id" => "00000000-0000-0000-0000-000000000000"})

    # Price unchanged — no nil add-on appended
    assert html_after =~ "$50.00"
    # Rendered output is stable
    assert html_before =~ "$50.00"
  end
end
