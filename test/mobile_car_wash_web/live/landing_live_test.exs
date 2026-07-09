defmodule MobileCarWashWeb.LandingLiveTest do
  use MobileCarWashWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  require Ash.Query

  defp create_service(attrs) do
    defaults = %{
      name: "Test Service #{System.unique_integer([:positive])}",
      slug: "test_service_#{System.unique_integer([:positive])}",
      description: "A service for landing page tests.",
      base_price_cents: 5000,
      duration_minutes: 45,
      active: true,
      show_on_landing: true
    }

    MobileCarWash.Scheduling.ServiceType
    |> Ash.Changeset.for_create(:create, Map.merge(defaults, attrs))
    |> Ash.create!()
  end

  describe "landing page" do
    test "renders hero with headline and trust badge", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/")

      assert html =~ "Your car, washed where you parked it."
      assert html =~ "SAN ANTONIO"
      assert html =~ "Book my first wash"
    end

    test "renders How It Works section with 3 steps", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/")

      assert html =~ "HOW IT WORKS"
      assert html =~ "Three steps. No hose hookup."
      assert html =~ "Book online"
      assert html =~ "We come to you"
      assert html =~ "Pay when done"
    end

    test "renders every active service marked for landing display", %{conn: conn} do
      create_service(%{
        name: "Basic Wash",
        slug: "basic_wash_#{System.unique_integer([:positive])}",
        base_price_cents: 5000,
        duration_minutes: 45,
        show_on_landing: true
      })

      create_service(%{
        name: "Deep Clean & Detail",
        slug: "deep_clean_#{System.unique_integer([:positive])}",
        base_price_cents: 20_000,
        duration_minutes: 120,
        show_on_landing: true
      })

      {:ok, _lv, html} = live(conn, ~p"/")

      assert html =~ "SERVICES"
      assert html =~ "Basic Wash"
      assert html =~ "$50"
      assert html =~ "Deep Clean &amp; Detail"
      assert html =~ "$200"
      refute html =~ "Two tiers"
    end

    test "does not render active services hidden from landing display", %{conn: conn} do
      create_service(%{
        name: "Private Fleet Wash",
        slug: "private_fleet_wash_#{System.unique_integer([:positive])}",
        base_price_cents: 7500,
        duration_minutes: 60,
        active: true,
        show_on_landing: false
      })

      {:ok, _lv, html} = live(conn, ~p"/")

      refute html =~ "Private Fleet Wash"
      refute html =~ "$75"
    end

    test "renders tech section with SMS preview content", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/")

      assert html =~ "We tell you exactly when"
      assert html =~ "15 minutes"
      assert html =~ "Jordan is 8 minutes away"
    end

    test "renders 3 testimonials", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/")

      assert html =~ "What customers say"
      assert html =~ "Maria G."
      assert html =~ "Marcus T."
      assert html =~ "Brittany R."
    end

    test "renders final CTA band and footer", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/")

      assert html =~ "Ready for a clean car without the trip?"
      assert html =~ "© 2026 Driveway Detail Co. LLC"
      assert html =~ "Veteran-owned"
    end

    test "links to booking page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/")

      assert html =~ "/book"
    end
  end
end
