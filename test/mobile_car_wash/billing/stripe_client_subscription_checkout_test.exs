defmodule MobileCarWash.Billing.StripeClientSubscriptionCheckoutTest do
  use ExUnit.Case, async: false

  alias MobileCarWash.Billing.{StripeClient, StripeCheckoutSessionMock}

  setup do
    StripeCheckoutSessionMock.init()
    :ok
  end

  test "subscription checkout saves the default payment method for off-session reuse" do
    plan = %{id: Ecto.UUID.generate(), slug: "standard", stripe_price_id: "price_test_123"}

    {:ok, _session} = StripeClient.create_subscription_checkout(plan, "buyer@test.com")

    [{:create, _id, params}] = StripeCheckoutSessionMock.calls()

    assert params.subscription_data == %{
             payment_settings: %{save_default_payment_method: "on_subscription"}
           }
  end
end
