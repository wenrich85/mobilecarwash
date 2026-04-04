defmodule MobileCarWash.Scheduling.AppointmentTracker do
  @moduledoc """
  Real-time appointment progress tracking via Phoenix PubSub.
  Broadcasts step-level detail so customers see exactly what's happening.
  """

  alias Phoenix.PubSub

  @pubsub MobileCarWash.PubSub

  def subscribe(appointment_id) do
    PubSub.subscribe(@pubsub, topic(appointment_id))
  end

  @doc "Subscribe to all new appointment notifications (for dispatch dashboard)."
  def subscribe_to_new_appointments do
    PubSub.subscribe(@pubsub, "appointments:new")
  end

  @doc "Broadcast that a new appointment was created."
  def broadcast_new_appointment(appointment_id) do
    PubSub.broadcast(@pubsub, "appointments:new", {:new_appointment, appointment_id})
  end

  @doc "Subscribe to tech appointment requests (for dispatch)."
  def subscribe_to_tech_requests do
    PubSub.subscribe(@pubsub, "appointments:tech_requests")
  end

  @doc "Subscribe to appointments assigned to a specific technician (for tech dashboard)."
  def subscribe_to_tech_assignments(technician_id) do
    PubSub.subscribe(@pubsub, "tech:#{technician_id}:assigned")
  end

  @doc "Broadcast that an appointment was assigned to a technician."
  def broadcast_assigned_to_tech(_appointment_id, nil), do: :ok

  def broadcast_assigned_to_tech(appointment_id, technician_id) do
    PubSub.broadcast(@pubsub, "tech:#{technician_id}:assigned", {:appointment_assigned, appointment_id})
  end

  @doc "Broadcast that a tech is requesting an appointment."
  def broadcast_tech_request(appointment_id, technician_id, technician_name) do
    PubSub.broadcast(@pubsub, "appointments:tech_requests", {:tech_request, %{
      appointment_id: appointment_id,
      technician_id: technician_id,
      technician_name: technician_name
    }})
  end

  @doc "Broadcast that an appointment's technician assignment or confirmation status changed."
  def broadcast_assignment_changed(appointment_id) do
    PubSub.broadcast(@pubsub, topic(appointment_id), {:appointment_update, %{
      appointment_id: appointment_id,
      event: :assignment_changed
    }})
  end

  def broadcast_started(appointment_id) do
    PubSub.broadcast(@pubsub, topic(appointment_id), {:appointment_update, %{
      appointment_id: appointment_id,
      status: :in_progress,
      event: :started,
      message: "Your wash has begun!"
    }})
  end

  @doc """
  Broadcasts detailed step progress including all items for the customer view.
  `items` should be the full list of checklist items with their current state.
  """
  def broadcast_step_progress(appointment_id, %{} = data) do
    remaining_minutes = calculate_remaining_minutes(data[:items] || [])

    PubSub.broadcast(@pubsub, topic(appointment_id), {:appointment_update, %{
      appointment_id: appointment_id,
      status: :in_progress,
      event: :step_update,
      current_step: data[:current_step],
      steps_done: data[:steps_done],
      steps_total: data[:steps_total],
      eta_minutes: remaining_minutes,
      items: sanitize_items(data[:items] || []),
      message: "Step #{data[:steps_done]}/#{data[:steps_total]}: #{data[:current_step]}"
    }})
  end

  def broadcast_photo(appointment_id, photo_type) do
    PubSub.broadcast(@pubsub, topic(appointment_id), {:appointment_update, %{
      appointment_id: appointment_id,
      status: :in_progress,
      event: :photo_uploaded,
      photo_type: photo_type
    }})
  end

  def broadcast_completed(appointment_id) do
    PubSub.broadcast(@pubsub, topic(appointment_id), {:appointment_update, %{
      appointment_id: appointment_id,
      status: :completed,
      event: :completed,
      eta_minutes: 0,
      message: "Your wash is complete!"
    }})
  end

  defp topic(appointment_id), do: "appointment:#{appointment_id}"

  defp calculate_remaining_minutes(items) do
    items
    |> Enum.reject(& &1.completed)
    |> Enum.reduce(0, fn item, acc -> acc + (item.estimated_minutes || 5) end)
  end

  # Strip items to only what the customer needs (no internal IDs)
  defp sanitize_items(items) do
    Enum.map(items, fn item ->
      %{
        step_number: item.step_number,
        title: item.title,
        completed: item.completed,
        estimated_minutes: item.estimated_minutes,
        started_at: item.started_at,
        actual_seconds: item.actual_seconds
      }
    end)
  end
end
