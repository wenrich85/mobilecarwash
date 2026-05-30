defmodule MobileCarWashWeb.Api.V1.AdminSuppliesControllerTest do
  use MobileCarWashWeb.ApiCase

  alias MobileCarWash.Inventory.Supply

  describe "GET /api/v1/admin/supplies" do
    test "requires admin role", %{conn: conn} do
      {authed, _customer, _token} = register_and_sign_in(conn)

      conn = get(authed, ~p"/api/v1/admin/supplies")

      assert json_response(conn, 403)
    end

    test "returns supplies for native admin inventory management", %{conn: conn} do
      {authed, _admin, _token} = register_and_sign_in_admin(conn)

      supply =
        create_supply(%{
          name: "Native Soap",
          category: :chemicals,
          quantity_on_hand: Decimal.new("2.5"),
          low_stock_threshold: Decimal.new("3")
        })

      conn = get(authed, ~p"/api/v1/admin/supplies")
      body = json_response(conn, 200)

      assert returned = Enum.find(body["data"], &(&1["id"] == supply.id))
      assert returned["name"] == "Native Soap"
      assert returned["category"] == "chemicals"
      assert returned["quantity_on_hand"] == "2.5"
      assert returned["low_stock_threshold"] == "3"
      assert returned["low_stock"] == true
    end
  end

  describe "POST /api/v1/admin/supplies" do
    test "creates a supply", %{conn: conn} do
      {authed, _admin, _token} = register_and_sign_in_admin(conn)

      conn =
        post(authed, ~p"/api/v1/admin/supplies", %{
          "name" => "Native Towels",
          "category" => "disposables",
          "unit" => "packs",
          "quantity_on_hand" => "4",
          "low_stock_threshold" => "2",
          "unit_cost_cents" => 1200,
          "supplier" => "Warehouse",
          "notes" => "For native app",
          "active" => true
        })

      body = json_response(conn, 201)

      assert body["data"]["name"] == "Native Towels"
      assert body["data"]["category"] == "disposables"
      assert body["data"]["quantity_on_hand"] == "4"
      assert body["data"]["low_stock"] == false
    end
  end

  describe "PATCH /api/v1/admin/supplies/:id" do
    test "updates supply metadata", %{conn: conn} do
      {authed, _admin, _token} = register_and_sign_in_admin(conn)
      supply = create_supply(%{name: "Old Native Supply", category: :other})

      conn =
        patch(authed, ~p"/api/v1/admin/supplies/#{supply.id}", %{
          "name" => "Updated Native Supply",
          "category" => "safety",
          "unit" => "boxes",
          "low_stock_threshold" => "",
          "unit_cost_cents" => nil,
          "supplier" => "",
          "notes" => "",
          "active" => false
        })

      body = json_response(conn, 200)

      assert body["data"]["id"] == supply.id
      assert body["data"]["name"] == "Updated Native Supply"
      assert body["data"]["category"] == "safety"
      assert body["data"]["low_stock_threshold"] == nil
      assert body["data"]["active"] == false
    end
  end

  describe "POST /api/v1/admin/supplies/:id/restock" do
    test "adds stock to a supply", %{conn: conn} do
      {authed, _admin, _token} = register_and_sign_in_admin(conn)
      supply = create_supply(%{quantity_on_hand: Decimal.new("1")})

      conn =
        post(authed, ~p"/api/v1/admin/supplies/#{supply.id}/restock", %{
          "quantity" => "2.5",
          "total_cost_cents" => 0,
          "notes" => "Restocked by native app"
        })

      body = json_response(conn, 200)

      assert body["data"]["id"] == supply.id
      assert body["data"]["quantity_on_hand"] == "3.5"
    end
  end

  describe "POST /api/v1/admin/supplies/:id/use" do
    test "uses stock from a supply", %{conn: conn} do
      {authed, _admin, _token} = register_and_sign_in_admin(conn)
      supply = create_supply(%{quantity_on_hand: Decimal.new("5")})

      conn =
        post(authed, ~p"/api/v1/admin/supplies/#{supply.id}/use", %{
          "quantity" => "1.25"
        })

      body = json_response(conn, 200)

      assert body["data"]["id"] == supply.id
      assert body["data"]["quantity_on_hand"] == "3.75"
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

  defp create_supply(attrs) do
    defaults = %{
      name: "Native Supply",
      category: :other,
      unit: "units",
      quantity_on_hand: Decimal.new("0"),
      active: true
    }

    Supply
    |> Ash.Changeset.for_create(:create, Map.merge(defaults, attrs))
    |> Ash.create!(authorize?: false)
  end
end
