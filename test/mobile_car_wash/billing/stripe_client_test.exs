defmodule MobileCarWash.Billing.StripeClientTest do
  use ExUnit.Case, async: true

  alias MobileCarWash.Billing.StripeClient

  describe "create_checkout_session/3" do
    test "builds correct params structure" do
      # This test verifies the client module exists and is callable
      # In a real integration test, we'd mock Stripe.Checkout.Session

      appointment = %{
        id: "test-appt-id",
        price_cents: 5000
      }

      service_type = %{
        name: "Basic Wash",
        slug: "basic_wash"
      }

      # Stripe Checkout is globally mocked in test (config/test.exs), like the
      # other Stripe modules, so the client builds its params and returns a
      # checkout session (id + url) rather than erroring on missing keys.
      result = StripeClient.create_checkout_session(appointment, service_type, "test@example.com")

      assert {:ok, %{url: "https://checkout.stripe.com/" <> _}} = result
    end
  end
end
