defmodule MobileCarWashWeb.Api.V1.VehiclesControllerTest do
  use MobileCarWashWeb.ApiCase

  describe "GET /api/v1/vehicles" do
    test "requires authentication", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/vehicles")
      assert json_response(conn, 401)
    end

    test "returns only the current customer's vehicles", %{conn: conn} do
      {authed, customer, _} = register_and_sign_in(conn)

      {:ok, v1} =
        MobileCarWash.Fleet.Vehicle
        |> Ash.Changeset.for_create(:create, %{make: "Toyota", model: "Camry", size: :car})
        |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
        |> Ash.create()

      # Another customer's vehicle — must not leak
      {:ok, other} =
        MobileCarWash.Accounts.Customer
        |> Ash.Changeset.for_create(:create_guest, %{
          email: "other-#{:rand.uniform(100_000)}@example.com",
          name: "Other"
        })
        |> Ash.create()

      {:ok, _} =
        MobileCarWash.Fleet.Vehicle
        |> Ash.Changeset.for_create(:create, %{make: "Ford", model: "F-150", size: :pickup})
        |> Ash.Changeset.force_change_attribute(:customer_id, other.id)
        |> Ash.create()

      conn = get(authed, ~p"/api/v1/vehicles")
      body = json_response(conn, 200)

      assert length(body["data"]) == 1
      assert hd(body["data"])["id"] == v1.id
      assert hd(body["data"])["make"] == "Toyota"
    end
  end

  describe "POST /api/v1/vehicles" do
    test "requires authentication", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/vehicles", %{make: "Toyota", model: "Camry"})
      assert json_response(conn, 401)
    end

    test "creates a vehicle owned by the current customer", %{conn: conn} do
      {authed, customer, _} = register_and_sign_in(conn)

      conn =
        post(authed, ~p"/api/v1/vehicles", %{
          make: "Honda",
          model: "Civic",
          year: 2023,
          color: "Blue",
          size: "car"
        })

      body = json_response(conn, 201)
      assert body["make"] == "Honda"
      assert body["model"] == "Civic"
      assert body["customer_id"] == customer.id
    end

    test "returns 422 on invalid input", %{conn: conn} do
      {authed, _, _} = register_and_sign_in(conn)

      conn = post(authed, ~p"/api/v1/vehicles", %{})

      assert json_response(conn, 422)
    end
  end
end
