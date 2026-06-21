defmodule MobileCarWash.Scheduling.BookingPaymentTest do
  @moduledoc """
  Guards the Stripe payment-confirmation path. Regression: `complete_payment`
  and `fail_payment` looked up the Payment with `Ash.read!(Payment, action:
  ..., arguments: ...)`, but `:arguments` is not a valid `Ash.read!` option —
  arguments must go through `Ash.Query.for_read/3`. The result raised on every
  webhook, so paid appointments never got confirmed.
  """
  use MobileCarWash.DataCase, async: false

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Billing.Payment
  alias MobileCarWash.Scheduling.Booking

  defp register! do
    {:ok, c} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "bookpay-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Book Pay",
        phone:
          "+15125557#{:rand.uniform(999) |> Integer.to_string() |> String.pad_leading(3, "0")}"
      })
      |> Ash.create()

    c
  end

  defp pending_payment!(customer, session_id) do
    Payment
    |> Ash.Changeset.for_create(:create, %{
      amount_cents: 5_000,
      stripe_checkout_session_id: session_id
    })
    |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
    |> Ash.create!(authorize?: false)
  end

  test "complete_payment finds the payment by checkout session and marks it succeeded" do
    customer = register!()
    sid = "cs_test_#{System.unique_integer([:positive])}"
    pending_payment!(customer, sid)

    assert {:ok, %{payment: completed}} = Booking.complete_payment(sid, "pi_test_123")
    assert completed.status == :succeeded
    assert completed.stripe_payment_intent_id == "pi_test_123"
  end

  test "fail_payment marks the matching payment failed" do
    customer = register!()
    sid = "cs_test_#{System.unique_integer([:positive])}"
    pending_payment!(customer, sid)

    assert {:ok, failed} = Booking.fail_payment(sid)
    assert failed.status == :failed
  end

  test "complete_payment returns {:error, :payment_not_found} for an unknown session" do
    assert {:error, :payment_not_found} = Booking.complete_payment("cs_nonexistent")
  end
end
