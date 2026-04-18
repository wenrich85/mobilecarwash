defmodule MobileCarWashWeb.Api.V1.CatalogControllerTest do
  @moduledoc """
  The catalog endpoints (services + subscription_plans) are public — no
  auth required — because new customers need to browse before signing up.
  """
  use MobileCarWashWeb.ConnCase, async: true

  alias MobileCarWash.Scheduling.ServiceType
  alias MobileCarWash.Billing.SubscriptionPlan

  describe "GET /api/v1/services" do
    test "returns active services with id, name, price, duration", %{conn: conn} do
      {:ok, _} =
        ServiceType
        |> Ash.Changeset.for_create(:create, %{
          name: "Premium Wash",
          slug: "premium_wash_#{:rand.uniform(100_000)}",
          description: "Top-tier wash",
          base_price_cents: 7500,
          duration_minutes: 60
        })
        |> Ash.create()

      conn = get(conn, ~p"/api/v1/services")
      body = json_response(conn, 200)

      assert is_list(body["data"])
      assert length(body["data"]) > 0

      svc = Enum.find(body["data"], &(&1["name"] == "Premium Wash"))
      assert svc["base_price_cents"] == 7500
      assert svc["duration_minutes"] == 60
      assert svc["description"] == "Top-tier wash"
    end

    test "excludes inactive services", %{conn: conn} do
      {:ok, svc} =
        ServiceType
        |> Ash.Changeset.for_create(:create, %{
          name: "Hidden Wash",
          slug: "hidden_wash_#{:rand.uniform(100_000)}",
          base_price_cents: 5000,
          duration_minutes: 30
        })
        |> Ash.create()

      {:ok, _} =
        svc
        |> Ash.Changeset.for_update(:update, %{active: false})
        |> Ash.update()

      conn = get(conn, ~p"/api/v1/services")
      body = json_response(conn, 200)

      refute Enum.any?(body["data"], &(&1["name"] == "Hidden Wash"))
    end
  end

  describe "GET /api/v1/subscription_plans" do
    test "returns active plans with quotas and pricing", %{conn: conn} do
      {:ok, _} =
        SubscriptionPlan
        |> Ash.Changeset.for_create(:create, %{
          name: "Gold API",
          slug: "gold_api_#{:rand.uniform(100_000)}",
          price_cents: 15_000,
          basic_washes_per_month: 4,
          deep_cleans_per_month: 1,
          deep_clean_discount_percent: 40,
          description: "Test plan"
        })
        |> Ash.create()

      conn = get(conn, ~p"/api/v1/subscription_plans")
      body = json_response(conn, 200)

      plan = Enum.find(body["data"], &(&1["name"] == "Gold API"))
      assert plan["price_cents"] == 15_000
      assert plan["basic_washes_per_month"] == 4
      assert plan["deep_cleans_per_month"] == 1
      assert plan["deep_clean_discount_percent"] == 40
    end
  end
end
