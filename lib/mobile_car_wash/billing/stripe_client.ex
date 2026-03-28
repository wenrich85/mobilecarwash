defmodule MobileCarWash.Billing.StripeClient do
  @moduledoc """
  Wraps Stripe API calls for the mobile car wash application.

  Uses Stripe Checkout Sessions for one-time payments.
  Designed to be mockable in tests via application config.
  """

  @doc """
  Creates a Stripe Checkout Session for a one-time appointment payment.

  Returns `{:ok, checkout_session}` or `{:error, reason}`.
  """
  def create_checkout_session(appointment, service_type, customer_email) do
    base_url = Application.get_env(:mobile_car_wash, :base_url, "http://localhost:4000")

    params = %{
      mode: "payment",
      customer_email: customer_email,
      line_items: [
        %{
          price_data: %{
            currency: "usd",
            product_data: %{
              name: service_type.name,
              description: "Mobile car wash — #{service_type.name}"
            },
            unit_amount: appointment.price_cents
          },
          quantity: 1
        }
      ],
      metadata: %{
        appointment_id: appointment.id,
        service_type: service_type.slug
      },
      success_url: "#{base_url}/book/success?session_id={CHECKOUT_SESSION_ID}",
      cancel_url: "#{base_url}/book/cancel?appointment_id=#{appointment.id}"
    }

    case stripe_module().create(params) do
      {:ok, session} -> {:ok, session}
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Retrieves a Stripe Checkout Session by ID.
  """
  def get_checkout_session(session_id) do
    stripe_module().retrieve(session_id)
  end

  @doc """
  Verifies a Stripe webhook signature and parses the event.
  """
  def construct_webhook_event(payload, signature) do
    secret = Application.get_env(:mobile_car_wash, :stripe_webhook_secret)

    Stripe.Webhook.construct_event(payload, signature, secret)
  end

  # Allow mocking Stripe in tests
  defp stripe_module do
    Application.get_env(:mobile_car_wash, :stripe_checkout_module, Stripe.Checkout.Session)
  end
end
