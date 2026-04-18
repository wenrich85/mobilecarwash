defmodule MobileCarWash.Billing.SubscriptionPlanStripeSyncTest do
  @moduledoc """
  SubscriptionPlan records should automatically create/update a Stripe
  Product and recurring Price. Like ServiceType, price changes archive
  the old Price and create a new one (Stripe prices are immutable).
  """
  use MobileCarWash.DataCase, async: false

  alias MobileCarWash.Billing.SubscriptionPlan
  alias MobileCarWash.Billing.StripeProductMock
  alias MobileCarWash.Billing.StripePriceMock

  setup do
    StripeProductMock.init()
    StripePriceMock.init()

    prev_product = Application.get_env(:mobile_car_wash, :stripe_product_module)
    prev_price = Application.get_env(:mobile_car_wash, :stripe_price_module)

    Application.put_env(:mobile_car_wash, :stripe_product_module, StripeProductMock)
    Application.put_env(:mobile_car_wash, :stripe_price_module, StripePriceMock)

    on_exit(fn ->
      if prev_product do
        Application.put_env(:mobile_car_wash, :stripe_product_module, prev_product)
      else
        Application.delete_env(:mobile_car_wash, :stripe_product_module)
      end

      if prev_price do
        Application.put_env(:mobile_car_wash, :stripe_price_module, prev_price)
      else
        Application.delete_env(:mobile_car_wash, :stripe_price_module)
      end
    end)

    :ok
  end

  defp create_plan(attrs) do
    defaults = %{
      name: "Test Plan",
      slug: "test_plan_#{:rand.uniform(100_000)}",
      price_cents: 9000,
      basic_washes_per_month: 2,
      deep_cleans_per_month: 0,
      deep_clean_discount_percent: 0
    }

    SubscriptionPlan
    |> Ash.Changeset.for_create(:create, Map.merge(defaults, attrs))
    |> Ash.create!()
  end

  describe "creating a SubscriptionPlan" do
    test "creates a Stripe Product and a recurring monthly Price" do
      plan = create_plan(%{name: "Basic Monthly", price_cents: 9000})

      assert plan.stripe_product_id =~ "prod_"
      assert plan.stripe_price_id =~ "price_"

      [{:create, product_id, product_params}] = StripeProductMock.calls(:create)
      assert product_params.name == "Basic Monthly"
      assert product_id == plan.stripe_product_id

      [{:create, _price_id, price_params}] = StripePriceMock.calls(:create)
      assert price_params.product == product_id
      assert price_params.unit_amount == 9000
      assert price_params.currency == "usd"
      assert price_params.recurring == %{interval: "month"}
    end
  end

  describe "updating a SubscriptionPlan" do
    test "changing price_cents archives the old Price and creates a new recurring one" do
      plan = create_plan(%{price_cents: 9000})
      old_price_id = plan.stripe_price_id
      StripeProductMock.init()
      StripePriceMock.init()

      {:ok, updated} =
        plan
        |> Ash.Changeset.for_update(:update, %{price_cents: 12_500})
        |> Ash.update()

      assert updated.stripe_product_id == plan.stripe_product_id
      assert updated.stripe_price_id != old_price_id

      assert [{:update, ^old_price_id, %{active: false}}] = StripePriceMock.calls(:update)

      [{:create, _, price_params}] = StripePriceMock.calls(:create)
      assert price_params.unit_amount == 12_500
      assert price_params.recurring == %{interval: "month"}
    end

    test "editing name without changing price updates only the Product" do
      plan = create_plan(%{name: "Basic Monthly"})
      StripeProductMock.init()
      StripePriceMock.init()

      {:ok, updated} =
        plan
        |> Ash.Changeset.for_update(:update, %{name: "Basic+"})
        |> Ash.update()

      assert updated.stripe_price_id == plan.stripe_price_id
      assert [{:update, _, %{name: "Basic+"}}] = StripeProductMock.calls(:update)
      assert StripePriceMock.calls(:create) == []
      assert StripePriceMock.calls(:update) == []
    end
  end
end
