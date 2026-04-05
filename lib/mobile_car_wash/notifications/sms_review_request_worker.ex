defmodule MobileCarWash.Notifications.SMSReviewRequestWorker do
  @moduledoc """
  Sends a review request SMS 2 hours after wash completion.
  Scheduled in the Appointment :complete after_action callback.
  """
  use Oban.Worker, queue: :notifications, max_attempts: 3

  alias MobileCarWash.Scheduling.Appointment
  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Notifications.{SMS, TwilioClient}

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"appointment_id" => appointment_id}}) do
    with {:ok, appointment} <- Ash.get(Appointment, appointment_id),
         {:ok, customer} <- Ash.get(Customer, appointment.customer_id, authorize?: false),
         true <- customer.sms_opt_in && customer.phone != nil do
      body = SMS.review_request(customer)

      case TwilioClient.send_sms(customer.phone, body) do
        {:ok, sid} ->
          Logger.info("SMS review request sent: #{sid}")
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
