defmodule MobileCarWashWeb.LandingLiveTest do
  use MobileCarWashWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  require Ash.Query

  # Seed the two service types that the landing page pricing section
  # displays conditionally via :if={@basic} / :if={@premium}.
  defp seed_services do
    basic =
      MobileCarWash.Scheduling.ServiceType
      |> Ash.Query.filter(slug == "basic_wash")
      |> Ash.read!()
      |> case do
        [st | _] ->
          st

        [] ->
          MobileCarWash.Scheduling.ServiceType
          |> Ash.Changeset.for_create(:create, %{
            name: "Basic Wash",
            slug: "basic_wash",
            base_price_cents: 5000,
            duration_minutes: 45
          })
          |> Ash.create!()
      end

    premium =
      MobileCarWash.Scheduling.ServiceType
      |> Ash.Query.filter(slug == "deep_clean_detail")
      |> Ash.read!()
      |> case do
        [st | _] ->
          st

        [] ->
          MobileCarWash.Scheduling.ServiceType
          |> Ash.Changeset.for_create(:create, %{
            name: "Premium",
            slug: "deep_clean_detail",
            base_price_cents: 19_999,
            duration_minutes: 180
          })
          |> Ash.create!()
      end

    {basic, premium}
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

    test "renders pricing section with both tier names and prices", %{conn: conn} do
      seed_services()
      {:ok, _lv, html} = live(conn, ~p"/")

      assert html =~ "PRICING"
      assert html =~ "Two tiers. No hidden fees."
      assert html =~ "Basic Wash"
      assert html =~ "$50"
      assert html =~ "Premium"
      assert html =~ "$199.99"
      assert html =~ "MOST POPULAR"
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
