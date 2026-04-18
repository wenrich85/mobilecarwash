defmodule Mix.Tasks.BackfillStripeCatalog do
  @moduledoc """
  One-time backfill: for every ServiceType and SubscriptionPlan that doesn't
  yet have a Stripe Product/Price, creates them via the Stripe API and stores
  the IDs.

  Run with:

      mix backfill_stripe_catalog

  Safe to re-run — records already linked are skipped.
  """
  use Mix.Task

  @shortdoc "Backfill Stripe Products & Prices for existing ServiceTypes + SubscriptionPlans"

  alias MobileCarWash.Billing.{StripeClient, SubscriptionPlan}
  alias MobileCarWash.Scheduling.ServiceType

  require Ash.Query

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    backfill_services()
    backfill_plans()

    IO.puts("\nDone.")
  end

  defp backfill_services do
    IO.puts("Backfilling ServiceTypes...")

    services =
      ServiceType
      |> Ash.Query.filter(is_nil(stripe_product_id) or is_nil(stripe_price_id))
      |> Ash.read!()

    Enum.each(services, fn svc ->
      case ensure_service_stripe(svc) do
        {:ok, updated} ->
          IO.puts(
            "  ✓ #{svc.name}: product=#{updated.stripe_product_id}, price=#{updated.stripe_price_id}"
          )

        {:error, reason} ->
          IO.puts("  ✗ #{svc.name}: #{inspect(reason)}")
      end
    end)

    if services == [], do: IO.puts("  (all services already synced)")
  end

  defp backfill_plans do
    IO.puts("\nBackfilling SubscriptionPlans...")

    plans =
      SubscriptionPlan
      |> Ash.Query.filter(is_nil(stripe_product_id) or is_nil(stripe_price_id))
      |> Ash.read!()

    Enum.each(plans, fn plan ->
      case ensure_plan_stripe(plan) do
        {:ok, updated} ->
          IO.puts(
            "  ✓ #{plan.name}: product=#{updated.stripe_product_id}, price=#{updated.stripe_price_id}"
          )

        {:error, reason} ->
          IO.puts("  ✗ #{plan.name}: #{inspect(reason)}")
      end
    end)

    if plans == [], do: IO.puts("  (all plans already synced)")
  end

  defp ensure_service_stripe(svc) do
    with {:ok, product_id} <-
           ensure_product(svc.stripe_product_id, svc.name, svc.description),
         {:ok, price_id} <-
           ensure_price(svc.stripe_price_id, product_id, svc.base_price_cents, false) do
      svc
      |> Ash.Changeset.for_update(:update, %{})
      |> Ash.Changeset.force_change_attribute(:stripe_product_id, product_id)
      |> Ash.Changeset.force_change_attribute(:stripe_price_id, price_id)
      |> Ash.update()
    end
  end

  defp ensure_plan_stripe(plan) do
    with {:ok, product_id} <-
           ensure_product(plan.stripe_product_id, plan.name, plan.description),
         {:ok, price_id} <-
           ensure_price(plan.stripe_price_id, product_id, plan.price_cents, true) do
      plan
      |> Ash.Changeset.for_update(:update, %{})
      |> Ash.Changeset.force_change_attribute(:stripe_product_id, product_id)
      |> Ash.Changeset.force_change_attribute(:stripe_price_id, price_id)
      |> Ash.update()
    end
  end

  defp ensure_product(nil, name, description) do
    params = %{name: name} |> maybe_put(:description, description)

    case StripeClient.create_product(params) do
      {:ok, %{id: id}} -> {:ok, id}
      err -> err
    end
  end

  defp ensure_product(existing, _name, _description), do: {:ok, existing}

  defp ensure_price(nil, product_id, amount, recurring?) do
    params =
      %{product: product_id, unit_amount: amount, currency: "usd"}
      |> maybe_recurring(recurring?)

    case StripeClient.create_price(params) do
      {:ok, %{id: id}} -> {:ok, id}
      err -> err
    end
  end

  defp ensure_price(existing, _product_id, _amount, _recurring?), do: {:ok, existing}

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_recurring(map, true), do: Map.put(map, :recurring, %{interval: "month"})
  defp maybe_recurring(map, false), do: map
end
