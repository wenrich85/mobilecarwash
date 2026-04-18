defmodule MobileCarWash.Billing.StripeCatalogTest do
  @moduledoc """
  Tests for the Stripe Products & Prices CRUD surface on StripeClient.

  These functions let us manage the Stripe product catalog from our admin UI
  so that services/plans in our DB stay in sync with Stripe without manual
  copy-paste of price IDs.
  """
  use ExUnit.Case, async: false

  alias MobileCarWash.Billing.StripeClient
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

  describe "create_product/1" do
    test "creates a Stripe Product with the provided name and description" do
      assert {:ok, %{id: product_id}} =
               StripeClient.create_product(%{
                 name: "Basic Wash",
                 description: "Exterior wash & tire shine"
               })

      assert product_id =~ "prod_"

      [{:create, ^product_id, params}] = StripeProductMock.calls(:create)
      assert params.name == "Basic Wash"
      assert params.description == "Exterior wash & tire shine"
    end

    test "passes metadata through to Stripe" do
      assert {:ok, _} =
               StripeClient.create_product(%{
                 name: "Deep Clean",
                 metadata: %{service_slug: "deep_clean"}
               })

      [{:create, _, params}] = StripeProductMock.calls(:create)
      assert params.metadata == %{service_slug: "deep_clean"}
    end
  end

  describe "update_product/2" do
    test "updates a Stripe Product by id" do
      assert {:ok, %{id: "prod_123"}} =
               StripeClient.update_product("prod_123", %{name: "New Name"})

      assert [{:update, "prod_123", %{name: "New Name"}}] = StripeProductMock.calls(:update)
    end
  end

  describe "archive_product/1" do
    test "marks the Stripe Product inactive" do
      assert {:ok, %{id: "prod_abc"}} = StripeClient.archive_product("prod_abc")

      assert [{:update, "prod_abc", %{active: false}}] = StripeProductMock.calls(:update)
    end
  end

  describe "create_price/1" do
    test "creates a one-time price attached to a product" do
      assert {:ok, %{id: price_id}} =
               StripeClient.create_price(%{
                 product: "prod_123",
                 unit_amount: 5000,
                 currency: "usd"
               })

      assert price_id =~ "price_"

      [{:create, ^price_id, params}] = StripePriceMock.calls(:create)
      assert params.product == "prod_123"
      assert params.unit_amount == 5000
      assert params.currency == "usd"
      refute Map.has_key?(params, :recurring)
    end

    test "creates a recurring monthly price when recurring interval is given" do
      assert {:ok, _} =
               StripeClient.create_price(%{
                 product: "prod_sub",
                 unit_amount: 9000,
                 currency: "usd",
                 recurring: %{interval: "month"}
               })

      [{:create, _, params}] = StripePriceMock.calls(:create)
      assert params.recurring == %{interval: "month"}
    end
  end

  describe "archive_price/1" do
    test "marks the Stripe Price inactive" do
      assert {:ok, %{id: "price_xyz"}} = StripeClient.archive_price("price_xyz")

      assert [{:update, "price_xyz", %{active: false}}] = StripePriceMock.calls(:update)
    end
  end
end
