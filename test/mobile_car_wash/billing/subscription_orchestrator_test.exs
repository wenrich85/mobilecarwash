defmodule MobileCarWash.Billing.SubscriptionOrchestratorTest do
  @moduledoc """
  Guards subscription creation from the Stripe checkout webhook. Regression:
  `create_from_checkout` used `get_in(stripe_session, [:metadata, ...])` on a
  `%Stripe.Checkout.Session{}` struct, which raised (structs don't implement
  the Access behaviour) — so paid subscriptions never created a local
  Subscription row. The test passes a real struct so a plain-map fixture
  (maps DO implement Access) can't mask the bug.
  """
  use MobileCarWash.DataCase, async: false

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Billing.{Subscription, SubscriptionOrchestrator, SubscriptionPlan}
  alias MobileCarWash.CashFlow.Account

  require Ash.Query

  # create_from_checkout records the subscription deposit in the cash-flow
  # ledger, which requires the 5 accounts that seeds.exs creates in dev/prod
  # but the test sandbox lacks. Seed them here.
  setup do
    for {type, name} <- [
          {:expense, "Expense Account"},
          {:tax, "Tax Account"},
          {:business_savings, "Business Savings"},
          {:investment, "Investment Account"},
          {:personal_salary, "Personal Salary"}
        ] do
      Account
      |> Ash.Changeset.for_create(:create, %{account_type: type, name: name, color: :blue})
      |> Ash.create!(authorize?: false)
    end

    :ok
  end

  defp register!(email) do
    {:ok, c} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: email,
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Sub Tester",
        phone:
          "+15125558#{:rand.uniform(999) |> Integer.to_string() |> String.pad_leading(3, "0")}"
      })
      |> Ash.create()

    c
  end

  defp plan! do
    SubscriptionPlan
    |> Ash.Changeset.for_create(:create, %{
      name: "Test Plan #{System.unique_integer([:positive])}",
      slug: "test-plan-#{System.unique_integer([:positive])}",
      price_cents: 4_999,
      basic_washes_per_month: 2,
      deep_cleans_per_month: 1,
      deep_clean_discount_percent: 10,
      description: "Test plan"
    })
    |> Ash.create!(authorize?: false)
  end

  test "create_from_checkout creates a Subscription from a Stripe session struct" do
    email = "subtest-#{System.unique_integer([:positive])}@test.com"
    customer = register!(email)
    plan = plan!()

    session = %Stripe.Checkout.Session{
      id: "cs_test_#{System.unique_integer([:positive])}",
      mode: "subscription",
      subscription: "sub_test_#{System.unique_integer([:positive])}",
      customer: "cus_test_#{System.unique_integer([:positive])}",
      customer_email: email,
      metadata: %{"plan_id" => plan.id, "plan_slug" => plan.slug}
    }

    assert {:ok, subscription} = SubscriptionOrchestrator.create_from_checkout(session)
    assert subscription.customer_id == customer.id
    assert subscription.plan_id == plan.id
    assert subscription.status == :active

    assert [_one] = Ash.read!(Subscription, authorize?: false)
  end
end
