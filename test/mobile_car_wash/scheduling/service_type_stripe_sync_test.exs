defmodule MobileCarWash.Scheduling.ServiceTypeStripeSyncTest do
  @moduledoc """
  When a ServiceType is created or updated, we expect the system to
  automatically create/update a matching Stripe Product + Price so that
  the admin never has to copy-paste IDs from the Stripe dashboard.

  Pricing rule: Stripe Prices are immutable on `unit_amount`. When a
  service's base price changes, we archive the old Price and create a
  new one so historical records stay intact.
  """
  use MobileCarWash.DataCase, async: false

  alias MobileCarWash.Scheduling.ServiceType
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

  defp create_service(attrs) do
    defaults = %{
      name: "Test Wash",
      slug: "test_wash_#{:rand.uniform(100_000)}",
      base_price_cents: 5000,
      duration_minutes: 45
    }

    ServiceType
    |> Ash.Changeset.for_create(:create, Map.merge(defaults, attrs))
    |> Ash.create!()
  end

  describe "creating a ServiceType" do
    test "creates a matching Stripe Product and Price, storing the IDs" do
      service = create_service(%{name: "Basic Wash", base_price_cents: 5000})

      assert service.stripe_product_id =~ "prod_"
      assert service.stripe_price_id =~ "price_"

      [{:create, product_id, product_params}] = StripeProductMock.calls(:create)
      assert product_params.name == "Basic Wash"
      assert product_id == service.stripe_product_id

      [{:create, price_id, price_params}] = StripePriceMock.calls(:create)
      assert price_params.product == product_id
      assert price_params.unit_amount == 5000
      assert price_params.currency == "usd"
      assert price_id == service.stripe_price_id
    end
  end

  describe "updating a ServiceType" do
    test "editing only the name updates the Stripe Product in place, not the Price" do
      service = create_service(%{name: "Basic Wash"})
      StripeProductMock.init()
      StripePriceMock.init()

      {:ok, updated} =
        service
        |> Ash.Changeset.for_update(:update, %{name: "Premium Wash"})
        |> Ash.update()

      assert updated.stripe_product_id == service.stripe_product_id
      assert updated.stripe_price_id == service.stripe_price_id

      assert [{:update, product_id, %{name: "Premium Wash"}}] = StripeProductMock.calls(:update)
      assert product_id == service.stripe_product_id

      assert StripePriceMock.calls(:create) == []
      assert StripePriceMock.calls(:update) == []
    end

    test "changing base_price_cents archives the old Price and creates a new one" do
      service = create_service(%{base_price_cents: 5000})
      old_price_id = service.stripe_price_id
      StripeProductMock.init()
      StripePriceMock.init()

      {:ok, updated} =
        service
        |> Ash.Changeset.for_update(:update, %{base_price_cents: 6000})
        |> Ash.update()

      assert updated.stripe_product_id == service.stripe_product_id
      assert updated.stripe_price_id != old_price_id
      assert updated.stripe_price_id =~ "price_"

      assert [{:update, ^old_price_id, %{active: false}}] = StripePriceMock.calls(:update)

      [{:create, new_price_id, price_params}] = StripePriceMock.calls(:create)
      assert price_params.unit_amount == 6000
      assert price_params.product == service.stripe_product_id
      assert new_price_id == updated.stripe_price_id
    end

    test "setting active=false archives both Product and Price in Stripe" do
      service = create_service(%{})
      product_id = service.stripe_product_id
      price_id = service.stripe_price_id
      StripeProductMock.init()
      StripePriceMock.init()

      {:ok, _updated} =
        service
        |> Ash.Changeset.for_update(:update, %{active: false})
        |> Ash.update()

      assert [{:update, ^product_id, %{active: false}}] = StripeProductMock.calls(:update)
      assert [{:update, ^price_id, %{active: false}}] = StripePriceMock.calls(:update)
    end
  end
end
