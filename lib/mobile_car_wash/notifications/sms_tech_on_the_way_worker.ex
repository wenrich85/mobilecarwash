defmodule MobileCarWash.Notifications.SMSTechOnTheWayWorker do
  use Oban.Worker, queue: :notifications, max_attempts: 3

  alias MobileCarWash.Scheduling.Appointment
  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Operations.Technician
  alias MobileCarWash.Notifications.{SMS, TwilioClient}

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"appointment_id" => appointment_id}}) do
    with {:ok, appointment} <- Ash.get(Appointment, appointment_id),
         {:ok, customer} <- Ash.get(Customer, appointment.customer_id, authorize?: false),
         true <- customer.sms_opt_in && customer.phone != nil,
         true <- appointment.technician_id != nil,
         {:ok, technician} <- Ash.get(Technician, appointment.technician_id) do
      body = SMS.tech_on_the_way(appointment, technician)

      case TwilioClient.send_sms(customer.phone, body) do
        {:ok, sid} ->
          Logger.info("SMS tech on the way sent: #{sid}")
          :ok

        {:error, _reason} ->
          :ok
      end
    else
      false -> :ok
      {:error, _reason} -> :ok
    end
  end
end
