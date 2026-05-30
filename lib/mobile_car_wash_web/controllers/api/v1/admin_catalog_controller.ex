defmodule MobileCarWashWeb.Api.V1.AdminCatalogController do
  @moduledoc """
  Admin catalog endpoints for native clients.
  """
  use MobileCarWashWeb, :controller

  alias MobileCarWash.Billing.SubscriptionPlan
  alias MobileCarWash.Scheduling.ServiceType

  require Ash.Query

  plug MobileCarWashWeb.Plugs.RequireApiAuth
  plug :require_admin
  action_fallback MobileCarWashWeb.Api.V1.FallbackController

  def services(conn, _params) do
    services =
      ServiceType
      |> Ash.Query.sort(base_price_cents: :asc)
      |> Ash.read!(authorize?: false)
      |> Enum.map(&service_json/1)

    json(conn, %{data: services})
  end

  def subscription_plans(conn, _params) do
    plans =
      SubscriptionPlan
      |> Ash.Query.sort(price_cents: :asc)
      |> Ash.read!(authorize?: false)
      |> Enum.map(&plan_json/1)

    json(conn, %{data: plans})
  end

  defp require_admin(conn, _opts) do
    case current_user(conn) do
      %{role: :admin} ->
        conn

      _ ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "forbidden", message: "Admin role required"})
        |> halt()
    end
  end

  defp service_json(service) do
    %{
      id: service.id,
      name: service.name,
      slug: service.slug,
      description: service.description,
      base_price_cents: service.base_price_cents,
      duration_minutes: service.duration_minutes,
      active: service.active,
      window_minutes: service.window_minutes,
      block_capacity: service.block_capacity
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
      deep_clean_discount_percent: plan.deep_clean_discount_percent,
      active: plan.active
    }
  end

  defp current_user(conn), do: conn.assigns[:current_user] || conn.assigns[:current_customer]
end
