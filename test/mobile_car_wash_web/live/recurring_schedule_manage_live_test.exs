defmodule MobileCarWashWeb.RecurringScheduleManageLiveTest do
  use MobileCarWashWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MobileCarWash.Scheduling.RecurringSchedule

  require Ash.Query

  setup %{conn: conn} do
    {:ok, customer} =
      MobileCarWash.Accounts.Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "recur-ui-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Recurring UI Test",
        phone: "+15125550000"
      })
      |> Ash.create()

    {:ok, service_type} =
      MobileCarWash.Scheduling.ServiceType
      |> Ash.Changeset.for_create(:create, %{
        name: "Basic Wash",
        slug: "recur_ui_#{System.unique_integer([:positive])}",
        base_price_cents: 5_000,
        duration_minutes: 45
      })
      |> Ash.create()

    {:ok, vehicle} =
      MobileCarWash.Fleet.Vehicle
      |> Ash.Changeset.for_create(:create, %{make: "Toyota", model: "Camry", year: 2021})
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create()

    {:ok, address} =
      MobileCarWash.Fleet.Address
      |> Ash.Changeset.for_create(:create, %{street: "100 Main St", city: "San Antonio", state: "TX", zip: "78259"})
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create()

    # Sign in through the auth controller to set up proper session + token
    conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> post("/auth/customer/password/sign_in", %{
        "customer" => %{
          "email" => to_string(customer.email),
          "password" => "Password123!"
        }
      })

    # Follow the redirect and use that conn's cookies for LiveView
    conn = recycle(conn)

    %{conn: conn, customer: customer, service_type: service_type, vehicle: vehicle, address: address}
  end

  test "unauthenticated user is redirected to sign-in" do
    conn = build_conn()
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/account/recurring")
  end

  test "renders the recurring schedules page", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/account/recurring")
    assert html =~ "Recurring Schedules"
  end

  test "shows empty state when no schedules exist", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/account/recurring")
    assert html =~ "No recurring schedules"
  end

  test "can create a new recurring schedule", %{conn: conn, vehicle: vehicle, address: address, service_type: service_type} do
    {:ok, view, _html} = live(conn, ~p"/account/recurring")

    view |> element("button", "Add Schedule") |> render_click()

    html =
      view
      |> form("#schedule-form", %{
        "schedule" => %{
          "frequency" => "weekly",
          "preferred_day" => "3",
          "preferred_time" => "10:00",
          "vehicle_id" => vehicle.id,
          "address_id" => address.id,
          "service_type_id" => service_type.id
        }
      })
      |> render_submit()

    assert html =~ "Schedule created"
  end

  test "can deactivate a schedule", %{conn: conn, customer: customer, vehicle: vehicle, address: address, service_type: service_type} do
    {:ok, _schedule} =
      RecurringSchedule
      |> Ash.Changeset.for_create(:create, %{
        frequency: :weekly,
        preferred_day: 3,
        preferred_time: ~T[10:00:00]
      })
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.Changeset.force_change_attribute(:vehicle_id, vehicle.id)
      |> Ash.Changeset.force_change_attribute(:address_id, address.id)
      |> Ash.Changeset.force_change_attribute(:service_type_id, service_type.id)
      |> Ash.create()

    {:ok, view, _html} = live(conn, ~p"/account/recurring")

    html = view |> element("button", "Pause") |> render_click()

    assert html =~ "Schedule paused"
  end
end
