defmodule MobileCarWashWeb.Api.V1.AppointmentsControllerTest do
  use MobileCarWashWeb.ApiCase

  alias MobileCarWash.Scheduling.{Appointment, ServiceType}

  defp create_appointment(customer_id, status \\ :pending) do
    {:ok, service} =
      ServiceType
      |> Ash.Changeset.for_create(:create, %{
        name: "Basic",
        slug: "basic_appt_#{:rand.uniform(100_000)}",
        base_price_cents: 5000,
        duration_minutes: 45
      })
      |> Ash.create()

    {:ok, vehicle} =
      MobileCarWash.Fleet.Vehicle
      |> Ash.Changeset.for_create(:create, %{make: "T", model: "M", size: :car})
      |> Ash.Changeset.force_change_attribute(:customer_id, customer_id)
      |> Ash.create()

    {:ok, address} =
      MobileCarWash.Fleet.Address
      |> Ash.Changeset.for_create(:create, %{
        street: "1 A St",
        city: "San Antonio",
        state: "TX",
        zip: "78261"
      })
      |> Ash.Changeset.force_change_attribute(:customer_id, customer_id)
      |> Ash.create()

    scheduled_at =
      DateTime.utc_now() |> DateTime.add(86_400, :second) |> DateTime.truncate(:second)

    {:ok, appt} =
      Appointment
      |> Ash.Changeset.for_create(:book, %{
        customer_id: customer_id,
        vehicle_id: vehicle.id,
        address_id: address.id,
        service_type_id: service.id,
        scheduled_at: scheduled_at,
        price_cents: 5000,
        duration_minutes: 45
      })
      |> Ash.create()

    # Optional status override
    if status != :pending do
      {:ok, updated} =
        appt
        |> Ash.Changeset.for_update(:update, %{status: status})
        |> Ash.update()

      updated
    else
      appt
    end
  end

  describe "GET /api/v1/appointments" do
    test "requires authentication", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/appointments")
      assert json_response(conn, 401)
    end

    test "returns upcoming (pending/confirmed, scheduled_at > now) appointments for current customer",
         %{conn: conn} do
      {authed, customer, _} = register_and_sign_in(conn)
      upcoming = create_appointment(customer.id, :pending)
      _completed = create_appointment(customer.id, :completed)

      conn = get(authed, ~p"/api/v1/appointments")
      body = json_response(conn, 200)

      assert [returned] = body["data"]
      assert returned["id"] == upcoming.id
      assert returned["status"] == "pending"
    end

    test "does not return another customer's appointments", %{conn: conn} do
      {authed, _, _} = register_and_sign_in(conn)

      {:ok, other} =
        MobileCarWash.Accounts.Customer
        |> Ash.Changeset.for_create(:create_guest, %{
          email: "stranger-#{:rand.uniform(100_000)}@example.com",
          name: "Stranger"
        })
        |> Ash.create()

      _other_appt = create_appointment(other.id)

      conn = get(authed, ~p"/api/v1/appointments")
      body = json_response(conn, 200)
      assert body["data"] == []
    end
  end

  describe "GET /api/v1/appointments/:id" do
    test "returns appointment detail for the owner", %{conn: conn} do
      {authed, customer, _} = register_and_sign_in(conn)
      appt = create_appointment(customer.id)

      conn = get(authed, ~p"/api/v1/appointments/#{appt.id}")
      body = json_response(conn, 200)

      assert body["id"] == appt.id
      assert body["status"] == "pending"
    end

    test "returns 404 when fetching another customer's appointment", %{conn: conn} do
      {authed, _, _} = register_and_sign_in(conn)

      {:ok, other} =
        MobileCarWash.Accounts.Customer
        |> Ash.Changeset.for_create(:create_guest, %{
          email: "other-appt-#{:rand.uniform(100_000)}@example.com",
          name: "X"
        })
        |> Ash.create()

      appt = create_appointment(other.id)

      conn = get(authed, ~p"/api/v1/appointments/#{appt.id}")
      assert json_response(conn, 404)
    end
  end

  describe "DELETE /api/v1/appointments/:id" do
    test "requires authentication", %{conn: conn} do
      conn = delete(conn, ~p"/api/v1/appointments/11111111-1111-1111-1111-111111111111")
      assert json_response(conn, 401)
    end

    test "cancels a pending appointment for the owner", %{conn: conn} do
      {authed, customer, _} = register_and_sign_in(conn)
      appt = create_appointment(customer.id, :pending)

      conn = delete(authed, ~p"/api/v1/appointments/#{appt.id}")
      body = json_response(conn, 200)

      assert body["id"] == appt.id
      assert body["status"] == "cancelled"

      {:ok, reloaded} = Ash.get(Appointment, appt.id, authorize?: false)
      assert reloaded.status == :cancelled
    end

    test "rejects cancellation of an in_progress appointment with 422", %{conn: conn} do
      {authed, customer, _} = register_and_sign_in(conn)
      appt = create_appointment(customer.id, :in_progress)

      conn = delete(authed, ~p"/api/v1/appointments/#{appt.id}")
      body = json_response(conn, 422)
      assert body["error"]
    end

    test "rejects cancellation of a completed appointment with 422", %{conn: conn} do
      {authed, customer, _} = register_and_sign_in(conn)
      appt = create_appointment(customer.id, :completed)

      conn = delete(authed, ~p"/api/v1/appointments/#{appt.id}")
      assert json_response(conn, 422)
    end

    test "returns 404 when cancelling another customer's appointment", %{conn: conn} do
      {authed, _, _} = register_and_sign_in(conn)

      {:ok, other} =
        MobileCarWash.Accounts.Customer
        |> Ash.Changeset.for_create(:create_guest, %{
          email: "other-cancel-#{:rand.uniform(100_000)}@example.com",
          name: "X"
        })
        |> Ash.create()

      appt = create_appointment(other.id)

      conn = delete(authed, ~p"/api/v1/appointments/#{appt.id}")
      assert json_response(conn, 404)
    end
  end
end
