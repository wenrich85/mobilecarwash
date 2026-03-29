defmodule MobileCarWash.Booking.WashStateMachine do
  @moduledoc """
  Pure functional state machine for the technician wash flow.
  Manages: appointment lifecycle, checklist lifecycle, and step sequencing.
  No Phoenix/Ash dependencies — operates on plain maps.
  """

  # === Appointment-level transitions ===

  @doc "Can this appointment be started? Must be confirmed with a technician assigned."
  def can_start_wash?(%{status: :confirmed, technician_id: tid}) when not is_nil(tid), do: true
  def can_start_wash?(_), do: false

  @doc "Can this appointment be marked complete? Appointment must be in_progress and checklist completed."
  def can_complete_wash?(%{status: :in_progress}, :completed), do: true
  def can_complete_wash?(_, _), do: false

  # === Checklist item transitions ===

  @doc """
  Can this step be started? Requirements:
  - Step not already started or completed
  - No other step currently active (has started_at but not completed)
  - All previous required steps must be complete
  """
  def can_start_step?(target_item, all_items) do
    not already_started?(target_item) and
      not target_item.completed and
      not any_active?(all_items) and
      previous_required_complete?(target_item, all_items)
  end

  @doc "Can this step be completed? Must be started and not already completed."
  def can_complete_step?(%{started_at: started_at, completed: false}) when not is_nil(started_at), do: true
  def can_complete_step?(_), do: false

  @doc "Are all required items complete?"
  def all_required_complete?(items) do
    items
    |> Enum.filter(& &1.required)
    |> Enum.all?(& &1.completed)
  end

  @doc "Returns the next incomplete step, or nil if all done."
  def next_step(items) do
    Enum.find(items, &(!&1.completed))
  end

  # --- Private helpers ---

  defp already_started?(%{started_at: nil}), do: false
  defp already_started?(_), do: true

  defp any_active?(items) do
    Enum.any?(items, fn item ->
      item.started_at != nil and not item.completed
    end)
  end

  defp previous_required_complete?(target_item, all_items) do
    all_items
    |> Enum.filter(fn item ->
      item.step_number < target_item.step_number and item.required
    end)
    |> Enum.all?(& &1.completed)
  end
end
