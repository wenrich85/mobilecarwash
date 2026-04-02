defmodule MobileCarWash.Notifications.AppointmentReminderWorker do
  @moduledoc """
  Oban worker that sends appointment reminder emails 24 hours before the appointment.
  Runs on the :notifications queue.
  Scheduled via `scheduled_at` when the booking is created.
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
         true <- appointment.status in [:confirmed, :pending],
         {:ok, service_type} <- Ash.get(ServiceType, appointment.service_type_id),
         {:ok, customer} <- Ash.get(Customer, appointment.customer_id, authorize?: false),
         {:ok, address} <- Ash.get(Address, appointment.address_id) do
      email = Email.appointment_reminder(appointment, service_type, customer, address)

      case Mailer.deliver(email) do
        {:ok, _} ->
          Logger.info("Reminder email sent for appointment #{appointment_id}")
          :ok

        {:error, reason} ->
          Logger.error("Failed to send reminder email: #{inspect(reason)}")
          {:error, reason}
      end
    else
      false ->
        # Appointment was cancelled — skip the reminder
        Logger.info("Skipping reminder for cancelled appointment #{appointment_id}")
        :ok

      {:error, reason} ->
        Logger.error("Failed to load data for reminder email: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
