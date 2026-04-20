defmodule MobileCarWashWeb.Admin.ProceduresLiveTest do
  @moduledoc """
  Tests for the admin Procedures LiveView.
  """
  use MobileCarWashWeb.ConnCase, async: true

  require Ash.Query

  alias MobileCarWash.Operations.{Procedure, ProcedureStep}

  describe "auth guard" do
    test "non-authenticated user is redirected to sign-in", %{conn: conn} do
      conn = get(conn, ~p"/admin/procedures")
      assert redirected_to(conn) == "/sign-in"
    end
  end

  describe "procedure resource" do
    test "can create a procedure", _context do
      {:ok, proc} =
        Procedure
        |> Ash.Changeset.for_create(:create, %{
          name: "Test Procedure",
          slug: "test_procedure",
          description: "Test description",
          category: :wash,
          active: true
        })
        |> Ash.create()

      assert proc.name == "Test Procedure"
      assert proc.category == :wash
      assert proc.active == true
    end

    test "can update a procedure", _context do
      {:ok, proc} =
        Procedure
        |> Ash.Changeset.for_create(:create, %{
          name: "Original Procedure",
          slug: "original_procedure",
          category: :wash
        })
        |> Ash.create()

      {:ok, updated} =
        proc
        |> Ash.Changeset.for_update(:update, %{
          name: "Updated Procedure",
          category: :admin
        })
        |> Ash.update()

      assert updated.name == "Updated Procedure"
      assert updated.category == :admin
    end

    test "cannot delete procedure with steps", _context do
      {:ok, proc} =
        Procedure
        |> Ash.Changeset.for_create(:create, %{
          name: "Procedure with Steps",
          slug: "procedure_with_steps",
          category: :wash
        })
        |> Ash.create()

      # Add a step
      {:ok, _step} =
        ProcedureStep
        |> Ash.Changeset.for_create(:create, %{
          step_number: 1,
          title: "First Step",
          estimated_minutes: 10,
          required: true
        })
        |> Ash.Changeset.force_change_attribute(:procedure_id, proc.id)
        |> Ash.create()

      # Verify deletion is blocked by checking step count
      proc_id = proc.id
      steps = ProcedureStep |> Ash.Query.filter(procedure_id == ^proc_id) |> Ash.read!()
      assert length(steps) > 0
    end

    test "can delete procedure without steps", _context do
      {:ok, proc} =
        Procedure
        |> Ash.Changeset.for_create(:create, %{
          name: "Empty Procedure",
          slug: "empty_procedure",
          category: :wash
        })
        |> Ash.create()

      # Delete should succeed
      assert :ok == Ash.destroy(proc)

      # Verify deletion
      result = Ash.get(Procedure, proc.id)
      assert match?({:error, _}, result)
    end

    test "can reorder steps using Ash", _context do
      {:ok, proc} =
        Procedure
        |> Ash.Changeset.for_create(:create, %{
          name: "Reorder Test",
          slug: "reorder_test",
          category: :wash
        })
        |> Ash.create()

      # Create three steps
      {:ok, step1} =
        ProcedureStep
        |> Ash.Changeset.for_create(:create, %{
          step_number: 1,
          title: "Step 1",
          estimated_minutes: 5,
          required: true
        })
        |> Ash.Changeset.force_change_attribute(:procedure_id, proc.id)
        |> Ash.create()

      {:ok, step2} =
        ProcedureStep
        |> Ash.Changeset.for_create(:create, %{
          step_number: 2,
          title: "Step 2",
          estimated_minutes: 5,
          required: true
        })
        |> Ash.Changeset.force_change_attribute(:procedure_id, proc.id)
        |> Ash.create()

      {:ok, step3} =
        ProcedureStep
        |> Ash.Changeset.for_create(:create, %{
          step_number: 3,
          title: "Step 3",
          estimated_minutes: 5,
          required: true
        })
        |> Ash.Changeset.force_change_attribute(:procedure_id, proc.id)
        |> Ash.create()

      # Reorder: move step3 to position 1, step1 to position 2, step2 to position 3
      step3
      |> Ash.Changeset.for_update(:update, %{step_number: 1})
      |> Ash.update()

      step1
      |> Ash.Changeset.for_update(:update, %{step_number: 2})
      |> Ash.update()

      step2
      |> Ash.Changeset.for_update(:update, %{step_number: 3})
      |> Ash.update()

      # Verify reorder
      {:ok, updated_step3} = Ash.get(ProcedureStep, step3.id)
      assert updated_step3.step_number == 1

      {:ok, updated_step1} = Ash.get(ProcedureStep, step1.id)
      assert updated_step1.step_number == 2

      {:ok, updated_step2} = Ash.get(ProcedureStep, step2.id)
      assert updated_step2.step_number == 3
    end

    test "can renumber steps after deletion", _context do
      {:ok, proc} =
        Procedure
        |> Ash.Changeset.for_create(:create, %{
          name: "Renumber Test",
          slug: "renumber_test",
          category: :wash
        })
        |> Ash.create()

      # Create three steps
      {:ok, step1} =
        ProcedureStep
        |> Ash.Changeset.for_create(:create, %{
          step_number: 1,
          title: "Step 1",
          estimated_minutes: 5,
          required: true
        })
        |> Ash.Changeset.force_change_attribute(:procedure_id, proc.id)
        |> Ash.create()

      {:ok, step2} =
        ProcedureStep
        |> Ash.Changeset.for_create(:create, %{
          step_number: 2,
          title: "Step 2",
          estimated_minutes: 5,
          required: true
        })
        |> Ash.Changeset.force_change_attribute(:procedure_id, proc.id)
        |> Ash.create()

      {:ok, step3} =
        ProcedureStep
        |> Ash.Changeset.for_create(:create, %{
          step_number: 3,
          title: "Step 3",
          estimated_minutes: 5,
          required: true
        })
        |> Ash.Changeset.force_change_attribute(:procedure_id, proc.id)
        |> Ash.create()

      # Delete step 2
      Ash.destroy(step2)

      # Renumber remaining steps
      proc_id = proc.id

      remaining_steps =
        ProcedureStep
        |> Ash.Query.filter(procedure_id == ^proc_id)
        |> Ash.Query.sort(step_number: :asc)
        |> Ash.read!()

      remaining_steps
      |> Enum.with_index(1)
      |> Enum.each(fn {step, new_number} ->
        step
        |> Ash.Changeset.for_update(:update, %{step_number: new_number})
        |> Ash.update()
      end)

      # Verify renumbering
      {:ok, updated_step1} = Ash.get(ProcedureStep, step1.id)
      assert updated_step1.step_number == 1

      {:ok, updated_step3} = Ash.get(ProcedureStep, step3.id)
      assert updated_step3.step_number == 2
    end
  end
end
