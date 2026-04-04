defmodule MobileCarWash.Billing.SubscriptionOrchestrator do
  @moduledoc """
  Coordinates subscription lifecycle events triggered by Stripe webhooks.
  Stripe is the source of truth — this module mirrors state into the local DB.
  """

  alias MobileCarWash.Billing.{Subscription, SubscriptionPlan, SubscriptionUsage, Payment}
  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.CashFlow.Engine, as: CashFlowEngine

  require Ash.Query
  require Logger

  @doc """
  Called from webhook: checkout.session.completed (mode=subscription).
  Creates local Subscription record mirroring what Stripe created.
  """
  def create_from_checkout(stripe_session) do
    stripe_subscription_id = Map.get(stripe_session, :subscription)
    stripe_customer_id = Map.get(stripe_session, :customer)
    plan_id = get_in(stripe_session, [:metadata, "plan_id"]) || Map.get(stripe_session.metadata, :plan_id)

    with {:ok, plan} <- Ash.get(SubscriptionPlan, plan_id),
         {:ok, customer} <- find_and_link_customer(stripe_customer_id, stripe_session) do

      today = Date.utc_today()
      period_end = Date.add(today, 30)

      {:ok, subscription} =
        Subscription
        |> Ash.Changeset.for_create(:create, %{
          stripe_subscription_id: stripe_subscription_id,
          status: :active,
          current_period_start: today,
          current_period_end: period_end
        })
        |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
        |> Ash.Changeset.force_change_attribute(:plan_id, plan.id)
        |> Ash.create()

      # Create initial usage record
      create_usage_record(subscription, today, period_end)

      # Send welcome email
      %{subscription_id: subscription.id, event: "created"}
      |> MobileCarWash.Notifications.SubscriptionNotificationWorker.new(queue: :notifications)
      |> Oban.insert()

      # Record initial subscription payment in cash flow ledger
      CashFlowEngine.record_deposit(plan.price_cents, "New subscription — #{plan.name}")

      {:ok, subscription}
    end
  end

  @doc "Called from webhook: customer.subscription.updated"
  def sync_status(stripe_subscription) do
    case find_subscription(stripe_subscription.id) do
      {:ok, subscription} ->
        new_status = map_stripe_status(stripe_subscription.status)

        subscription
        |> Ash.Changeset.for_update(:update, %{status: new_status})
        |> Ash.update()

      error ->
        error
    end
  end

  @doc "Called from webhook: customer.subscription.deleted"
  def handle_deleted(stripe_subscription) do
    case find_subscription(stripe_subscription.id) do
      {:ok, subscription} ->
        {:ok, cancelled_subscription} =
          subscription
          |> Ash.Changeset.for_update(:cancel, %{})
          |> Ash.update()

        # Send cancellation email
        %{subscription_id: cancelled_subscription.id, event: "cancelled"}
        |> MobileCarWash.Notifications.SubscriptionNotificationWorker.new(queue: :notifications)
        |> Oban.insert()

        {:ok, cancelled_subscription}

      error ->
        error
    end
  end

  @doc "Called from webhook: invoice.payment_succeeded (for subscription renewals)"
  def handle_invoice_paid(stripe_invoice) do
    sub_id = Map.get(stripe_invoice, :subscription)
    if is_nil(sub_id), do: {:error, :no_subscription}, else: do_handle_invoice_paid(sub_id, stripe_invoice)
  end

  defp do_handle_invoice_paid(stripe_sub_id, stripe_invoice) do
    case find_subscription(stripe_sub_id) do
      {:ok, subscription} ->
        period_start = unix_to_date(stripe_invoice.period_start)
        period_end = unix_to_date(stripe_invoice.period_end)

        {:ok, subscription} =
          subscription
          |> Ash.Changeset.for_update(:update, %{
            status: :active,
            current_period_start: period_start,
            current_period_end: period_end
          })
          |> Ash.update()

        create_usage_record(subscription, period_start, period_end)

        # Create a Payment record for this renewal and sync to accounting + cash flow
        amount_cents = Map.get(stripe_invoice, :amount_paid, 0)
        stripe_intent = Map.get(stripe_invoice, :payment_intent)
        record_subscription_renewal(subscription, amount_cents, stripe_intent)

        {:ok, subscription}

      error ->
        error
    end
  end

  defp record_subscription_renewal(subscription, amount_cents, stripe_payment_intent_id)
       when is_integer(amount_cents) and amount_cents > 0 do
    plan = Ash.get!(SubscriptionPlan, subscription.plan_id)

    # Create a Payment record so the renewal is traceable
    {:ok, payment} =
      Payment
      |> Ash.Changeset.for_create(:create, %{
        amount_cents: amount_cents,
        status: :succeeded,
        paid_at: DateTime.utc_now(),
        stripe_payment_intent_id: if(is_binary(stripe_payment_intent_id), do: stripe_payment_intent_id)
      })
      |> Ash.Changeset.force_change_attribute(:customer_id, subscription.customer_id)
      |> Ash.Changeset.force_change_attribute(:subscription_id, subscription.id)
      |> Ash.create()

    # Sync to external accounting (ZohoBooks/QB)
    %{payment_id: payment.id}
    |> MobileCarWash.Accounting.SyncWorker.new(queue: :billing)
    |> Oban.insert()

    # Record in local cash flow ledger
    CashFlowEngine.record_deposit(amount_cents, "Subscription renewal — #{plan.name}")
  end

  defp record_subscription_renewal(_subscription, _amount, _intent), do: :ok

  @doc "Called from webhook: invoice.payment_failed"
  def handle_invoice_failed(stripe_invoice) do
    sub_id = Map.get(stripe_invoice, :subscription)
    if is_nil(sub_id), do: {:error, :no_subscription}, else: do_handle_invoice_failed(sub_id)
  end

  defp do_handle_invoice_failed(stripe_sub_id) do
    case find_subscription(stripe_sub_id) do
      {:ok, subscription} ->
        subscription
        |> Ash.Changeset.for_update(:mark_past_due, %{})
        |> Ash.update()

      error ->
        error
    end
  end

  # --- Private ---

  defp find_subscription(stripe_id) do
    results =
      Subscription
      |> Ash.Query.filter(stripe_subscription_id == ^stripe_id)
      |> Ash.read!()

    case results do
      [sub | _] -> {:ok, sub}
      [] -> {:error, :subscription_not_found}
    end
  end

  defp find_and_link_customer(stripe_customer_id, stripe_session) do
    email = Map.get(stripe_session, :customer_email) || Map.get(stripe_session, :customer_details, %{}) |> Map.get(:email)

    customer =
      if email do
        Customer
        |> Ash.Query.filter(email == ^email)
        |> Ash.read!()
        |> List.first()
      end

    case customer do
      nil ->
        Logger.error("No customer found for stripe session: #{inspect(stripe_session.id)}")
        {:error, :customer_not_found}

      customer ->
        # Link stripe_customer_id if not already set
        if is_nil(customer.stripe_customer_id) do
          customer
          |> Ash.Changeset.for_update(:update, %{stripe_customer_id: stripe_customer_id})
          |> Ash.update()
        else
          {:ok, customer}
        end
    end
  end

  defp map_stripe_status("active"), do: :active
  defp map_stripe_status("past_due"), do: :past_due
  defp map_stripe_status("canceled"), do: :cancelled
  defp map_stripe_status("paused"), do: :paused
  defp map_stripe_status(_), do: :paused

  defp unix_to_date(unix) when is_integer(unix) do
    DateTime.from_unix!(unix) |> DateTime.to_date()
  end

  defp unix_to_date(_), do: Date.utc_today()

  defp create_usage_record(subscription, period_start, period_end) do
    SubscriptionUsage
    |> Ash.Changeset.for_create(:create, %{
      period_start: period_start,
      period_end: period_end
    })
    |> Ash.Changeset.force_change_attribute(:subscription_id, subscription.id)
    |> Ash.create()
  end
end
