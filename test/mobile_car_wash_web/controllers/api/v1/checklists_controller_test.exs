defmodule MobileCarWashWeb.Api.V1.ChecklistsControllerTest do
  use MobileCarWashWeb.ApiCase

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Fleet.{Address, Vehicle}

  alias MobileCarWash.Operations.{
    AppointmentChecklist,
    ChecklistItem,
    Procedure,
    ProcedureStep,
    Technician
  }

  alias MobileCarWash.Scheduling.{Appointment, AppointmentTracker, ServiceType}

  require Ash.Query

  defp register_and_sign_in_tech(conn) do
    {authed, user, _token} =
      register_and_sign_in(conn,
        email: "checklist-tech-#{System.unique_integer([:positive])}@example.com"
      )

    {:ok, user} =
      user
      |> Ash.Changeset.for_update(:update, %{role: :technician})
      |> Ash.update(authorize?: false)

    {:ok, tech} =
      Technician
      |> Ash.Changeset.for_create(:create, %{name: user.name, phone: user.phone, active: true})
      |> Ash.create()

    {:ok, tech} =
      tech
      |> Ash.Changeset.for_update(:update, %{})
      |> Ash.Changeset.force_change_attribute(:user_account_id, user.id)
      |> Ash.update(authorize?: false)

    {authed, tech}
  end

  defp appointment_with_checklist(tech_id) do
    {:ok, customer} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "checklist-customer-#{System.unique_integer([:positive])}@example.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Checklist Customer",
        phone: "+15125559900"
      })
      |> Ash.create()

    {:ok, service} =
      ServiceType
      |> Ash.Changeset.for_create(:create, %{
        name: "Checklist Wash",
        slug: "checklist-wash-#{System.unique_integer([:positive])}",
        base_price_cents: 5_000,
        duration_minutes: 45
      })
      |> Ash.create()

    {:ok, vehicle} =
      Vehicle
      |> Ash.Changeset.for_create(:create, %{make: "Toyota", model: "Camry"})
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create()

    {:ok, address} =
      Address
      |> Ash.Changeset.for_create(:create, %{
        street: "100 API Ave",
        city: "San Antonio",
        state: "TX",
        zip: "78259"
      })
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create()

    {:ok, appointment} =
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

    appointment =
      appointment
      |> Ash.Changeset.for_update(:update, %{})
      |> Ash.Changeset.force_change_attribute(:technician_id, tech_id)
      |> Ash.Changeset.force_change_attribute(:status, :in_progress)
      |> Ash.update!(authorize?: false)

    {:ok, procedure} =
      Procedure
      |> Ash.Changeset.for_create(:create, %{
        name: "Checklist SOP",
        slug: "checklist-sop-#{System.unique_integer([:positive])}"
      })
      |> Ash.Changeset.force_change_attribute(:service_type_id, service.id)
      |> Ash.Changeset.force_change_attribute(:active, true)
      |> Ash.create()

    {:ok, first_step} =
      ProcedureStep
      |> Ash.Changeset.for_create(:create, %{
        step_number: 1,
        title: "Pre-rinse",
        estimated_minutes: 5
      })
      |> Ash.Changeset.force_change_attribute(:procedure_id, procedure.id)
      |> Ash.create()

    {:ok, second_step} =
      ProcedureStep
      |> Ash.Changeset.for_create(:create, %{
        step_number: 2,
        title: "Foam wash",
        estimated_minutes: 10
      })
      |> Ash.Changeset.force_change_attribute(:procedure_id, procedure.id)
      |> Ash.create()

    {:ok, checklist} =
      AppointmentChecklist
      |> Ash.Changeset.for_create(:create, %{status: :in_progress})
      |> Ash.Changeset.force_change_attribute(:appointment_id, appointment.id)
      |> Ash.Changeset.force_change_attribute(:procedure_id, procedure.id)
      |> Ash.create()

    {:ok, first_item} =
      ChecklistItem
      |> Ash.Changeset.for_create(:create, %{
        step_number: 1,
        title: "Pre-rinse",
        estimated_minutes: 5
      })
      |> Ash.Changeset.force_change_attribute(:checklist_id, checklist.id)
      |> Ash.Changeset.force_change_attribute(:procedure_step_id, first_step.id)
      |> Ash.create()

    {:ok, _second_item} =
      ChecklistItem
      |> Ash.Changeset.for_create(:create, %{
        step_number: 2,
        title: "Foam wash",
        estimated_minutes: 10
      })
      |> Ash.Changeset.force_change_attribute(:checklist_id, checklist.id)
      |> Ash.Changeset.force_change_attribute(:procedure_step_id, second_step.id)
      |> Ash.create()

    {appointment, checklist, first_item}
  end

  describe "POST /api/v1/checklists/:id/items/:item_id/start" do
    test "broadcasts customer progress when a step starts", %{conn: conn} do
      {authed, tech} = register_and_sign_in_tech(conn)
      {appointment, checklist, item} = appointment_with_checklist(tech.id)

      AppointmentTracker.subscribe(appointment.id)

      conn = post(authed, ~p"/api/v1/checklists/#{checklist.id}/items/#{item.id}/start")

      assert json_response(conn, 200)["data"]["id"] == item.id

      assert Ash.get!(AppointmentChecklist, checklist.id, authorize?: false).status ==
               :in_progress

      assert_receive {:appointment_update,
                      %{
                        event: :step_update,
                        appointment_id: appointment_id,
                        current_step: "Pre-rinse",
                        current_step_number: 1,
                        message: "Step 1/2: Pre-rinse",
                        steps_done: 0,
                        completed_steps: 0,
                        steps_total: 2
                      }},
                     500

      assert appointment_id == appointment.id
    end
  end

  describe "POST /api/v1/checklists/:id/items/:item_id/complete" do
    test "marks the checklist completed when the final required step is completed", %{conn: conn} do
      {authed, tech} = register_and_sign_in_tech(conn)
      {_appointment, checklist, first_item} = appointment_with_checklist(tech.id)

      {:ok, first_item} =
        first_item
        |> Ash.Changeset.for_update(:start_step, %{})
        |> Ash.update(authorize?: false)

      {:ok, _first_item} =
        first_item
        |> Ash.Changeset.for_update(:check, %{})
        |> Ash.update(authorize?: false)

      second_item =
        ChecklistItem
        |> Ash.Query.filter(checklist_id == ^checklist.id and step_number == 2)
        |> Ash.read_one!(authorize?: false)

      {:ok, second_item} =
        second_item
        |> Ash.Changeset.for_update(:start_step, %{})
        |> Ash.update(authorize?: false)

      conn = post(authed, ~p"/api/v1/checklists/#{checklist.id}/items/#{second_item.id}/complete")

      assert json_response(conn, 200)["data"]["id"] == second_item.id
      assert Ash.get!(AppointmentChecklist, checklist.id, authorize?: false).status == :completed
    end
  end
end
