defmodule MobileCarWash.Notifications.BookingConfirmationWorker do
  @moduledoc """
  Oban worker that sends booking confirmation emails after successful payment.
  Runs on the :notifications queue.
  """
  use Oban.Worker, queue: :notifications, max_attempts: 3

  alias MobileCarWash.Scheduling.Appointment
  alias MobileCarWash.Scheduling.ServiceType
  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Fleet.Address
  alias MobileCarWash.Notifications.Email
  alias MobileCarWash.Mailer

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"appointment_id" => appointment_id}}) do
    with {:ok, appointment} <- Ash.get(Appointment, appointment_id),
         {:ok, service_type} <- Ash.get(ServiceType, appointment.service_type_id),
         {:ok, customer} <- Ash.get(Customer, appointment.customer_id, authorize?: false),
         {:ok, address} <- Ash.get(Address, appointment.address_id) do
      email = Email.booking_confirmation(appointment, service_type, customer, address)

      case Mailer.deliver(email) do
        {:ok, _} ->
          Logger.info("Booking confirmation email sent for appointment #{appointment_id}")
          :ok

        {:error, reason} ->
          Logger.error("Failed to send confirmation email: #{inspect(reason)}")
          {:error, reason}
      end
    else
      {:error, reason} ->
        Logger.error("Failed to load data for confirmation email: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
