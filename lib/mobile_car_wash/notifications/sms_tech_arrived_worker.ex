defmodule MobileCarWash.Notifications.SMSTechArrivedWorker do
  @moduledoc """
  SMS worker that fires when the appointment transitions to :on_site.
  """
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
         true <- not is_nil(appointment.technician_id),
         {:ok, technician} <- Ash.get(Technician, appointment.technician_id) do
      body = SMS.tech_arrived(appointment, technician)

      case TwilioClient.send_sms(customer.phone, body) do
        {:ok, sid} ->
          Logger.info("SMS tech arrived sent: #{sid}")
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
