defmodule MobileCarWashWeb.Api.V1.TechControllerTest do
  @moduledoc """
  Role-gated tech-facing API. Every route under /api/v1/tech requires
  role == :technician or :admin. Non-tech customers get 403; unauthenticated
  requests get 401.

  Covers:
    * GET /api/v1/tech/me
    * PATCH /api/v1/tech/me/status
    * GET /api/v1/tech/appointments
    * POST /api/v1/tech/appointments/:id/depart
    * POST /api/v1/tech/appointments/:id/arrive
    * POST /api/v1/tech/appointments/:id/start
    * POST /api/v1/tech/appointments/:id/complete
  """
  use MobileCarWashWeb.ApiCase

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Operations.Technician
  alias MobileCarWash.Scheduling.Appointment

  defp register_and_sign_in_tech(conn) do
    {authed, user, token} =
      register_and_sign_in(conn, email: "api-tech-#{:rand.uniform(100_000)}@example.com")

    {:ok, user} =
      user
      |> Ash.Changeset.for_update(:update, %{role: :technician})
      |> Ash.update(authorize?: false)

    {:ok, tech} =
      Technician
      |> Ash.Changeset.for_create(:create, %{
        name: user.name,
        phone: user.phone,
        active: true
      })
      |> Ash.create()

    {:ok, tech} =
      tech
      |> Ash.Changeset.for_update(:update, %{})
      |> Ash.Changeset.force_change_attribute(:user_account_id, user.id)
      |> Ash.update(authorize?: false)

    {authed, user, tech, token}
  end

  defp create_customer_appointment(tech_id, status) do
    {:ok, customer} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "tech-appt-cust-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "API Customer",
        phone: "+15125559500"
      })
      |> Ash.create()

    {:ok, service} =
      MobileCarWash.Scheduling.ServiceType
      |> Ash.Changeset.for_create(:create, %{
        name: "Basic Wash",
        slug: "tech-api-#{System.unique_integer([:positive])}",
        base_price_cents: 5_000,
        duration_minutes: 45
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
        street: "100 API Ave",
        city: "San Antonio",
        state: "TX",
        zip: "78259"
      })
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create()

    {:ok, appt} =
      Appointment
      |> Ash.Changeset.for_create(:book, %{
        customer_id: customer.id,
        vehicle_id: vehicle.id,
        address_id: address.id,
        service_type_id: service.id,
        scheduled_at:
          DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second),
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

  describe "auth gating" do
    test "GET /me returns 401 without a token", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/tech/me")
      assert json_response(conn, 401)
    end

    test "GET /me returns 403 when the signed-in customer is not a tech",
         %{conn: conn} do
      {authed, _user, _token} = register_and_sign_in(conn)
      conn = get(authed, ~p"/api/v1/tech/me")
      assert json_response(conn, 403)
    end
  end

  describe "GET /api/v1/tech/me" do
    test "returns the signed-in technician's profile + duty status",
         %{conn: conn} do
      {authed, _user, tech, _} = register_and_sign_in_tech(conn)

      conn = get(authed, ~p"/api/v1/tech/me")
      body = json_response(conn, 200)

      assert body["data"]["id"] == tech.id
      assert body["data"]["name"] == tech.name
      assert body["data"]["status"] == "off_duty"
    end
  end

  describe "PATCH /api/v1/tech/me/status" do
    test "transitions duty status", %{conn: conn} do
      {authed, _user, tech, _} = register_and_sign_in_tech(conn)

      conn = patch(authed, ~p"/api/v1/tech/me/status", %{status: "available"})
      body = json_response(conn, 200)
      assert body["data"]["status"] == "available"

      {:ok, reloaded} = Ash.get(Technician, tech.id)
      assert reloaded.status == :available
    end

    test "rejects an unknown status with 422", %{conn: conn} do
      {authed, _user, _tech, _} = register_and_sign_in_tech(conn)

      conn = patch(authed, ~p"/api/v1/tech/me/status", %{status: "on_vacation"})
      assert json_response(conn, 422)
    end
  end

  describe "GET /api/v1/tech/appointments" do
    test "returns today's appointments for the signed-in tech, denormalized",
         %{conn: conn} do
      {authed, _user, tech, _} = register_and_sign_in_tech(conn)
      appt = create_customer_appointment(tech.id, :confirmed)

      conn = get(authed, ~p"/api/v1/tech/appointments")
      body = json_response(conn, 200)

      [row] = body["data"]
      assert row["id"] == appt.id
      assert row["status"] == "confirmed"
      assert row["service_name"] == "Basic Wash"
      assert row["customer_name"] == "API Customer"
      assert row["address"]["street"] == "100 API Ave"
      assert row["vehicle"]["make"] == "Toyota"
    end

    test "does not return another tech's appointments", %{conn: conn} do
      {authed, _user, _tech, _} = register_and_sign_in_tech(conn)

      {:ok, other_tech} =
        Technician
        |> Ash.Changeset.for_create(:create, %{name: "Other Tech", active: true})
        |> Ash.create()

      _other_appt = create_customer_appointment(other_tech.id, :confirmed)

      conn = get(authed, ~p"/api/v1/tech/appointments")
      body = json_response(conn, 200)
      assert body["data"] == []
    end
  end

  describe "POST /api/v1/tech/appointments/:id/depart" do
    test "transitions :confirmed -> :en_route and returns the updated appointment",
         %{conn: conn} do
      {authed, _user, tech, _} = register_and_sign_in_tech(conn)
      appt = create_customer_appointment(tech.id, :confirmed)

      conn = post(authed, ~p"/api/v1/tech/appointments/#{appt.id}/depart")
      body = json_response(conn, 200)
      assert body["data"]["status"] == "en_route"

      {:ok, reloaded} = Ash.get(Appointment, appt.id, authorize?: false)
      assert reloaded.status == :en_route
    end

    test "returns 404 when the appointment belongs to another tech",
         %{conn: conn} do
      {authed, _user, _tech, _} = register_and_sign_in_tech(conn)

      {:ok, other_tech} =
        Technician
        |> Ash.Changeset.for_create(:create, %{name: "Other", active: true})
        |> Ash.create()

      appt = create_customer_appointment(other_tech.id, :confirmed)

      conn = post(authed, ~p"/api/v1/tech/appointments/#{appt.id}/depart")
      assert json_response(conn, 404)
    end

    test "returns 422 when the appointment is already past the pre-wash states",
         %{conn: conn} do
      {authed, _user, tech, _} = register_and_sign_in_tech(conn)
      appt = create_customer_appointment(tech.id, :completed)

      conn = post(authed, ~p"/api/v1/tech/appointments/#{appt.id}/depart")
      assert json_response(conn, 422)
    end
  end

  describe "POST /api/v1/tech/appointments/:id/arrive" do
    test "transitions :en_route -> :on_site", %{conn: conn} do
      {authed, _user, tech, _} = register_and_sign_in_tech(conn)
      appt = create_customer_appointment(tech.id, :en_route)

      conn = post(authed, ~p"/api/v1/tech/appointments/#{appt.id}/arrive")
      body = json_response(conn, 200)
      assert body["data"]["status"] == "on_site"
    end
  end

  describe "POST /api/v1/tech/appointments/:id/start" do
    test "transitions :on_site -> :in_progress and returns checklist_id",
         %{conn: conn} do
      {authed, _user, tech, _} = register_and_sign_in_tech(conn)
      appt = create_customer_appointment(tech.id, :on_site)

      # WashOrchestrator.start_wash expects a Procedure defined for the
      # service_type; create one plus one step so the checklist seeding
      # succeeds.
      {:ok, procedure} =
        MobileCarWash.Operations.Procedure
        |> Ash.Changeset.for_create(:create, %{
          name: "SOP",
          slug: "sop-#{System.unique_integer([:positive])}"
        })
        |> Ash.Changeset.force_change_attribute(:service_type_id, appt.service_type_id)
        |> Ash.Changeset.force_change_attribute(:active, true)
        |> Ash.create()

      {:ok, _step} =
        MobileCarWash.Operations.ProcedureStep
        |> Ash.Changeset.for_create(:create, %{
          step_number: 1,
          title: "Pre-wash",
          estimated_minutes: 5
        })
        |> Ash.Changeset.force_change_attribute(:procedure_id, procedure.id)
        |> Ash.create()

      conn = post(authed, ~p"/api/v1/tech/appointments/#{appt.id}/start")
      body = json_response(conn, 200)

      assert body["data"]["appointment"]["status"] == "in_progress"
      assert body["data"]["checklist_id"]
    end
  end

  describe "POST /api/v1/tech/appointments/:id/complete" do
    test "transitions :in_progress -> :completed", %{conn: conn} do
      {authed, _user, tech, _} = register_and_sign_in_tech(conn)
      appt = create_customer_appointment(tech.id, :in_progress)

      conn = post(authed, ~p"/api/v1/tech/appointments/#{appt.id}/complete")
      body = json_response(conn, 200)
      assert body["data"]["status"] == "completed"
    end
  end
end
