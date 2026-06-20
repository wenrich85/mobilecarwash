defmodule MobileCarWashWeb.BookingSignInTest do
  @moduledoc """
  Covers the booking wizard's :auth step recovery paths:

  - An anonymous customer must be offered a *working* sign-in route
    (previously a disabled "coming soon" stub), so returning customers
    can reach their saved vehicles/addresses without abandoning the flow.
  - A guest who enters an email that already belongs to a registered
    account is offered a sign-in path instead of a dead-end error.
  """
  use MobileCarWashWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Scheduling.ServiceType

  setup do
    service =
      ServiceType
      |> Ash.Changeset.for_create(:create, %{
        name: "Basic Wash",
        slug: "basic_wash",
        description: "Exterior hand wash",
        base_price_cents: 5_000,
        duration_minutes: 45
      })
      |> Ash.create!()

    %{service: service}
  end

  defp advance_to_auth(view) do
    render_click(view, "select_service", %{"slug" => "basic_wash"})
    render_click(view, "next_step", %{})
  end

  test "successful guest checkout advances to the vehicle step without crashing",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, "/book")
    advance_to_auth(view)

    html =
      view
      |> form("form[phx-submit=guest_checkout]",
        guest: %{name: "New Guest", email: "newguest@example.com", phone: "512-555-0100"}
      )
      |> render_submit()

    # We should land on the vehicle step, not crash or stay stuck on the
    # guest form. (The vehicle-step inputs previously crashed on render.)
    assert html =~ "Make"
    refute html =~ "Continue as guest"
  end

  test "auth step offers a working sign-in link, not a disabled stub", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/book")
    html = advance_to_auth(view)

    # The real fix: a navigable link to the booking sign-in entry point.
    assert html =~ ~s(href="/book/sign-in")
    # And the dead "coming soon" stub is gone.
    refute html =~ "coming soon"
  end

  test "guest checkout with a registered email offers sign-in instead of a dead-end",
       %{conn: conn} do
    {:ok, _registered} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "returning@example.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Returning Customer",
        phone: "512-555-0100"
      })
      |> Ash.create()

    {:ok, view, _html} = live(conn, "/book")
    advance_to_auth(view)

    html =
      view
      |> form("form[phx-submit=guest_checkout]",
        guest: %{
          name: "Returning Customer",
          email: "returning@example.com",
          phone: "512-555-0100"
        }
      )
      |> render_submit()

    # Recovery, not a wall: the collision message links to sign-in.
    assert html =~ "already"
    assert html =~ ~s(href="/book/sign-in")
  end
end
