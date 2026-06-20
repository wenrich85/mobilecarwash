defmodule MobileCarWashWeb.BookingSinglePageTest do
  use MobileCarWashWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias MobileCarWash.Scheduling.ServiceType

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

    :ok
  end

  # Extracts the markup of a single <section id="..."> up to the next <section
  # (or end), so per-section assertions don't bleed into neighbouring sections.
  defp section_html(html, id) do
    case Regex.run(~r/<section id="#{id}".*?(?=<section |<\/main>|$)/s, html) do
      [chunk] -> chunk
      _ -> ""
    end
  end

  test "all six sections render on one page; later ones start locked", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/book")

    for t <- [
          "Service",
          "Add-ons",
          "Your vehicle",
          "Service location",
          "Pick a time",
          "Review &amp; Pay"
        ] do
      assert html =~ t
    end

    # Vehicle section is locked (disabled fieldset) before a service is chosen
    assert section_html(html, "section-vehicle") =~ "<fieldset disabled"
  end

  test "choosing a service unlocks the vehicle section and updates the hero", %{conn: conn} do
    {:ok, view, _} = live(conn, "/book")
    html = render_click(view, "select_service", %{"slug" => "basic_wash"})
    assert html =~ "$50.00"
    # vehicle section no longer disabled
    refute section_html(html, "section-vehicle") =~ "<fieldset disabled"
  end

  test "Pay is disabled until all required sections + contact are present", %{conn: conn} do
    {:ok, view, _} = live(conn, "/book")
    html = render_click(view, "select_service", %{"slug" => "basic_wash"})
    assert html =~ ~r/phx-click="confirm_booking"[^>]*disabled/
  end

  test "the page no longer renders the step wizard controls", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/book")
    refute html =~ ~s(phx-click="next_step")
    refute html =~ ~s(phx-click="prev_step")
  end
end
