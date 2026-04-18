defmodule MobileCarWashWeb.Api.V1.AddressesControllerTest do
  use MobileCarWashWeb.ApiCase

  describe "GET /api/v1/addresses" do
    test "requires authentication", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/addresses")
      assert json_response(conn, 401)
    end

    test "returns only the current customer's addresses", %{conn: conn} do
      {authed, customer, _} = register_and_sign_in(conn)

      {:ok, addr} =
        MobileCarWash.Fleet.Address
        |> Ash.Changeset.for_create(:create, %{
          street: "123 Main St",
          city: "San Antonio",
          state: "TX",
          zip: "78261"
        })
        |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
        |> Ash.create()

      conn = get(authed, ~p"/api/v1/addresses")
      body = json_response(conn, 200)

      assert length(body["data"]) == 1
      assert hd(body["data"])["id"] == addr.id
      assert hd(body["data"])["latitude"] == 29.65
    end
  end

  describe "POST /api/v1/addresses" do
    test "creates an address owned by the current customer, auto-geocoded", %{conn: conn} do
      {authed, customer, _} = register_and_sign_in(conn)

      conn =
        post(authed, ~p"/api/v1/addresses", %{
          street: "456 Oak Ave",
          city: "San Antonio",
          state: "TX",
          zip: "78259"
        })

      body = json_response(conn, 201)
      assert body["customer_id"] == customer.id
      assert body["latitude"] == 29.61
      assert body["longitude"] == -98.46
    end

    test "requires authentication", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/addresses", %{street: "x"})
      assert json_response(conn, 401)
    end
  end
end
