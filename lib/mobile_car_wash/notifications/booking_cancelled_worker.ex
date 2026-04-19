defmodule MobileCarWash.Notifications.BookingCancelledWorker do
  @moduledoc """
  Booking-cancelled email. Enqueued from the appointment's `:cancel`
  after-action hook, alongside the SMS and push equivalents.
  """
  use Oban.Worker, queue: :notifications, max_attempts: 3

  alias MobileCarWash.Notifications.Email
  alias MobileCarWash.Scheduling.{Appointment, ServiceType}
  alias MobileCarWash.Accounts.Customer

  require Logger

  @impl true
  def perform(%Oban.Job{args: %{"appointment_id" => appointment_id}}) do
    with {:ok, appointment} <- Ash.get(Appointment, appointment_id),
         {:ok, customer} <- Ash.get(Customer, appointment.customer_id, authorize?: false),
         {:ok, service_type} <- Ash.get(ServiceType, appointment.service_type_id) do
      Email.booking_cancelled(customer, appointment, service_type.name)
      |> MobileCarWash.Mailer.deliver()

      :ok
    else
      {:error, reason} ->
        Logger.error("Failed to send booking cancelled email: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
