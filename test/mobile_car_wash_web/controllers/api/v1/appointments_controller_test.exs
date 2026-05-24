defmodule MobileCarWashWeb.Api.V1.AppointmentsControllerTest do
  use MobileCarWashWeb.ApiCase

  alias MobileCarWash.Operations.{AppointmentChecklist, ChecklistItem, Procedure, ProcedureStep}
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

    test "keeps live in-progress appointments visible after their scheduled time", %{conn: conn} do
      {authed, customer, _} = register_and_sign_in(conn)

      past =
        DateTime.utc_now()
        |> DateTime.add(-900, :second)
        |> DateTime.truncate(:second)

      appt =
        customer.id
        |> create_appointment(:in_progress)
        |> Ash.Changeset.for_update(:update, %{scheduled_at: past})
        |> Ash.update!()

      conn = get(authed, ~p"/api/v1/appointments")
      body = json_response(conn, 200)

      assert [returned] = body["data"]
      assert returned["id"] == appt.id
      assert returned["status"] == "in_progress"
    end

    test "does not keep stale live appointments visible forever", %{conn: conn} do
      {authed, customer, _} = register_and_sign_in(conn)

      stale =
        DateTime.utc_now()
        |> DateTime.add(-24 * 3600, :second)
        |> DateTime.truncate(:second)

      customer.id
      |> create_appointment(:in_progress)
      |> Ash.Changeset.for_update(:update, %{scheduled_at: stale})
      |> Ash.update!()

      conn = get(authed, ~p"/api/v1/appointments")
      body = json_response(conn, 200)

      assert body["data"] == []
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

    test "returns live progress snapshot for an in-progress appointment", %{conn: conn} do
      {authed, customer, _} = register_and_sign_in(conn)

      appt = create_appointment(customer.id, :in_progress)
      create_started_checklist(appt)

      conn = get(authed, ~p"/api/v1/appointments/#{appt.id}")
      body = json_response(conn, 200)

      assert body["status"] == "in_progress"
      assert body["live_progress"]["current_step"] == "Hand Wash"
      assert body["live_progress"]["current_step_number"] == 2
      assert body["live_progress"]["steps_done"] == 1
      assert body["live_progress"]["completed_steps"] == 1
      assert body["live_progress"]["steps_total"] == 3
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

  defp create_started_checklist(appt) do
    {:ok, procedure} =
      Procedure
      |> Ash.Changeset.for_create(:create, %{
        name: "Snapshot Wash",
        slug: "snapshot-wash-#{System.unique_integer([:positive])}"
      })
      |> Ash.create()

    steps =
      for {title, number} <- [{"Inspect", 1}, {"Hand Wash", 2}, {"Dry", 3}] do
        {:ok, step} =
          ProcedureStep
          |> Ash.Changeset.for_create(:create, %{
            title: title,
            step_number: number,
            estimated_minutes: 5
          })
          |> Ash.Changeset.force_change_attribute(:procedure_id, procedure.id)
          |> Ash.create()

        step
      end

    {:ok, checklist} =
      AppointmentChecklist
      |> Ash.Changeset.for_create(:create, %{status: :in_progress})
      |> Ash.Changeset.force_change_attribute(:appointment_id, appt.id)
      |> Ash.Changeset.force_change_attribute(:procedure_id, procedure.id)
      |> Ash.create()

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    steps
    |> Enum.each(fn step ->
      attrs = %{
        title: step.title,
        step_number: step.step_number,
        estimated_minutes: step.estimated_minutes,
        started_at: if(step.step_number in [1, 2], do: now),
        completed: step.step_number == 1,
        completed_at: if(step.step_number == 1, do: now)
      }

      {:ok, _item} =
        ChecklistItem
        |> Ash.Changeset.for_create(:create, attrs)
        |> Ash.Changeset.force_change_attribute(:checklist_id, checklist.id)
        |> Ash.Changeset.force_change_attribute(:procedure_step_id, step.id)
        |> Ash.create()
    end)
  end
end
