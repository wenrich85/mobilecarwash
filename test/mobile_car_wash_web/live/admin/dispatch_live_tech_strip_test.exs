defmodule MobileCarWashWeb.Admin.DispatchLiveTechStripTest do
  @moduledoc """
  Covers the Slice D addition to admin dispatch: the "Techs on shift"
  strip that shows each active technician's duty status and current
  appointment, updated live via TechnicianTracker's firehose topic.
  """
  use MobileCarWashWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  require Ash.Query

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Operations.Technician

  defp create_admin do
    {:ok, admin} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "admin-dispatch-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Dispatch Admin",
        phone: "+15125550301"
      })
      |> Ash.create()

    {:ok, admin} =
      admin
      |> Ash.Changeset.for_update(:update, %{role: :admin})
      |> Ash.update(authorize?: false)

    admin
  end

  defp sign_in(conn, user) do
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> post("/auth/customer/password/sign_in", %{
      "customer" => %{
        "email" => to_string(user.email),
        "password" => "Password123!"
      }
    })
    |> recycle()
  end

  defp create_tech(name, status) do
    {:ok, tech} =
      Technician
      |> Ash.Changeset.for_create(:create, %{
        name: name,
        phone: "+15125550#{:rand.uniform(999) |> Integer.to_string() |> String.pad_leading(3, "0")}",
        active: true
      })
      |> Ash.create()

    {:ok, tech} =
      tech
      |> Ash.Changeset.for_update(:set_status, %{status: status})
      |> Ash.update()

    tech
  end

  defp create_active_appointment(tech_id, status) do
    {:ok, service} =
      MobileCarWash.Scheduling.ServiceType
      |> Ash.Changeset.for_create(:create, %{
        name: "Basic Wash",
        slug: "strip-#{System.unique_integer([:positive])}",
        base_price_cents: 5_000,
        duration_minutes: 45
      })
      |> Ash.create()

    {:ok, customer} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "strip-cust-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Smith Active",
        phone: "+15125551001"
      })
      |> Ash.create()

    {:ok, vehicle} =
      MobileCarWash.Fleet.Vehicle
      |> Ash.Changeset.for_create(:create, %{make: "Toyota", model: "Camry"})
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create()

    {:ok, address} =
      MobileCarWash.Fleet.Address
      |> Ash.Changeset.for_create(:create, %{
        street: "50 Strip St",
        city: "San Antonio",
        state: "TX",
        zip: "78259"
      })
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create()

    {:ok, appt} =
      MobileCarWash.Scheduling.Appointment
      |> Ash.Changeset.for_create(:book, %{
        customer_id: customer.id,
        vehicle_id: vehicle.id,
        address_id: address.id,
        service_type_id: service.id,
        scheduled_at: DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second),
        price_cents: 5_000,
        duration_minutes: 45
      })
      |> Ash.create()

    appt
    |> Ash.Changeset.for_update(:update, %{})
    |> Ash.Changeset.force_change_attribute(:technician_id, tech_id)
    |> Ash.Changeset.force_change_attribute(:status, status)
    |> Ash.update!(authorize?: false)
  end

  describe "techs on shift strip" do
    setup %{conn: conn} do
      admin = create_admin()
      conn = sign_in(conn, admin)
      {:ok, conn: conn}
    end

    test "lists each active technician with their duty status", %{conn: conn} do
      _miguel = create_tech("Miguel Dispatch", :available)
      _sam = create_tech("Sam Dispatch", :on_break)

      {:ok, _view, html} = live(conn, ~p"/admin/dispatch")

      assert html =~ "Miguel Dispatch"
      assert html =~ "Sam Dispatch"
      assert html =~ "Available"
      assert html =~ "On break"
    end

    test "shows the current active appointment when the tech has one in progress",
         %{conn: conn} do
      miguel = create_tech("Miguel Active", :available)
      _appt = create_active_appointment(miguel.id, :en_route)

      {:ok, _view, html} = live(conn, ~p"/admin/dispatch")

      # Card should surface the customer-facing activity ("En route to Smith")
      # on top of the plain duty-status line.
      assert html =~ "En route"
      assert html =~ "Smith Active"
    end

    test "reflects a status change pushed via TechnicianTracker", %{conn: conn} do
      tech = create_tech("Live Tech", :available)

      {:ok, view, initial_html} = live(conn, ~p"/admin/dispatch")
      assert initial_html =~ "Available"

      # Flip the status out-of-band (simulating the tech tapping Break
      # on their dashboard); the firehose broadcast should reach the LV.
      tech
      |> Ash.Changeset.for_update(:set_status, %{status: :on_break})
      |> Ash.update!()

      # Two renders: the broadcast enqueues a handle_info, and the LV
      # rerenders on the next cycle.
      _ = render(view)
      assert render(view) =~ "On break"
    end
  end
end
