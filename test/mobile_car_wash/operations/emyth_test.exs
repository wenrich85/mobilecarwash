defmodule MobileCarWash.Operations.EMythTest do
  use MobileCarWash.DataCase, async: true

  alias MobileCarWash.Operations.{
    OrgPosition,
    Procedure,
    ProcedureStep,
    AppointmentChecklist,
    ChecklistItem
  }

  require Ash.Query

  defp create_position(attrs \\ %{}) do
    defaults = %{name: "Test Position", slug: "test_pos_#{:rand.uniform(100_000)}", level: 0}

    OrgPosition
    |> Ash.Changeset.for_create(:create, Map.merge(defaults, attrs))
    |> Ash.create!()
  end

  defp create_procedure_with_steps do
    proc =
      Procedure
      |> Ash.Changeset.for_create(:create, %{
        name: "Test Procedure",
        slug: "test_proc_#{:rand.uniform(100_000)}",
        category: :wash
      })
      |> Ash.create!()

    steps =
      for n <- 1..3 do
        ProcedureStep
        |> Ash.Changeset.for_create(:create, %{
          step_number: n,
          title: "Step #{n}",
          description: "Do step #{n}",
          estimated_minutes: 5,
          required: n <= 2
        })
        |> Ash.Changeset.force_change_attribute(:procedure_id, proc.id)
        |> Ash.create!()
      end

    {proc, steps}
  end

  describe "org positions" do
    test "creates a position with hierarchy" do
      owner = create_position(%{name: "Owner", slug: "owner_test", level: 0})
      manager = create_position(%{name: "Manager", slug: "mgr_test", level: 1})

      {:ok, manager} =
        manager
        |> Ash.Changeset.for_update(:update, %{})
        |> Ash.Changeset.force_change_attribute(:parent_position_id, owner.id)
        |> Ash.update()

      assert manager.parent_position_id == owner.id
    end

    test "enforces unique slug" do
      slug = "unique_#{:rand.uniform(100_000)}"
      create_position(%{slug: slug})

      assert {:error, _} =
               OrgPosition
               |> Ash.Changeset.for_create(:create, %{name: "Dup", slug: slug})
               |> Ash.create()
    end
  end

  describe "procedures and steps" do
    test "creates a procedure with ordered steps" do
      {proc, steps} = create_procedure_with_steps()

      assert proc.name == "Test Procedure"
      assert length(steps) == 3
      assert Enum.at(steps, 0).step_number == 1
      assert Enum.at(steps, 2).step_number == 3
    end

    test "step 3 is optional, steps 1-2 are required" do
      {_proc, steps} = create_procedure_with_steps()

      assert Enum.at(steps, 0).required == true
      assert Enum.at(steps, 1).required == true
      assert Enum.at(steps, 2).required == false
    end
  end

  defp create_test_appointment do
    # Create required related records
    {:ok, customer} =
      MobileCarWash.Accounts.Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "tech-test-#{:rand.uniform(100_000)}@example.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Test Tech"
      })
      |> Ash.create()

    {:ok, service_type} =
      MobileCarWash.Scheduling.ServiceType
      |> Ash.Changeset.for_create(:create, %{
        name: "Test Wash",
        slug: "test_wash_#{:rand.uniform(100_000)}",
        base_price_cents: 5000,
        duration_minutes: 45
      })
      |> Ash.create()

    {:ok, vehicle} =
      MobileCarWash.Fleet.Vehicle
      |> Ash.Changeset.for_create(:create, %{make: "Toyota", model: "Test"})
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create()

    {:ok, address} =
      MobileCarWash.Fleet.Address
      |> Ash.Changeset.for_create(:create, %{
        street: "123 Test",
        city: "Austin",
        state: "TX",
        zip: "78701"
      })
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create()

    scheduled_at =
      DateTime.utc_now() |> DateTime.add(86_400, :second) |> DateTime.truncate(:second)

    {:ok, appointment} =
      MobileCarWash.Scheduling.Appointment
      |> Ash.Changeset.for_create(:book, %{
        customer_id: customer.id,
        vehicle_id: vehicle.id,
        address_id: address.id,
        service_type_id: service_type.id,
        scheduled_at: scheduled_at,
        price_cents: 5000,
        duration_minutes: 45
      })
      |> Ash.create()

    appointment
  end

  describe "appointment checklists" do
    test "creates checklist and items from procedure steps" do
      {proc, steps} = create_procedure_with_steps()
      appointment = create_test_appointment()
      appointment_id = appointment.id

      checklist =
        AppointmentChecklist
        |> Ash.Changeset.for_create(:create, %{status: :not_started})
        |> Ash.Changeset.force_change_attribute(:appointment_id, appointment_id)
        |> Ash.Changeset.force_change_attribute(:procedure_id, proc.id)
        |> Ash.create!()

      # Create checklist items from procedure steps
      items =
        for step <- steps do
          ChecklistItem
          |> Ash.Changeset.for_create(:create, %{
            step_number: step.step_number,
            title: step.title,
            description: step.description,
            required: step.required
          })
          |> Ash.Changeset.force_change_attribute(:checklist_id, checklist.id)
          |> Ash.Changeset.force_change_attribute(:procedure_step_id, step.id)
          |> Ash.create!()
        end

      assert length(items) == 3
      assert checklist.status == :not_started
    end

    test "checking items off updates completion" do
      {proc, steps} = create_procedure_with_steps()
      appointment_id = create_test_appointment().id

      checklist =
        AppointmentChecklist
        |> Ash.Changeset.for_create(:create, %{status: :in_progress})
        |> Ash.Changeset.force_change_attribute(:appointment_id, appointment_id)
        |> Ash.Changeset.force_change_attribute(:procedure_id, proc.id)
        |> Ash.create!()

      item =
        ChecklistItem
        |> Ash.Changeset.for_create(:create, %{
          step_number: 1,
          title: "Step 1",
          required: true
        })
        |> Ash.Changeset.force_change_attribute(:checklist_id, checklist.id)
        |> Ash.Changeset.force_change_attribute(:procedure_step_id, Enum.at(steps, 0).id)
        |> Ash.create!()

      assert item.completed == false

      {:ok, checked} =
        item
        |> Ash.Changeset.for_update(:check, %{})
        |> Ash.update()

      assert checked.completed == true
      assert checked.completed_at != nil

      # Uncheck
      {:ok, unchecked} =
        checked
        |> Ash.Changeset.for_update(:uncheck, %{})
        |> Ash.update()

      assert unchecked.completed == false
      assert unchecked.completed_at == nil
    end

    test "can add notes to a checklist item" do
      {proc, steps} = create_procedure_with_steps()
      appointment_id = create_test_appointment().id

      checklist =
        AppointmentChecklist
        |> Ash.Changeset.for_create(:create, %{status: :in_progress})
        |> Ash.Changeset.force_change_attribute(:appointment_id, appointment_id)
        |> Ash.Changeset.force_change_attribute(:procedure_id, proc.id)
        |> Ash.create!()

      item =
        ChecklistItem
        |> Ash.Changeset.for_create(:create, %{step_number: 1, title: "Step 1"})
        |> Ash.Changeset.force_change_attribute(:checklist_id, checklist.id)
        |> Ash.Changeset.force_change_attribute(:procedure_step_id, Enum.at(steps, 0).id)
        |> Ash.create!()

      {:ok, noted} =
        item
        |> Ash.Changeset.for_update(:add_note, %{notes: "Small scratch on driver door"})
        |> Ash.update()

      assert noted.notes == "Small scratch on driver door"
    end

    test "completing checklist sets completed_at" do
      {proc, _steps} = create_procedure_with_steps()
      appointment_id = create_test_appointment().id

      checklist =
        AppointmentChecklist
        |> Ash.Changeset.for_create(:create, %{status: :in_progress})
        |> Ash.Changeset.force_change_attribute(:appointment_id, appointment_id)
        |> Ash.Changeset.force_change_attribute(:procedure_id, proc.id)
        |> Ash.create!()

      {:ok, completed} =
        checklist
        |> Ash.Changeset.for_update(:complete_checklist, %{})
        |> Ash.update()

      assert completed.status == :completed
      assert completed.completed_at != nil
    end
  end
end
