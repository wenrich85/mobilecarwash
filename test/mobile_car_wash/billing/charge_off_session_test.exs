defmodule MobileCarWash.Billing.ChargeOffSessionTest do
  use ExUnit.Case, async: false

  alias MobileCarWash.Billing.StripeClient

  test "succeeds when the customer has a default payment method" do
    assert {:ok, %{status: "succeeded", amount: 2_400}} =
             StripeClient.charge_off_session("cus_test_123", 2_400, %{kind: "appointment_addons"})
  end

  test "returns :card_declined when the saved card declines" do
    assert {:error, :card_declined} =
             StripeClient.charge_off_session("cus_decline_123", 2_400)
  end

  test "returns :no_payment_method when the customer has none" do
    assert {:error, :no_payment_method} =
             StripeClient.charge_off_session("cus_nopm_123", 2_400)
  end

  test "returns :no_payment_method for a nil customer id" do
    assert {:error, :no_payment_method} = StripeClient.charge_off_session(nil, 2_400)
  end
end
