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
  use MobileCarWashWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Scheduling.{ServiceType, AppointmentBlock}
  alias MobileCarWash.Operations.Technician

  require Ash.Query

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

  defp create_open_block(service) do
    tech =
      Technician
      |> Ash.Changeset.for_create(:create, %{
        name: "Test Tech #{System.unique_integer([:positive])}"
      })
      |> Ash.create!()

    starts_at =
      DateTime.utc_now()
      |> DateTime.add(2 * 86_400, :second)
      |> DateTime.truncate(:second)

    ends_at = DateTime.add(starts_at, 3 * 3600, :second)
    closes_at = DateTime.add(starts_at, -3600, :second)

    AppointmentBlock
    |> Ash.Changeset.for_create(:create, %{
      service_type_id: service.id,
      technician_id: tech.id,
      starts_at: starts_at,
      ends_at: ends_at,
      closes_at: closes_at,
      capacity: 5,
      status: :open
    })
    |> Ash.create!()
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

  test "paying with a registered email surfaces a sign-in recovery message",
       %{conn: conn, service: service} do
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

    block = create_open_block(service)

    {:ok, view, _html} = live(conn, "/book")

    # Complete all required sections so the payable? guard passes
    render_click(view, "select_service", %{"slug" => "basic_wash"})

    render_submit(view, "save_vehicle", %{
      "vehicle" => %{
        "make" => "Toyota",
        "model" => "Camry",
        "year" => "2022",
        "color" => "Silver",
        "size" => "car",
        "vin" => "",
        "body_class" => ""
      }
    })

    render_submit(view, "save_address", %{
      "address" => %{
        "street" => "123 Main St",
        "city" => "San Antonio",
        "state" => "TX",
        "zip" => "78261"
      }
    })

    block_date = block.starts_at |> DateTime.to_date() |> Date.to_string()
    render_click(view, "select_date", %{"date" => block_date})
    render_click(view, "select_block", %{"id" => block.id})

    render_change(view, "guest_form_change", %{
      "guest" => %{
        "name" => "Returning Customer",
        "email" => "returning@example.com",
        "phone" => "512-555-0100"
      }
    })

    # confirm_booking runs payable? guard (passes), then ensure_customer;
    # the registered-email collision halts before any booking and surfaces
    # a recovery message + sign-in link.
    html = render_click(view, "confirm_booking", %{})

    assert html =~ "already"
    assert html =~ ~s(href="/book/sign-in")
  end
end
