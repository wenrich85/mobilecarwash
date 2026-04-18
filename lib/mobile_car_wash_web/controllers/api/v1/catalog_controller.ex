defmodule MobileCarWashWeb.Api.V1.CatalogController do
  @moduledoc """
  Public catalog endpoints. No auth required — lets the mobile app show
  services and subscription plans before a user signs up.
  """
  use MobileCarWashWeb, :controller

  alias MobileCarWash.Scheduling.ServiceType
  alias MobileCarWash.Billing.SubscriptionPlan

  require Ash.Query

  def services(conn, _params) do
    services =
      ServiceType
      |> Ash.Query.filter(active == true)
      |> Ash.Query.sort(base_price_cents: :asc)
      |> Ash.read!()
      |> Enum.map(&service_json/1)

    json(conn, %{data: services})
  end

  def subscription_plans(conn, _params) do
    plans =
      SubscriptionPlan
      |> Ash.Query.filter(active == true)
      |> Ash.Query.sort(price_cents: :asc)
      |> Ash.read!()
      |> Enum.map(&plan_json/1)

    json(conn, %{data: plans})
  end

  defp service_json(svc) do
    %{
      id: svc.id,
      name: svc.name,
      slug: svc.slug,
      description: svc.description,
      base_price_cents: svc.base_price_cents,
      duration_minutes: svc.duration_minutes,
      window_minutes: svc.window_minutes,
      block_capacity: svc.block_capacity
    }
  end

  defp plan_json(plan) do
    %{
      id: plan.id,
      name: plan.name,
      slug: plan.slug,
      description: plan.description,
      price_cents: plan.price_cents,
      basic_washes_per_month: plan.basic_washes_per_month,
      deep_cleans_per_month: plan.deep_cleans_per_month,
      deep_clean_discount_percent: plan.deep_clean_discount_percent
    }
  end
end
