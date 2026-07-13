defmodule MobileCarWash.Operations.AppointmentChecklistWrapUpTest do
  use MobileCarWash.DataCase, async: true

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Fleet.{Address, Vehicle}
  alias MobileCarWash.Operations.{AppointmentChecklist, Procedure}
  alias MobileCarWash.Scheduling.{Appointment, ServiceType}

  test "save_wrap_up persists final notes" do
    checklist = create_checklist!()

    {:ok, updated} =
      checklist
      |> Ash.Changeset.for_update(:save_wrap_up, %{final_notes: "Customer loved the shine."})
      |> Ash.update(authorize?: false)

    assert updated.final_notes == "Customer loved the shine."

    reloaded = Ash.get!(AppointmentChecklist, checklist.id, authorize?: false)
    assert reloaded.final_notes == "Customer loved the shine."
  end

  test "save_wrap_up accepts a blank final note" do
    checklist = create_checklist!()

    {:ok, updated} =
      checklist
      |> Ash.Changeset.for_update(:save_wrap_up, %{final_notes: ""})
      |> Ash.update(authorize?: false)

    assert updated.final_notes == ""
  end

  defp create_checklist! do
    {:ok, customer} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "wrap-checklist-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Wrap Customer",
        phone: "+15125550900"
      })
      |> Ash.create()

    {:ok, service} =
      ServiceType
      |> Ash.Changeset.for_create(:create, %{
        name: "Wrap Wash",
        slug: "wrap-wash-#{System.unique_integer([:positive])}",
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
        street: "100 Wrap Ave",
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

    {:ok, procedure} =
      Procedure
      |> Ash.Changeset.for_create(:create, %{
        name: "Wrap SOP",
        slug: "wrap-sop-#{System.unique_integer([:positive])}"
      })
      |> Ash.Changeset.force_change_attribute(:service_type_id, service.id)
      |> Ash.create()

    AppointmentChecklist
    |> Ash.Changeset.for_create(:create, %{status: :completed})
    |> Ash.Changeset.force_change_attribute(:appointment_id, appointment.id)
    |> Ash.Changeset.force_change_attribute(:procedure_id, procedure.id)
    |> Ash.create!(authorize?: false)
  end
end
