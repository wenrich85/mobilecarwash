defmodule MobileCarWash.Notifications.SMSWashCompletedWorker do
  use Oban.Worker, queue: :notifications, max_attempts: 3

  alias MobileCarWash.Scheduling.{Appointment, ServiceType}
  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Notifications.{SMS, TwilioClient}

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"appointment_id" => appointment_id}}) do
    with {:ok, appointment} <- Ash.get(Appointment, appointment_id),
         {:ok, customer} <- Ash.get(Customer, appointment.customer_id, authorize?: false),
         true <- customer.sms_opt_in && customer.phone != nil do
      {:ok, service_type} = Ash.get(ServiceType, appointment.service_type_id)

      body = SMS.wash_completed(appointment, service_type)

      case TwilioClient.send_sms(customer.phone, body) do
        {:ok, sid} ->
          Logger.info("SMS wash completed sent: #{sid}")
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
