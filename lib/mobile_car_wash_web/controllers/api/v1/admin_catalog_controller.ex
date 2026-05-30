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

  def create_service(conn, params) do
    with {:ok, service} <-
           ServiceType
           |> Ash.Changeset.for_create(:create, service_params(params))
           |> Ash.create(authorize?: false) do
      conn
      |> put_status(:created)
      |> json(%{data: service_json(service)})
    end
  end

  def update_service(conn, %{"id" => id} = params) do
    with {:ok, service} <- Ash.get(ServiceType, id, authorize?: false),
         {:ok, service} <-
           service
           |> Ash.Changeset.for_update(:update, service_params(params))
           |> Ash.update(authorize?: false) do
      json(conn, %{data: service_json(service)})
    end
  end

  def toggle_service(conn, %{"id" => id}) do
    with {:ok, service} <- Ash.get(ServiceType, id, authorize?: false),
         {:ok, service} <-
           service
           |> Ash.Changeset.for_update(:update, %{active: not service.active})
           |> Ash.update(authorize?: false) do
      json(conn, %{data: service_json(service)})
    end
  end

  def subscription_plans(conn, _params) do
    plans =
      SubscriptionPlan
      |> Ash.Query.sort(price_cents: :asc)
      |> Ash.read!(authorize?: false)
      |> Enum.map(&plan_json/1)

    json(conn, %{data: plans})
  end

  def create_subscription_plan(conn, params) do
    with {:ok, plan} <-
           SubscriptionPlan
           |> Ash.Changeset.for_create(:create, plan_params(params))
           |> Ash.create(authorize?: false) do
      conn
      |> put_status(:created)
      |> json(%{data: plan_json(plan)})
    end
  end

  def update_subscription_plan(conn, %{"id" => id} = params) do
    with {:ok, plan} <- Ash.get(SubscriptionPlan, id, authorize?: false),
         {:ok, plan} <-
           plan
           |> Ash.Changeset.for_update(:update, plan_params(params))
           |> Ash.update(authorize?: false) do
      json(conn, %{data: plan_json(plan)})
    end
  end

  def toggle_subscription_plan(conn, %{"id" => id}) do
    with {:ok, plan} <- Ash.get(SubscriptionPlan, id, authorize?: false),
         {:ok, plan} <-
           plan
           |> Ash.Changeset.for_update(:update, %{active: not plan.active})
           |> Ash.update(authorize?: false) do
      json(conn, %{data: plan_json(plan)})
    end
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

  defp service_params(params) do
    %{
      name: params["name"],
      slug: slugify(params["name"]),
      description: params["description"],
      base_price_cents: params["base_price_cents"],
      duration_minutes: params["duration_minutes"],
      block_capacity: params["block_capacity"],
      active: Map.get(params, "active", true)
    }
  end

  defp plan_params(params) do
    %{
      name: params["name"],
      slug: slugify(params["name"]),
      description: params["description"],
      price_cents: params["price_cents"],
      basic_washes_per_month: params["basic_washes_per_month"],
      deep_cleans_per_month: params["deep_cleans_per_month"],
      deep_clean_discount_percent: params["deep_clean_discount_percent"],
      active: Map.get(params, "active", true)
    }
  end

  defp slugify(value) when is_binary(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  defp slugify(_value), do: nil

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
