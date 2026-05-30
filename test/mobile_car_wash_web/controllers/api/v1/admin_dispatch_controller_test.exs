defmodule MobileCarWashWeb.Api.V1.AdminDispatchControllerTest do
  use MobileCarWashWeb.ApiCase

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Fleet.{Address, Vehicle}
  alias MobileCarWash.Operations.Technician
  alias MobileCarWash.Scheduling.{Appointment, ServiceType}

  describe "GET /api/v1/admin/dispatch" do
    test "returns command center state for the requested date", %{conn: conn} do
      {authed, _admin, _token} = register_and_sign_in_admin(conn)
      %{appointment: appointment, customer: customer} = create_dispatch_appointment()

      conn = get(authed, ~p"/api/v1/admin/dispatch?date=2031-02-03")
      body = json_response(conn, 200)

      assert body["data"]["date"] == "2031-02-03"
      assert body["data"]["metrics"]["total"] == 1
      assert body["data"]["metrics"]["ready_to_assign"] == 1
      assert body["data"]["metrics"]["exceptions"] == 1
      assert [queued] = body["data"]["assignment_queue"]
      assert queued["id"] == appointment.id
      assert queued["customer_id"] == customer.id
      assert queued["customer_name"] == customer.name
      assert queued["service_name"] == "Command Detail"
      assert queued["address_line"] == "200 Dispatch Lane, San Antonio, TX 78258"
      assert queued["vehicle_name"] == "2025 White Toyota Tacoma"
      assert [%{"kind" => "unassigned"}] = body["data"]["exceptions"]

      assert [%{"assigned_count" => 0, "status" => "available"}] =
               body["data"]["technician_workload"]
    end
  end

  describe "POST /api/v1/admin/dispatch/appointments/:id/assign" do
    test "assigns a technician and returns the updated dispatch appointment", %{conn: conn} do
      {authed, _admin, _token} = register_and_sign_in_admin(conn)
      %{appointment: appointment, technician: technician} = create_dispatch_appointment()

      conn =
        post(authed, ~p"/api/v1/admin/dispatch/appointments/#{appointment.id}/assign", %{
          "technician_id" => technician.id
        })

      body = json_response(conn, 200)

      assert body["data"]["id"] == appointment.id
      assert body["data"]["technician_id"] == technician.id
      assert body["data"]["technician_name"] == technician.name
    end
  end

  describe "POST /api/v1/admin/dispatch/appointments/:id/confirm" do
    test "confirms an assigned appointment and returns the updated dispatch appointment", %{
      conn: conn
    } do
      {authed, _admin, _token} = register_and_sign_in_admin(conn)
      %{appointment: appointment, technician: technician} = create_dispatch_appointment()
      assign_technician(appointment, technician)

      conn = post(authed, ~p"/api/v1/admin/dispatch/appointments/#{appointment.id}/confirm")
      body = json_response(conn, 200)

      assert body["data"]["id"] == appointment.id
      assert body["data"]["status"] == "confirmed"
      assert body["data"]["technician_id"] == technician.id
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

  defp create_dispatch_appointment do
    {:ok, customer} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "dispatch-api-#{System.unique_integer([:positive])}@example.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Riley Dispatch",
        phone: "+15125550125"
      })
      |> Ash.create()

    {:ok, service} =
      ServiceType
      |> Ash.Changeset.for_create(:create, %{
        name: "Command Detail",
        slug: "command-detail-#{System.unique_integer([:positive])}",
        base_price_cents: 14_000,
        duration_minutes: 120
      })
      |> Ash.create()

    {:ok, vehicle} =
      Vehicle
      |> Ash.Changeset.for_create(:create, %{
        year: 2025,
        make: "Toyota",
        model: "Tacoma",
        color: "White",
        size: :pickup
      })
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create()

    {:ok, address} =
      Address
      |> Ash.Changeset.for_create(:create, %{
        street: "200 Dispatch Lane",
        city: "San Antonio",
        state: "TX",
        zip: "78258"
      })
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create()

    {:ok, technician} =
      Technician
      |> Ash.Changeset.for_create(:create, %{
        name: "Casey Command",
        phone: "+15125559877",
        active: true,
        status: :available
      })
      |> Ash.create()

    {:ok, appointment} =
      Appointment
      |> Ash.Changeset.for_create(:book, %{
        customer_id: customer.id,
        vehicle_id: vehicle.id,
        address_id: address.id,
        service_type_id: service.id,
        scheduled_at: ~U[2031-02-03 16:00:00Z],
        price_cents: 14_000,
        duration_minutes: 120
      })
      |> Ash.create()

    %{
      appointment: appointment,
      customer: customer,
      technician: technician
    }
  end

  defp assign_technician(appointment, technician) do
    appointment
    |> Ash.Changeset.for_update(:update, %{})
    |> Ash.Changeset.force_change_attribute(:technician_id, technician.id)
    |> Ash.update!(authorize?: false)
  end
end
