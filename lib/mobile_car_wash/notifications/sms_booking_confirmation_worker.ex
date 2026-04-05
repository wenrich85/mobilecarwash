defmodule MobileCarWash.Notifications.SMSBookingConfirmationWorker do
  use Oban.Worker, queue: :notifications, max_attempts: 3

  alias MobileCarWash.Scheduling.{Appointment, ServiceType}
  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Fleet.Address
  alias MobileCarWash.Notifications.{SMS, TwilioClient}

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"appointment_id" => appointment_id}}) do
    with {:ok, appointment} <- Ash.get(Appointment, appointment_id),
         {:ok, customer} <- Ash.get(Customer, appointment.customer_id, authorize?: false),
         true <- customer.sms_opt_in && customer.phone != nil do
      {:ok, service_type} = Ash.get(ServiceType, appointment.service_type_id)
      {:ok, address} = Ash.get(Address, appointment.address_id)

      body = SMS.booking_confirmation(appointment, service_type, address)

      case TwilioClient.send_sms(customer.phone, body) do
        {:ok, sid} ->
          Logger.info("SMS booking confirmation sent: #{sid}")
          :ok

        {:error, reason} ->
          Logger.error("SMS booking confirmation failed: #{inspect(reason)}")
          :ok
      end
    else
      false ->
        Logger.info("SMS skipped: customer not opted in or no phone")
        :ok

      {:error, reason} ->
        Logger.error("SMS booking confirmation data load failed: #{inspect(reason)}")
        :ok
    end
  end
end
