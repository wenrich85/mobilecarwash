defmodule MobileCarWashWeb.Api.V1.AdminVansControllerTest do
  use MobileCarWashWeb.ApiCase

  alias MobileCarWash.Operations.Van

  describe "GET /api/v1/admin/vans" do
    test "requires admin role", %{conn: conn} do
      {authed, _customer, _token} = register_and_sign_in(conn)

      conn = get(authed, ~p"/api/v1/admin/vans")

      assert json_response(conn, 403)
    end

    test "returns vans for native admin fleet management", %{conn: conn} do
      {authed, _admin, _token} = register_and_sign_in_admin(conn)
      van = create_van(%{name: "Native Van", license_plate: "MCW123", active: true})

      conn = get(authed, ~p"/api/v1/admin/vans")
      body = json_response(conn, 200)

      assert returned = Enum.find(body["data"], &(&1["id"] == van.id))
      assert returned["name"] == "Native Van"
      assert returned["license_plate"] == "MCW123"
      assert returned["active"] == true
      assert is_binary(returned["inserted_at"])
      assert is_binary(returned["updated_at"])
    end
  end

  describe "POST /api/v1/admin/vans" do
    test "creates a van", %{conn: conn} do
      {authed, _admin, _token} = register_and_sign_in_admin(conn)

      conn =
        post(authed, ~p"/api/v1/admin/vans", %{
          "name" => "New Native Van",
          "license_plate" => "NEW456"
        })

      body = json_response(conn, 201)

      assert body["data"]["name"] == "New Native Van"
      assert body["data"]["license_plate"] == "NEW456"
      assert body["data"]["active"] == true
    end
  end

  describe "PATCH /api/v1/admin/vans/:id" do
    test "updates a van", %{conn: conn} do
      {authed, _admin, _token} = register_and_sign_in_admin(conn)
      van = create_van(%{name: "Original Native Van", license_plate: "OLD123"})

      conn =
        patch(authed, ~p"/api/v1/admin/vans/#{van.id}", %{
          "name" => "Updated Native Van",
          "license_plate" => ""
        })

      body = json_response(conn, 200)

      assert body["data"]["id"] == van.id
      assert body["data"]["name"] == "Updated Native Van"
      assert body["data"]["license_plate"] == nil
    end
  end

  describe "POST /api/v1/admin/vans/:id/toggle" do
    test "toggles a van active state", %{conn: conn} do
      {authed, _admin, _token} = register_and_sign_in_admin(conn)
      van = create_van(%{name: "Toggle Native Van", active: true})

      conn = post(authed, ~p"/api/v1/admin/vans/#{van.id}/toggle")
      body = json_response(conn, 200)

      assert body["data"]["id"] == van.id
      assert body["data"]["active"] == false
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

  defp create_van(attrs) do
    defaults = %{
      name: "Admin Native Van",
      license_plate: nil,
      active: true
    }

    Van
    |> Ash.Changeset.for_create(:create, Map.merge(defaults, attrs))
    |> Ash.create!(authorize?: false)
  end
end
