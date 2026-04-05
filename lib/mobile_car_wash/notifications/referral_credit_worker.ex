defmodule MobileCarWash.Notifications.ReferralCreditWorker do
  @moduledoc """
  Credits the referrer $10 when someone uses their referral code on a paid booking.
  Sends an SMS notification to the referrer.
  """
  use Oban.Worker, queue: :notifications, max_attempts: 3

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Notifications.{SMS, TwilioClient}

  require Ash.Query
  require Logger

  @credit_amount_cents 1000

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"referral_code" => code, "referee_name" => referee_name}}) do
    case Customer
         |> Ash.Query.for_read(:by_referral_code, %{referral_code: code})
         |> Ash.read!(authorize?: false) do
      [referrer] ->
        # Credit the referrer
        new_balance = (referrer.referral_credit_cents || 0) + @credit_amount_cents

        referrer
        |> Ash.Changeset.for_update(:update, %{referral_credit_cents: new_balance})
        |> Ash.update!(authorize?: false)

        Logger.info("Referral credit: #{@credit_amount_cents} cents to #{referrer.id}")

        # Send SMS if opted in
        if referrer.sms_opt_in && referrer.phone do
          body = SMS.referral_credit(referrer, referee_name)
          TwilioClient.send_sms(referrer.phone, body)
        end

        :ok

      [] ->
        Logger.warning("Referral code not found for credit: #{code}")
        :ok
    end
  end
end
