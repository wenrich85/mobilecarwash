defmodule MobileCarWashWeb.Api.V1.AdminAppointmentsControllerTest do
  use MobileCarWashWeb.ApiCase

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Fleet.{Address, Vehicle}
  alias MobileCarWash.Operations.Technician
  alias MobileCarWash.Scheduling.{Appointment, ServiceType}

  describe "GET /api/v1/admin/appointments" do
    test "requires admin role", %{conn: conn} do
      {authed, _customer, _token} = register_and_sign_in(conn)

      conn = get(authed, ~p"/api/v1/admin/appointments")

      assert json_response(conn, 403)
    end

    test "returns enriched admin appointments filtered by date", %{conn: conn} do
      {authed, _admin, _token} = register_and_sign_in_admin(conn)

      %{appointment: appointment, customer: customer, technician: technician} =
        create_admin_appointment()

      conn = get(authed, ~p"/api/v1/admin/appointments?date=2031-02-03")
      body = json_response(conn, 200)

      assert [returned] = body["data"]
      assert returned["id"] == appointment.id
      assert returned["status"] == "confirmed"
      assert returned["customer_id"] == customer.id
      assert returned["customer_name"] == customer.name
      assert returned["technician_id"] == technician.id
      assert returned["technician_name"] == technician.name
      assert returned["service_name"] == "Executive Detail"
      assert returned["address_line"] == "100 Admin Way, San Antonio, TX 78259"
      assert returned["vehicle_name"] == "2026 Black Lexus GX"
    end
  end

  describe "GET /api/v1/admin/appointments/:id" do
    test "returns one enriched admin appointment", %{conn: conn} do
      {authed, _admin, _token} = register_and_sign_in_admin(conn)
      %{appointment: appointment} = create_admin_appointment()

      conn = get(authed, ~p"/api/v1/admin/appointments/#{appointment.id}")
      body = json_response(conn, 200)

      assert body["data"]["id"] == appointment.id
      assert body["data"]["service_name"] == "Executive Detail"
    end
  end

  defp register_and_sign_in_admin(conn) do
    {authed, customer, token} = register_and_sign_in(conn)

    {:ok, admin} =
      customer
      |> Ash.Changeset.for_update(:update, %{role: :admin})
      |> Ash.update(authorize?: false)

    {authed, admin, token}
  end

  defp create_admin_appointment do
    {:ok, customer} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "admin-appt-#{System.unique_integer([:positive])}@example.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Jordan Customer",
        phone: "+15125550123"
      })
      |> Ash.create()

    {:ok, service} =
      ServiceType
      |> Ash.Changeset.for_create(:create, %{
        name: "Executive Detail",
        slug: "executive-detail-#{System.unique_integer([:positive])}",
        base_price_cents: 12_000,
        duration_minutes: 90
      })
      |> Ash.create()

    {:ok, vehicle} =
      Vehicle
      |> Ash.Changeset.for_create(:create, %{
        year: 2026,
        make: "Lexus",
        model: "GX",
        color: "Black",
        size: :suv_van
      })
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create()

    {:ok, address} =
      Address
      |> Ash.Changeset.for_create(:create, %{
        street: "100 Admin Way",
        city: "San Antonio",
        state: "TX",
        zip: "78259"
      })
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create()

    {:ok, technician} =
      Technician
      |> Ash.Changeset.for_create(:create, %{
        name: "Mina Tech",
        phone: "+15125559876",
        active: true
      })
      |> Ash.create()

    scheduled_at = ~U[2031-02-03 15:30:00Z]

    {:ok, appointment} =
      Appointment
      |> Ash.Changeset.for_create(:book, %{
        customer_id: customer.id,
        vehicle_id: vehicle.id,
        address_id: address.id,
        service_type_id: service.id,
        scheduled_at: scheduled_at,
        price_cents: 12_000,
        duration_minutes: 90
      })
      |> Ash.create()

    appointment =
      appointment
      |> Ash.Changeset.for_update(:update, %{})
      |> Ash.Changeset.force_change_attribute(:status, :confirmed)
      |> Ash.Changeset.force_change_attribute(:technician_id, technician.id)
      |> Ash.update!(authorize?: false)

    %{
      appointment: appointment,
      customer: customer,
      technician: technician
    }
  end
end
