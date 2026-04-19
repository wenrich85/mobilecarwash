defmodule MobileCarWash.Notifications.PushBookingCancelledWorker do
  @moduledoc """
  Booking-cancelled push. Enqueued from the appointment's `:cancel`
  after-action hook, alongside the SMS and email equivalents.
  """
  use Oban.Worker, queue: :notifications, max_attempts: 3

  require Logger

  alias MobileCarWash.Scheduling.{Appointment, ServiceType}
  alias MobileCarWash.Notifications.Push

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"appointment_id" => appointment_id}}) do
    with {:ok, appointment} <- Ash.get(Appointment, appointment_id, authorize?: false),
         {:ok, service_type} <-
           Ash.get(ServiceType, appointment.service_type_id, authorize?: false) do
      Push.booking_cancelled(appointment, service_type)
      |> then(&Push.send_to_customer(appointment.customer_id, &1))
    else
      {:error, reason} ->
        Logger.error("Push booking_cancelled data load failed: #{inspect(reason)}")
        :ok
    end
  end
end
