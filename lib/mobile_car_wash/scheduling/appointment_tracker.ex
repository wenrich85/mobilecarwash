defmodule MobileCarWash.Scheduling.AppointmentTracker do
  @moduledoc """
  Real-time appointment progress tracking via Phoenix PubSub.

  When a technician checks off a step, this module broadcasts the progress
  to all subscribers (the customer's status page). No polling — pure push.

  Topic: "appointment:<appointment_id>"
  """

  alias Phoenix.PubSub

  @pubsub MobileCarWash.PubSub

  @doc "Subscribe to real-time updates for an appointment."
  def subscribe(appointment_id) do
    PubSub.subscribe(@pubsub, topic(appointment_id))
  end

  @doc "Broadcast that the appointment wash has started."
  def broadcast_started(appointment_id) do
    PubSub.broadcast(@pubsub, topic(appointment_id), {:appointment_update, %{
      status: :in_progress,
      event: :started,
      message: "Your wash has begun!"
    }})
  end

  @doc "Broadcast checklist step progress."
  def broadcast_progress(appointment_id, %{} = data) do
    eta_minutes = calculate_eta(data[:steps_remaining] || [])

    PubSub.broadcast(@pubsub, topic(appointment_id), {:appointment_update, %{
      status: :in_progress,
      event: :step_completed,
      current_step: data[:current_step],
      steps_done: data[:steps_done],
      steps_total: data[:steps_total],
      eta_minutes: eta_minutes,
      message: "Step #{data[:steps_done]}/#{data[:steps_total]}: #{data[:current_step]}"
    }})
  end

  @doc "Broadcast that a photo was uploaded."
  def broadcast_photo(appointment_id, photo_type) do
    PubSub.broadcast(@pubsub, topic(appointment_id), {:appointment_update, %{
      status: :in_progress,
      event: :photo_uploaded,
      photo_type: photo_type
    }})
  end

  @doc "Broadcast that the appointment is complete."
  def broadcast_completed(appointment_id) do
    PubSub.broadcast(@pubsub, topic(appointment_id), {:appointment_update, %{
      status: :completed,
      event: :completed,
      eta_minutes: 0,
      message: "Your wash is complete!"
    }})
  end

  defp topic(appointment_id), do: "appointment:#{appointment_id}"

  defp calculate_eta(remaining_steps) do
    remaining_steps
    |> Enum.reduce(0, fn step, acc -> acc + (step[:estimated_minutes] || 5) end)
  end
end
