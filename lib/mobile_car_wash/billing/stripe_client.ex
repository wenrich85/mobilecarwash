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
              description: "Driveway Detail Co — #{service_type.name}"
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
  Creates a Stripe Checkout Session for a recurring subscription.
  Uses the plan's `stripe_price_id` in subscription mode.
  """
  def create_subscription_checkout(plan, customer_email, stripe_customer_id \\ nil) do
    base_url = Application.get_env(:mobile_car_wash, :base_url, "http://localhost:4000")

    params = %{
      mode: "subscription",
      line_items: [%{price: plan.stripe_price_id, quantity: 1}],
      metadata: %{plan_id: plan.id, plan_slug: plan.slug},
      success_url: "#{base_url}/subscribe/success?session_id={CHECKOUT_SESSION_ID}",
      cancel_url: "#{base_url}/subscribe/cancel"
    }

    params =
      if stripe_customer_id do
        Map.put(params, :customer, stripe_customer_id)
      else
        Map.put(params, :customer_email, customer_email)
      end

    case stripe_module().create(params) do
      {:ok, session} -> {:ok, session}
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Creates a Stripe Billing Portal session for the customer to manage payment methods.
  """
  def create_billing_portal_session(stripe_customer_id, return_url) do
    billing_portal_module().create(%{
      customer: stripe_customer_id,
      return_url: return_url
    })
  end

  @doc """
  Verifies a Stripe webhook signature and parses the event.
  """
  def construct_webhook_event(payload, signature) do
    secret = Application.get_env(:mobile_car_wash, :stripe_webhook_secret)

    Stripe.Webhook.construct_event(payload, signature, secret)
  end

  @doc """
  Creates a Stripe Product. Params: `%{name:, description: (optional), metadata: (optional)}`.
  """
  def create_product(params) do
    product_module().create(params)
  end

  @doc """
  Updates a Stripe Product in place by id.
  """
  def update_product(product_id, params) do
    product_module().update(product_id, params)
  end

  @doc """
  Archives a Stripe Product (sets active: false). Stripe doesn't hard-delete
  products that have been used in checkouts or subscriptions.
  """
  def archive_product(product_id) do
    product_module().update(product_id, %{active: false})
  end

  @doc """
  Creates a Stripe Price. For recurring prices, include
  `recurring: %{interval: "month"}` in params.
  Prices are immutable on amount — to change a price, archive and recreate.
  """
  def create_price(params) do
    price_module().create(params)
  end

  @doc """
  Archives a Stripe Price (sets active: false). Existing subscriptions on
  the archived price keep working; only new checkouts are blocked from using it.
  """
  def archive_price(price_id) do
    price_module().update(price_id, %{active: false})
  end

  @doc """
  Creates a PaymentIntent for the native mobile Payment Sheet flow. The
  mobile SDK completes the payment client-side using the returned
  client_secret, and our Stripe webhook confirms the appointment.
  """
  def create_payment_intent(amount_cents, customer_email, metadata \\ %{}) do
    params = %{
      amount: amount_cents,
      currency: "usd",
      automatic_payment_methods: %{enabled: true},
      receipt_email: customer_email,
      metadata: metadata
    }

    payment_intent_module().create(params)
  end

  # Allow mocking Stripe in tests
  defp stripe_module do
    Application.get_env(:mobile_car_wash, :stripe_checkout_module, Stripe.Checkout.Session)
  end

  defp billing_portal_module do
    Application.get_env(:mobile_car_wash, :stripe_billing_portal_module, Stripe.BillingPortal.Session)
  end

  defp product_module do
    Application.get_env(:mobile_car_wash, :stripe_product_module, Stripe.Product)
  end

  defp price_module do
    Application.get_env(:mobile_car_wash, :stripe_price_module, Stripe.Price)
  end

  defp payment_intent_module do
    Application.get_env(:mobile_car_wash, :stripe_payment_intent_module, Stripe.PaymentIntent)
  end
end
