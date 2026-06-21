defmodule MobileCarWashWeb.StripeWebhookControllerTest do
  @moduledoc """
  Verifies the Stripe webhook endpoint can validate signatures. This guards a
  regression where `Plug.Parsers` consumed the request body before the raw body
  was captured, so signature verification always ran over empty bytes and every
  webhook 400'd (payments never confirmed appointments).
  """
  use MobileCarWashWeb.ConnCase, async: false

  @secret "whsec_test_secret_for_webhook_controller"

  setup do
    prev = Application.get_env(:mobile_car_wash, :stripe_webhook_secret)
    Application.put_env(:mobile_car_wash, :stripe_webhook_secret, @secret)
    on_exit(fn -> Application.put_env(:mobile_car_wash, :stripe_webhook_secret, prev) end)
    :ok
  end

  # Build a Stripe-style signature header (t=<ts>,v1=<hmac>) over the exact
  # payload bytes, the same scheme Stripe.Webhook.construct_event verifies.
  defp sign(payload, secret \\ @secret) do
    ts = System.system_time(:second)

    signature =
      :crypto.mac(:hmac, :sha256, secret, "#{ts}.#{payload}") |> Base.encode16(case: :lower)

    "t=#{ts},v1=#{signature}"
  end

  defp post_webhook(conn, payload, signature) do
    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header("stripe-signature", signature)
    |> post("/webhooks/stripe", payload)
  end

  test "a correctly-signed webhook verifies and returns 200", %{conn: conn} do
    # Unhandled event type → controller's catch-all returns :ok with no DB work,
    # so this isolates signature verification.
    payload =
      Jason.encode!(%{
        "id" => "evt_test_signed",
        "object" => "event",
        "type" => "payment_intent.created",
        "data" => %{"object" => %{"id" => "pi_test"}}
      })

    conn = post_webhook(conn, payload, sign(payload))

    assert json_response(conn, 200) == %{"status" => "ok"}
  end

  test "a webhook with a bad signature is rejected with 400", %{conn: conn} do
    payload =
      Jason.encode!(%{
        "id" => "evt_bad",
        "object" => "event",
        "type" => "payment_intent.created",
        "data" => %{"object" => %{}}
      })

    conn = post_webhook(conn, payload, "t=1,v1=deadbeef")

    assert response(conn, 400)
  end
end
