defmodule MobileCarWash.Notifications.VerificationEmailWorker do
  @moduledoc """
  Oban worker that mints a one-shot email-verification JWT and delivers
  the confirm link via the Mailer. Enqueued from the Customer resource's
  after-action on `:register_with_password`.

  No-ops when the customer is already verified — covers the case where
  the same worker is enqueued twice (e.g. resend flow) and the second
  run arrives after verification has already happened.
  """
  use Oban.Worker, queue: :notifications, max_attempts: 3

  alias MobileCarWash.Accounts.{Customer, EmailVerification}
  alias MobileCarWash.Notifications.Email

  require Logger

  @impl true
  def perform(%Oban.Job{args: %{"customer_id" => customer_id}}) do
    with {:ok, customer} <- Ash.get(Customer, customer_id, authorize?: false),
         true <- is_nil(customer.email_verified_at) do
      token = EmailVerification.mint_token(customer)
      link = verification_link(token)

      Email.verify_email(customer, link)
      |> MobileCarWash.Mailer.deliver()

      :ok
    else
      false ->
        Logger.info("Verification email skipped: customer already verified")
        :ok

      {:error, reason} ->
        Logger.error("Failed to deliver verification email: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp verification_link(token) do
    base =
      Application.get_env(
        :mobile_car_wash,
        :external_base_url,
        "https://drivewaydetailcosa.com"
      )

    base <> "/auth/verify-email?token=" <> URI.encode(token)
  end
end
