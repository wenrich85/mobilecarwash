defmodule MobileCarWashWeb.AccessibilityTest do
  @moduledoc """
  Verifies accessibility fixes from PageSpeed/Lighthouse findings:
  - Theme-toggle buttons have accessible names (aria-label)
  - Drawer-toggle checkbox has an associated label
  - Duplicate "Book a Wash" link text is differentiated for screen readers
  """
  use MobileCarWashWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  describe "landing layout a11y" do
    setup %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")
      %{html: html}
    end

    test "theme-toggle buttons each expose an aria-label", %{html: html} do
      assert html =~ ~s(aria-label="Use system theme")
      assert html =~ ~s(aria-label="Use light theme")
      assert html =~ ~s(aria-label="Use dark theme")
    end

    test "drawer-toggle checkbox has an associated sr-only label", %{html: html} do
      assert html =~ ~s(for="mobile-drawer")
      assert html =~ "Toggle navigation menu"
    end

    test "hero CTA does not collide with nav 'Book a Wash' link text", %{html: html} do
      # Nav + drawer both link to /book with text "Book a Wash"
      assert html =~ ~s(href="/book")

      # Hero button goes to #services — its visible text should differ from
      # the /book links so screen-reader users get distinct link names.
      hero_ctas =
        Regex.scan(~r/<a[^>]+href="#services"[^>]*>([^<]+)</s, html)
        |> Enum.map(fn [_, text] -> String.trim(text) end)

      refute "Book a Wash" in hero_ctas,
             ~s(hero CTA still reads "Book a Wash"; rename or add an aria-label)
    end
  end
end
