defmodule Mix.Tasks.BackfillStripeCatalogTest do
  @moduledoc """
  Tests for the `mix backfill_stripe_catalog` one-time task.
  """
  use MobileCarWash.DataCase, async: false

  alias Mix.Tasks.BackfillStripeCatalog
  alias MobileCarWash.Billing.{StripeProductMock, StripePriceMock, SubscriptionPlan}
  alias MobileCarWash.Scheduling.ServiceType

  require Ash.Query

  setup do
    StripeProductMock.init()
    StripePriceMock.init()
    :ok
  end

  defp create_service_without_stripe do
    # Go through the default create action (which syncs to Stripe via mocks),
    # then null the IDs to simulate a pre-existing record from before the
    # Stripe integration shipped.
    {:ok, svc} =
      ServiceType
      |> Ash.Changeset.for_create(:create, %{
        name: "Legacy Wash",
        slug: "legacy_wash_#{:rand.uniform(100_000)}",
        base_price_cents: 5000,
        duration_minutes: 45
      })
      |> Ash.create()

    import Ecto.Query

    MobileCarWash.Repo.update_all(
      from(s in "service_types", where: s.id == type(^svc.id, :binary_id)),
      set: [stripe_product_id: nil, stripe_price_id: nil]
    )

    Ash.get!(ServiceType, svc.id)
  end

  defp create_plan_without_stripe do
    {:ok, plan} =
      SubscriptionPlan
      |> Ash.Changeset.for_create(:create, %{
        name: "Legacy Plan",
        slug: "legacy_plan_#{:rand.uniform(100_000)}",
        price_cents: 9000,
        basic_washes_per_month: 2
      })
      |> Ash.create()

    import Ecto.Query

    MobileCarWash.Repo.update_all(
      from(p in "subscription_plans", where: p.id == type(^plan.id, :binary_id)),
      set: [stripe_product_id: nil, stripe_price_id: nil]
    )

    Ash.get!(SubscriptionPlan, plan.id)
  end

  test "backfill populates Stripe IDs on services that are missing them" do
    svc = create_service_without_stripe()

    assert svc.stripe_product_id == nil
    assert svc.stripe_price_id == nil

    # Suppress IO output during the task run
    ExUnit.CaptureIO.capture_io(fn ->
      BackfillStripeCatalog.run([])
    end)

    reloaded = Ash.get!(ServiceType, svc.id)
    assert reloaded.stripe_product_id =~ "prod_"
    assert reloaded.stripe_price_id =~ "price_"
  end

  test "backfill populates Stripe IDs on plans that are missing them" do
    plan = create_plan_without_stripe()

    assert plan.stripe_product_id == nil
    assert plan.stripe_price_id == nil

    ExUnit.CaptureIO.capture_io(fn ->
      BackfillStripeCatalog.run([])
    end)

    reloaded = Ash.get!(SubscriptionPlan, plan.id)
    assert reloaded.stripe_product_id =~ "prod_"
    assert reloaded.stripe_price_id =~ "price_"
  end

  test "backfill is idempotent — already-synced records are left alone" do
    svc = create_service_without_stripe()

    ExUnit.CaptureIO.capture_io(fn ->
      BackfillStripeCatalog.run([])
    end)

    first_product_id = Ash.get!(ServiceType, svc.id).stripe_product_id

    ExUnit.CaptureIO.capture_io(fn ->
      BackfillStripeCatalog.run([])
    end)

    reloaded = Ash.get!(ServiceType, svc.id)
    assert reloaded.stripe_product_id == first_product_id
  end
end
