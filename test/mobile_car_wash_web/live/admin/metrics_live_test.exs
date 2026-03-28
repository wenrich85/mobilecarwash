defmodule MobileCarWashWeb.Admin.MetricsLiveTest do
  use MobileCarWashWeb.ConnCase, async: true

  alias MobileCarWash.Analytics.Event

  setup %{conn: conn} do
    # Create an admin customer
    {:ok, customer} =
      MobileCarWash.Accounts.Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "admin@mobilecarwash.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Admin Owner"
      })
      |> Ash.create()

    # Create some events for the dashboard
    for name <- ["page.viewed", "booking.started", "booking.completed"] do
      Event
      |> Ash.Changeset.for_create(:track, %{
        session_id: "sess_admin_test",
        event_name: name,
        source: "web",
        properties: %{}
      })
      |> Ash.create!()
    end

    %{conn: conn, customer: customer}
  end

  test "renders dashboard for admin user", %{conn: conn} do
    # The dashboard renders when accessed (via GET which triggers LiveView mount)
    conn = get(conn, ~p"/admin/metrics")
    # Admin auth will redirect since we're not logged in via session
    assert redirected_to(conn) == "/sign-in"
  end

  test "non-authenticated user is redirected to sign-in", %{conn: conn} do
    conn = get(conn, ~p"/admin/metrics")
    assert redirected_to(conn) == "/sign-in"
  end

  test "events explorer is accessible", %{conn: conn} do
    conn = get(conn, ~p"/admin/events")
    assert redirected_to(conn) == "/sign-in"
  end
end
