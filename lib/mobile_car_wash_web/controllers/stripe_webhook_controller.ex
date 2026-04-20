defmodule MobileCarWashWeb.StripeWebhookController do
  @moduledoc """
  Handles Stripe webhook events.

  Events handled:
  - checkout.session.completed — payment successful, confirm appointment
  - checkout.session.expired — payment expired, mark as failed
  """
  use MobileCarWashWeb, :controller

  alias MobileCarWash.Billing.{StripeClient, SubscriptionOrchestrator}
  alias MobileCarWash.Scheduling.Booking

  require Logger

  @doc """
  Receives and processes Stripe webhook events.
  The raw body must be available for signature verification.
  """
  def handle(conn, _params) do
    with {:ok, payload} <- get_raw_body(conn),
         {:ok, signature} <- get_stripe_signature(conn),
         {:ok, event} <- StripeClient.construct_webhook_event(payload, signature) do
      process_event(event)
      json(conn, %{status: "ok"})
    else
      {:error, :missing_signature} ->
        Logger.warning("Stripe webhook: missing signature header")
        conn |> put_status(400) |> json(%{error: "Missing Stripe signature"})

      {:error, reason} ->
        Logger.warning("Stripe webhook verification failed: #{inspect(reason)}")
        conn |> put_status(400) |> json(%{error: "Invalid webhook"})
    end
  end

  defp get_raw_body(conn) do
    case conn.assigns[:raw_body] do
      body when is_binary(body) -> {:ok, body}
      _ -> {:error, :no_raw_body}
    end
  end

  defp get_stripe_signature(conn) do
    case Plug.Conn.get_req_header(conn, "stripe-signature") do
      [signature] -> {:ok, signature}
      _ -> {:error, :missing_signature}
    end
  end

  defp process_event(%{type: "checkout.session.completed"} = event) do
    session = event.data.object

    case Map.get(session, :mode) do
      "subscription" ->
        Logger.info("Stripe subscription checkout completed: #{session.id}")
        SubscriptionOrchestrator.create_from_checkout(session)

      _ ->
        Logger.info("Stripe payment checkout completed: #{session.id}")
        payment_intent_id = Map.get(session, :payment_intent)
        Booking.complete_payment(session.id, payment_intent_id)
    end
  end

  defp process_event(%{type: "checkout.session.expired"} = event) do
    session = event.data.object
    Logger.info("Stripe checkout expired: #{session.id}")
    Booking.fail_payment(session.id)
  end

  defp process_event(%{type: "customer.subscription.updated"} = event) do
    Logger.info("Stripe subscription updated: #{event.data.object.id}")
    SubscriptionOrchestrator.sync_status(event.data.object)
  end

  defp process_event(%{type: "customer.subscription.deleted"} = event) do
    Logger.info("Stripe subscription deleted: #{event.data.object.id}")
    SubscriptionOrchestrator.handle_deleted(event.data.object)
  end

  defp process_event(%{type: "invoice.payment_succeeded"} = event) do
    invoice = event.data.object

    if invoice.subscription do
      Logger.info("Stripe invoice paid for subscription: #{invoice.subscription}")
      SubscriptionOrchestrator.handle_invoice_paid(invoice)
    end
  end

  defp process_event(%{type: "invoice.payment_failed"} = event) do
    invoice = event.data.object

    if invoice.subscription do
      Logger.info("Stripe invoice failed for subscription: #{invoice.subscription}")
      SubscriptionOrchestrator.handle_invoice_failed(invoice)
    end
  end

  defp process_event(%{type: type}) do
    Logger.debug("Unhandled Stripe event: #{type}")
    :ok
  end
end
