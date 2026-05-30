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
