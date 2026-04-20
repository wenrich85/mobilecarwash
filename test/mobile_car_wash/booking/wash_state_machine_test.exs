defmodule MobileCarWash.Booking.WashStateMachineTest do
  use ExUnit.Case, async: true

  alias MobileCarWash.Booking.WashStateMachine

  # --- Stub data ---

  defp confirmed_appointment(opts \\ []) do
    %{
      status: Keyword.get(opts, :status, :confirmed),
      technician_id:
        if(Keyword.has_key?(opts, :technician_id), do: opts[:technician_id], else: "tech-1"),
      service_type_id: "svc-1"
    }
  end

  defp item(opts \\ []) do
    %{
      step_number: opts[:step_number] || 1,
      required: opts[:required] != false,
      started_at: opts[:started_at],
      completed: opts[:completed] || false,
      completed_at: opts[:completed_at]
    }
  end

  # === Start Wash ===

  describe "can_start_wash?/1" do
    test "allows confirmed appointment with technician" do
      assert WashStateMachine.can_start_wash?(confirmed_appointment())
    end

    test "rejects pending appointment" do
      refute WashStateMachine.can_start_wash?(confirmed_appointment(status: :pending))
    end

    test "rejects appointment without technician" do
      refute WashStateMachine.can_start_wash?(confirmed_appointment(technician_id: nil))
    end

    test "rejects already in-progress appointment" do
      refute WashStateMachine.can_start_wash?(confirmed_appointment(status: :in_progress))
    end
  end

  # === Complete Wash ===

  describe "can_complete_wash?/2" do
    test "allows when checklist is completed" do
      appt = confirmed_appointment(status: :in_progress)
      assert WashStateMachine.can_complete_wash?(appt, :completed)
    end

    test "rejects when checklist is still in_progress" do
      appt = confirmed_appointment(status: :in_progress)
      refute WashStateMachine.can_complete_wash?(appt, :in_progress)
    end

    test "rejects when appointment is not in_progress" do
      appt = confirmed_appointment(status: :confirmed)
      refute WashStateMachine.can_complete_wash?(appt, :completed)
    end
  end

  # === Start Step ===

  describe "can_start_step?/2" do
    test "allows starting first step when none active" do
      items = [item(step_number: 1), item(step_number: 2)]
      target = Enum.at(items, 0)
      assert WashStateMachine.can_start_step?(target, items)
    end

    test "rejects starting a step when another is already active" do
      items = [
        item(step_number: 1, started_at: ~U[2026-01-01 10:00:00Z]),
        item(step_number: 2)
      ]

      target = Enum.at(items, 1)
      refute WashStateMachine.can_start_step?(target, items)
    end

    test "rejects starting an already-started step" do
      items = [item(step_number: 1, started_at: ~U[2026-01-01 10:00:00Z])]
      target = Enum.at(items, 0)
      refute WashStateMachine.can_start_step?(target, items)
    end

    test "rejects starting a completed step" do
      items = [item(step_number: 1, completed: true, completed_at: ~U[2026-01-01 10:05:00Z])]
      target = Enum.at(items, 0)
      refute WashStateMachine.can_start_step?(target, items)
    end

    test "allows starting step 2 when step 1 (required) is complete" do
      items = [
        item(step_number: 1, completed: true, completed_at: ~U[2026-01-01 10:05:00Z]),
        item(step_number: 2)
      ]

      target = Enum.at(items, 1)
      assert WashStateMachine.can_start_step?(target, items)
    end

    test "rejects starting step 2 when step 1 (required) is not complete" do
      items = [
        item(step_number: 1, required: true),
        item(step_number: 2)
      ]

      target = Enum.at(items, 1)
      refute WashStateMachine.can_start_step?(target, items)
    end

    test "allows skipping optional step" do
      items = [
        item(step_number: 1, required: false),
        item(step_number: 2)
      ]

      target = Enum.at(items, 1)
      assert WashStateMachine.can_start_step?(target, items)
    end
  end

  # === Complete Step ===

  describe "can_complete_step?/1" do
    test "allows completing an active step" do
      active = item(started_at: ~U[2026-01-01 10:00:00Z])
      assert WashStateMachine.can_complete_step?(active)
    end

    test "rejects completing a step that hasn't been started" do
      refute WashStateMachine.can_complete_step?(item())
    end

    test "rejects completing an already-completed step" do
      refute WashStateMachine.can_complete_step?(item(completed: true))
    end
  end

  # === All Required Complete ===

  describe "all_required_complete?/1" do
    test "true when all required items are done" do
      items = [
        item(step_number: 1, required: true, completed: true),
        item(step_number: 2, required: true, completed: true),
        item(step_number: 3, required: false)
      ]

      assert WashStateMachine.all_required_complete?(items)
    end

    test "false when a required item is not done" do
      items = [
        item(step_number: 1, required: true, completed: true),
        item(step_number: 2, required: true, completed: false)
      ]

      refute WashStateMachine.all_required_complete?(items)
    end
  end

  # === Next Step ===

  describe "next_step/1" do
    test "returns first incomplete step" do
      items = [
        item(step_number: 1, completed: true),
        item(step_number: 2),
        item(step_number: 3)
      ]

      assert WashStateMachine.next_step(items) == Enum.at(items, 1)
    end

    test "returns nil when all done" do
      items = [item(step_number: 1, completed: true)]
      assert WashStateMachine.next_step(items) == nil
    end
  end
end
