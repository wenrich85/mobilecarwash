defmodule MobileCarWashWeb.StripeWebhookController do
  @moduledoc """
  Handles Stripe webhook events.

  Events handled:
  - checkout.session.completed — payment successful, confirm appointment
  - checkout.session.expired — payment expired, mark as failed
  """
  use MobileCarWashWeb, :controller

  alias MobileCarWash.Billing.StripeClient
  alias MobileCarWash.Scheduling.Booking

  require Logger

  @doc """
  Receives and processes Stripe webhook events.
  The raw body must be available for signature verification.
  """
  def handle(conn, _params) do
    with {:ok, payload} <- get_raw_body(conn),
         signature <- get_stripe_signature(conn),
         {:ok, event} <- StripeClient.construct_webhook_event(payload, signature) do
      process_event(event)
      json(conn, %{status: "ok"})
    else
      {:error, :missing_signature} ->
        conn |> put_status(400) |> json(%{error: "Missing Stripe signature"})

      {:error, _reason} ->
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
      [signature] -> signature
      _ -> nil
    end
  end

  defp process_event(%{type: "checkout.session.completed"} = event) do
    session = event.data.object

    Logger.info("Stripe checkout completed: #{session.id}")

    payment_intent_id = Map.get(session, :payment_intent)
    Booking.complete_payment(session.id, payment_intent_id)
  end

  defp process_event(%{type: "checkout.session.expired"} = event) do
    session = event.data.object

    Logger.info("Stripe checkout expired: #{session.id}")

    Booking.fail_payment(session.id)
  end

  defp process_event(%{type: type}) do
    Logger.debug("Unhandled Stripe event: #{type}")
    :ok
  end
end
