defmodule MobileCarWashWeb.Admin.BlocksLiveCalendarTest do
  use MobileCarWashWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  require Ash.Query

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Scheduling.{AppointmentBlock, Appointment, ServiceType}
  alias MobileCarWash.Operations.Technician
  alias MobileCarWash.Fleet.{Vehicle, Address}

  defp create_admin do
    {:ok, admin} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "admin-blocks-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Blocks Admin",
        phone: "+15125550301"
      })
      |> Ash.create()

    admin
    |> Ash.Changeset.for_update(:update, %{role: :admin})
    |> Ash.update!(authorize?: false)
  end

  defp sign_in(conn, user) do
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> post("/auth/customer/password/sign_in", %{
      "customer" => %{"email" => to_string(user.email), "password" => "Password123!"}
    })
    |> recycle()
  end

  defp service do
    ServiceType
    |> Ash.Changeset.for_create(:create, %{
      name: "Basic Wash",
      slug: "basic_#{System.unique_integer([:positive])}",
      base_price_cents: 5000,
      duration_minutes: 45
    })
    |> Ash.create!(authorize?: false)
  end

  defp tech do
    Technician
    |> Ash.Changeset.for_create(:create, %{name: "Cal Tech #{System.unique_integer([:positive])}"})
    |> Ash.create!(authorize?: false)
  end

  defp this_week_slot do
    today = Date.utc_today()
    monday = Date.add(today, -(Date.day_of_week(today) - 1))
    thursday = Date.add(monday, 3)
    DateTime.new!(thursday, ~T[09:00:00], "Etc/UTC") |> DateTime.truncate(:second)
  end

  defp empty_block(svc, t) do
    starts_at = this_week_slot()

    AppointmentBlock
    |> Ash.Changeset.for_create(:create, %{
      service_type_id: svc.id,
      technician_id: t.id,
      starts_at: starts_at,
      ends_at: DateTime.add(starts_at, 3 * 3600, :second),
      closes_at: DateTime.add(starts_at, -3600, :second),
      capacity: 3,
      status: :open
    })
    |> Ash.create!(authorize?: false)
  end

  test "renders the week calendar", %{conn: conn} do
    conn = sign_in(conn, create_admin())
    {:ok, view, _html} = live(conn, ~p"/admin/blocks")
    assert has_element?(view, "#blocks-calendar")
  end

  test "deletes an empty block", %{conn: conn} do
    svc = service()
    t = tech()
    b = empty_block(svc, t)

    conn = sign_in(conn, create_admin())
    {:ok, view, _html} = live(conn, ~p"/admin/blocks")

    # Navigate to the week that contains the block, then delete it.
    assert has_element?(view, "#block-#{b.id}")
    view |> element("#block-#{b.id} button[phx-click='delete_block']") |> render_click()

    refute has_element?(view, "#block-#{b.id}")
    assert {:error, _} = Ash.get(AppointmentBlock, b.id)
  end

  test "a booked block shows a locked marker and cannot be deleted", %{conn: conn} do
    svc = service()
    t = tech()
    b = empty_block(svc, t)

    cust =
      Customer
      |> Ash.Changeset.for_create(:create_guest, %{
        name: "Booked",
        email: "booked-#{System.unique_integer([:positive])}@test.com",
        phone: "+15125550177"
      })
      |> Ash.create!(authorize?: false)

    vehicle =
      Vehicle
      |> Ash.Changeset.for_create(:create, %{make: "Kia", model: "Soul", size: :car})
      |> Ash.Changeset.force_change_attribute(:customer_id, cust.id)
      |> Ash.create!(authorize?: false)

    address =
      Address
      |> Ash.Changeset.for_create(:create, %{
        street: "5 Elm",
        city: "Austin",
        state: "TX",
        zip: "78701"
      })
      |> Ash.Changeset.force_change_attribute(:customer_id, cust.id)
      |> Ash.create!(authorize?: false)

    Appointment
    |> Ash.Changeset.for_create(:admin_book, %{
      scheduled_at: b.starts_at,
      customer_id: cust.id,
      vehicle_id: vehicle.id,
      address_id: address.id,
      service_type_id: svc.id,
      price_cents: 5000,
      duration_minutes: 45
    })
    |> Ash.Changeset.force_change_attribute(:appointment_block_id, b.id)
    |> Ash.create!(authorize?: false)

    conn = sign_in(conn, create_admin())
    {:ok, view, _html} = live(conn, ~p"/admin/blocks")

    assert has_element?(view, "#block-#{b.id} .block-locked")
    refute has_element?(view, "#block-#{b.id} button[phx-click='delete_block']")
  end
end
