defmodule MobileCarWash.Notifications.SubscriptionNotificationWorker do
  @moduledoc "Sends subscription lifecycle emails (created, cancelled)."
  use Oban.Worker, queue: :notifications, max_attempts: 3

  alias MobileCarWash.Notifications.Email
  alias MobileCarWash.Billing.{Subscription, SubscriptionPlan}
  alias MobileCarWash.Accounts.Customer

  require Logger

  @impl true
  def perform(%Oban.Job{args: %{"subscription_id" => sub_id, "event" => event}}) do
    with {:ok, sub} <- Ash.get(Subscription, sub_id),
         {:ok, customer} <- Ash.get(Customer, sub.customer_id, authorize?: false),
         {:ok, plan} <- Ash.get(SubscriptionPlan, sub.plan_id) do
      case event do
        "created" ->
          Email.subscription_created(customer, plan)
          |> MobileCarWash.Mailer.deliver()

        "cancelled" ->
          Email.subscription_cancelled(customer, plan)
          |> MobileCarWash.Mailer.deliver()

        _ ->
          Logger.warning("Unknown subscription event: #{event}")
      end

      :ok
    else
      {:error, reason} ->
        Logger.error("Failed to send subscription email: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
