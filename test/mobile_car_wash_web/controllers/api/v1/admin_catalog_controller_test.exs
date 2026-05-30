defmodule MobileCarWashWeb.Api.V1.AdminCatalogControllerTest do
  use MobileCarWashWeb.ApiCase

  alias MobileCarWash.Billing.SubscriptionPlan
  alias MobileCarWash.Scheduling.ServiceType

  describe "GET /api/v1/admin/services" do
    test "requires admin role", %{conn: conn} do
      {authed, _customer, _token} = register_and_sign_in(conn)

      conn = get(authed, ~p"/api/v1/admin/services")

      assert json_response(conn, 403)
    end

    test "returns native admin services including inactive services", %{conn: conn} do
      {authed, _admin, _token} = register_and_sign_in_admin(conn)
      service = create_service()

      conn = get(authed, ~p"/api/v1/admin/services")
      body = json_response(conn, 200)

      assert returned = Enum.find(body["data"], &(&1["id"] == service.id))
      assert returned["name"] == service.name
      assert returned["slug"] == service.slug
      assert returned["description"] == service.description
      assert returned["base_price_cents"] == service.base_price_cents
      assert returned["duration_minutes"] == service.duration_minutes
      assert returned["active"] == false
      assert returned["window_minutes"] == service.window_minutes
      assert returned["block_capacity"] == service.block_capacity
    end
  end

  describe "POST /api/v1/admin/services" do
    test "creates a service for native admin catalog management", %{conn: conn} do
      {authed, _admin, _token} = register_and_sign_in_admin(conn)

      conn =
        post(authed, ~p"/api/v1/admin/services", %{
          "name" => "Native Express",
          "description" => "Quick native app wash",
          "base_price_cents" => 7_500,
          "duration_minutes" => 60,
          "block_capacity" => 4
        })

      body = json_response(conn, 201)

      assert body["data"]["name"] == "Native Express"
      assert body["data"]["slug"] == "native-express"
      assert body["data"]["base_price_cents"] == 7_500
      assert body["data"]["duration_minutes"] == 60
      assert body["data"]["active"] == true
      assert body["data"]["block_capacity"] == 4
    end
  end

  describe "PATCH /api/v1/admin/services/:id" do
    test "updates a service", %{conn: conn} do
      {authed, _admin, _token} = register_and_sign_in_admin(conn)
      service = create_service()

      conn =
        patch(authed, ~p"/api/v1/admin/services/#{service.id}", %{
          "name" => "Native Ceramic Plus",
          "description" => "Updated from iOS",
          "base_price_cents" => 21_000,
          "duration_minutes" => 165,
          "block_capacity" => 3
        })

      body = json_response(conn, 200)

      assert body["data"]["id"] == service.id
      assert body["data"]["name"] == "Native Ceramic Plus"
      assert body["data"]["slug"] == "native-ceramic-plus"
      assert body["data"]["description"] == "Updated from iOS"
      assert body["data"]["base_price_cents"] == 21_000
      assert body["data"]["duration_minutes"] == 165
      assert body["data"]["block_capacity"] == 3
    end
  end

  describe "POST /api/v1/admin/services/:id/toggle" do
    test "toggles a service active state", %{conn: conn} do
      {authed, _admin, _token} = register_and_sign_in_admin(conn)
      service = create_service()

      conn = post(authed, ~p"/api/v1/admin/services/#{service.id}/toggle")

      body = json_response(conn, 200)

      assert body["data"]["id"] == service.id
      assert body["data"]["active"] == true
    end
  end

  describe "GET /api/v1/admin/subscription_plans" do
    test "returns native admin subscription plans including inactive plans", %{conn: conn} do
      {authed, _admin, _token} = register_and_sign_in_admin(conn)
      plan = create_plan()

      conn = get(authed, ~p"/api/v1/admin/subscription_plans")
      body = json_response(conn, 200)

      assert returned = Enum.find(body["data"], &(&1["id"] == plan.id))
      assert returned["name"] == plan.name
      assert returned["slug"] == plan.slug
      assert returned["description"] == plan.description
      assert returned["price_cents"] == plan.price_cents
      assert returned["basic_washes_per_month"] == plan.basic_washes_per_month
      assert returned["deep_cleans_per_month"] == plan.deep_cleans_per_month
      assert returned["deep_clean_discount_percent"] == plan.deep_clean_discount_percent
      assert returned["active"] == false
    end
  end

  describe "POST /api/v1/admin/subscription_plans" do
    test "creates a subscription plan for native admin catalog management", %{conn: conn} do
      {authed, _admin, _token} = register_and_sign_in_admin(conn)

      conn =
        post(authed, ~p"/api/v1/admin/subscription_plans", %{
          "name" => "Native Plus",
          "description" => "Native app plan",
          "price_cents" => 16_500,
          "basic_washes_per_month" => 4,
          "deep_cleans_per_month" => 1,
          "deep_clean_discount_percent" => 35
        })

      body = json_response(conn, 201)

      assert body["data"]["name"] == "Native Plus"
      assert body["data"]["slug"] == "native-plus"
      assert body["data"]["price_cents"] == 16_500
      assert body["data"]["basic_washes_per_month"] == 4
      assert body["data"]["deep_cleans_per_month"] == 1
      assert body["data"]["deep_clean_discount_percent"] == 35
      assert body["data"]["active"] == true
    end
  end

  describe "PATCH /api/v1/admin/subscription_plans/:id" do
    test "updates a subscription plan", %{conn: conn} do
      {authed, _admin, _token} = register_and_sign_in_admin(conn)
      plan = create_plan()

      conn =
        patch(authed, ~p"/api/v1/admin/subscription_plans/#{plan.id}", %{
          "name" => "Native Fleet Pro",
          "description" => "Updated native plan",
          "price_cents" => 49_000,
          "basic_washes_per_month" => 10,
          "deep_cleans_per_month" => 3,
          "deep_clean_discount_percent" => 45
        })

      body = json_response(conn, 200)

      assert body["data"]["id"] == plan.id
      assert body["data"]["name"] == "Native Fleet Pro"
      assert body["data"]["slug"] == "native-fleet-pro"
      assert body["data"]["description"] == "Updated native plan"
      assert body["data"]["price_cents"] == 49_000
      assert body["data"]["basic_washes_per_month"] == 10
      assert body["data"]["deep_cleans_per_month"] == 3
      assert body["data"]["deep_clean_discount_percent"] == 45
    end
  end

  describe "POST /api/v1/admin/subscription_plans/:id/toggle" do
    test "toggles a subscription plan active state", %{conn: conn} do
      {authed, _admin, _token} = register_and_sign_in_admin(conn)
      plan = create_plan()

      conn = post(authed, ~p"/api/v1/admin/subscription_plans/#{plan.id}/toggle")

      body = json_response(conn, 200)

      assert body["data"]["id"] == plan.id
      assert body["data"]["active"] == true
    end
  end

  defp register_and_sign_in_admin(conn) do
    {authed, customer, token} = register_and_sign_in(conn)

    {:ok, admin} =
      customer
      |> Ash.Changeset.for_update(:update, %{role: :admin})
      |> Ash.update(authorize?: false)

    {authed, admin, token}
  end

  defp create_service do
    unique = System.unique_integer([:positive])

    ServiceType
    |> Ash.Changeset.for_create(:create, %{
      name: "Native Ceramic #{unique}",
      slug: "native-ceramic-#{unique}",
      description: "Native app ceramic service",
      base_price_cents: 19_500,
      duration_minutes: 150,
      active: false,
      window_minutes: 510,
      block_capacity: 2
    })
    |> Ash.create!(authorize?: false)
  end

  defp create_plan do
    unique = System.unique_integer([:positive])

    SubscriptionPlan
    |> Ash.Changeset.for_create(:create, %{
      name: "Native Fleet #{unique}",
      slug: "native-fleet-#{unique}",
      description: "Native app fleet subscription",
      price_cents: 45_000,
      basic_washes_per_month: 8,
      deep_cleans_per_month: 2,
      deep_clean_discount_percent: 40,
      active: false
    })
    |> Ash.create!(authorize?: false)
  end
end
