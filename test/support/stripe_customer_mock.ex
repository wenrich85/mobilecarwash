defmodule MobileCarWash.Billing.StripeCustomerMock do
  @moduledoc """
  Test mock for `Stripe.Customer.retrieve/1`. The customer id encodes the
  scenario so tests stay deterministic without global state:
    "cus_decline..." -> default PM "pm_decline" (intent will decline)
    "cus_nopm..."    -> no default PM
    anything else    -> default PM "pm_test_default" (intent will succeed)
  """
  def retrieve("cus_nopm" <> _ = id),
    do: {:ok, %{id: id, invoice_settings: %{default_payment_method: nil}}}

  def retrieve("cus_decline" <> _ = id),
    do: {:ok, %{id: id, invoice_settings: %{default_payment_method: "pm_decline"}}}

  def retrieve(id),
    do: {:ok, %{id: id, invoice_settings: %{default_payment_method: "pm_test_default"}}}
end
