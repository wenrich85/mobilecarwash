defmodule MobileCarWash.Notifications.PushAppointmentReminderWorker do
  @moduledoc """
  24-hour appointment reminder push. Enqueued alongside the SMS reminder in
  `Scheduling.Booking` after a booking is paid, scheduled 24h before the
  appointment.
  """
  use Oban.Worker, queue: :notifications, max_attempts: 3

  require Logger

  alias MobileCarWash.Scheduling.{Appointment, ServiceType}
  alias MobileCarWash.Fleet.Address
  alias MobileCarWash.Notifications.Push

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"appointment_id" => appointment_id}}) do
    with {:ok, appointment} <- Ash.get(Appointment, appointment_id, authorize?: false),
         {:ok, service_type} <-
           Ash.get(ServiceType, appointment.service_type_id, authorize?: false),
         {:ok, address} <- Ash.get(Address, appointment.address_id, authorize?: false) do
      Push.appointment_reminder(appointment, service_type, address)
      |> then(&Push.send_to_customer(appointment.customer_id, &1))
    else
      {:error, reason} ->
        Logger.error("Push appointment reminder data load failed: #{inspect(reason)}")
        :ok
    end
  end
end
