defmodule MobileCarWashWeb.BookingSignInTest do
  @moduledoc """
  Covers the single-page booking flow's account/guest recovery paths:

  - An anonymous customer is always offered a *working* sign-in route, so
    returning customers can reach their saved vehicles/addresses.
  - A guest provides contact info inline at Review & Pay; the customer is
    created at payment time.
  - A guest whose email already belongs to a registered account is offered a
    sign-in path (via an inline error) instead of a dead-end on pay.
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

  test "the page offers a working sign-in link, not a disabled stub", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/book")

    # A navigable link to the booking sign-in entry point.
    assert html =~ ~s(href="/book/sign-in")
    # And no dead "coming soon" stub.
    refute html =~ "coming soon"
  end

  test "a guest sees the inline contact form in Review & Pay", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/book")
    html = render_click(view, "select_service", %{"slug" => "basic_wash"})

    # The guest contact form lives in the review section for anonymous users.
    assert html =~ ~s(phx-change="guest_form_change")
    assert html =~ ~s(name="guest[email]")
  end

  test "guest_form_change keeps the typed contact info in the form", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/book")
    render_click(view, "select_service", %{"slug" => "basic_wash"})

    html =
      render_change(view, "guest_form_change", %{
        "guest" => %{
          "name" => "New Guest",
          "email" => "newguest@example.com",
          "phone" => "5125550100"
        }
      })

    assert html =~ "newguest@example.com"
  end

  test "paying with a registered email surfaces a sign-in recovery message", %{conn: conn} do
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
    render_click(view, "select_service", %{"slug" => "basic_wash"})

    render_change(view, "guest_form_change", %{
      "guest" => %{
        "name" => "Returning Customer",
        "email" => "returning@example.com",
        "phone" => "512-555-0100"
      }
    })

    # confirm_booking runs ensure_customer first; the registered-email collision
    # halts before any booking and surfaces a recovery message + sign-in link.
    html = render_click(view, "confirm_booking", %{})

    assert html =~ "already"
    assert html =~ ~s(href="/book/sign-in")
  end
end
