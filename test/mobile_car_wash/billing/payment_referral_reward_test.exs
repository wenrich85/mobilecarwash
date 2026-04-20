defmodule MobileCarWash.Billing.PaymentReferralRewardTest do
  @moduledoc """
  Marketing Phase 2E / Slice 2: when a Payment transitions to
  :succeeded, the referral reward fires (once) for the paying
  customer.

  The hook lives on the Payment resource's :complete action (which
  is what the Stripe webhook + booking success flow both invoke).
  It's also fine on any :update that sets status to :succeeded,
  which we exercise here.
  """
  use MobileCarWash.DataCase, async: false

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Billing.Payment

  defp register! do
    {:ok, c} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "pay-ref-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Pay Ref",
        phone:
          "+15125556#{:rand.uniform(999) |> Integer.to_string() |> String.pad_leading(3, "0")}"
      })
      |> Ash.create()

    c
  end

  defp create_pending_payment!(customer) do
    Payment
    |> Ash.Changeset.for_create(:create, %{amount_cents: 5_000})
    |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
    |> Ash.create!(authorize?: false)
  end

  defp reload!(customer) do
    {:ok, c} = Ash.get(Customer, customer.id, authorize?: false)
    c
  end

  test "crediting the referrer when the referee's payment succeeds" do
    referrer = register!()

    {:ok, referee} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "ee-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Referee",
        phone: "+15125556000"
      })
      |> Ash.Changeset.force_change_attribute(:referred_by_id, referrer.id)
      |> Ash.create()

    payment = create_pending_payment!(referee)

    {:ok, _} =
      payment
      |> Ash.Changeset.for_update(:complete, %{
        stripe_payment_intent_id: "pi_#{System.unique_integer([:positive])}"
      })
      |> Ash.update(authorize?: false)

    assert reload!(referrer).referral_credit_cents == 1_000
    assert reload!(referee).referral_reward_issued_at != nil
  end

  test "is idempotent — two successful payments only credit once" do
    referrer = register!()

    {:ok, referee} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "ee2-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Referee 2",
        phone: "+15125556001"
      })
      |> Ash.Changeset.force_change_attribute(:referred_by_id, referrer.id)
      |> Ash.create()

    for _ <- 1..2 do
      create_pending_payment!(referee)
      |> Ash.Changeset.for_update(:complete, %{
        stripe_payment_intent_id: "pi_#{System.unique_integer([:positive])}"
      })
      |> Ash.update!(authorize?: false)
    end

    assert reload!(referrer).referral_credit_cents == 1_000
  end

  test "does nothing when the payer has no referrer" do
    non_referred = register!()
    payment = create_pending_payment!(non_referred)

    {:ok, _} =
      payment
      |> Ash.Changeset.for_update(:complete, %{
        stripe_payment_intent_id: "pi_#{System.unique_integer([:positive])}"
      })
      |> Ash.update(authorize?: false)

    assert reload!(non_referred).referral_reward_issued_at == nil
  end
end
