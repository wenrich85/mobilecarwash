defmodule MobileCarWashWeb.BookingPriceHeaderTest do
  use MobileCarWashWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias MobileCarWash.Scheduling.ServiceType

  setup do
    ServiceType
    |> Ash.Changeset.for_create(:create, %{
      name: "Basic Wash", slug: "basic_wash", description: "x",
      base_price_cents: 5_000, duration_minutes: 45
    })
    |> Ash.create!()
    :ok
  end

  test "hero shows base price once a service is selected", %{conn: conn} do
    {:ok, view, html} = live(conn, "/book")
    # Before selecting: prompt to pick a service.
    assert html =~ "Select a service to see your price"

    html = render_click(view, "select_service", %{"slug" => "basic_wash"})
    assert html =~ "$50.00"
  end

  test "tapping the hero toggles the itemized receipt", %{conn: conn} do
    {:ok, view, _} = live(conn, "/book")
    render_click(view, "select_service", %{"slug" => "basic_wash"})

    html = render_click(view, "toggle_receipt", %{})
    assert html =~ "Total"
    assert html =~ "Base"
  end
end
