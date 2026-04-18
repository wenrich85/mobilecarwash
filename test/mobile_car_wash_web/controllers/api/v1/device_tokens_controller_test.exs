defmodule MobileCarWashWeb.Api.V1.DeviceTokensControllerTest do
  use MobileCarWashWeb.ApiCase

  require Ash.Query

  alias MobileCarWash.Notifications.DeviceToken

  describe "POST /api/v1/device_tokens" do
    test "requires authentication", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/device_tokens", %{token: "x"})
      assert json_response(conn, 401)
    end

    test "registers a new device token for the current customer", %{conn: conn} do
      {authed, customer, _} = register_and_sign_in(conn)

      conn =
        post(authed, ~p"/api/v1/device_tokens", %{
          token: "apns-hex-token",
          platform: "ios",
          app_version: "1.0.0",
          device_model: "iPhone15,3"
        })

      body = json_response(conn, 201)

      assert body["data"]["token"] == "apns-hex-token"
      assert body["data"]["platform"] == "ios"
      assert body["data"]["active"] == true
      assert body["data"]["id"]

      # Verify persistence
      {:ok, [row]} =
        DeviceToken
        |> Ash.Query.filter(token == "apns-hex-token")
        |> Ash.read(authorize?: false)

      assert row.customer_id == customer.id
    end

    test "re-registering the same token upserts (same id)", %{conn: conn} do
      {authed, _customer, _} = register_and_sign_in(conn)

      r1 =
        post(authed, ~p"/api/v1/device_tokens", %{
          token: "apns-upsert",
          platform: "ios"
        })

      first_id = json_response(r1, 201)["data"]["id"]

      r2 =
        post(authed, ~p"/api/v1/device_tokens", %{
          token: "apns-upsert",
          platform: "ios",
          app_version: "1.0.1"
        })

      second = json_response(r2, 201)["data"]
      assert second["id"] == first_id
      assert second["app_version"] == "1.0.1"
    end

    test "rejects request with a missing token", %{conn: conn} do
      {authed, _customer, _} = register_and_sign_in(conn)

      conn = post(authed, ~p"/api/v1/device_tokens", %{platform: "ios"})
      body = json_response(conn, 422)
      assert body["error"]
    end

    test "defaults platform to ios when omitted", %{conn: conn} do
      {authed, _customer, _} = register_and_sign_in(conn)

      conn = post(authed, ~p"/api/v1/device_tokens", %{token: "no-platform"})
      body = json_response(conn, 201)
      assert body["data"]["platform"] == "ios"
    end
  end

  describe "DELETE /api/v1/device_tokens/:id" do
    test "requires authentication", %{conn: conn} do
      conn = delete(conn, ~p"/api/v1/device_tokens/11111111-1111-1111-1111-111111111111")
      assert json_response(conn, 401)
    end

    test "deactivates the customer's own token", %{conn: conn} do
      {authed, customer, _} = register_and_sign_in(conn)

      {:ok, token} =
        DeviceToken
        |> Ash.Changeset.for_create(
          :register,
          %{token: "delete-me", customer_id: customer.id},
          actor: customer
        )
        |> Ash.create(actor: customer)

      conn = delete(authed, ~p"/api/v1/device_tokens/#{token.id}")
      assert json_response(conn, 200)["ok"] == true

      {:ok, row} = Ash.get(DeviceToken, token.id, authorize?: false)
      assert row.active == false
    end

    test "returns 404 when token belongs to a different customer", %{conn: conn} do
      {authed, _me, _} = register_and_sign_in(conn)

      {other_authed, other, _} = register_and_sign_in(conn, email: "other@x.com")

      {:ok, other_token} =
        DeviceToken
        |> Ash.Changeset.for_create(
          :register,
          %{token: "not-yours", customer_id: other.id},
          actor: other
        )
        |> Ash.create(actor: other)

      _ = other_authed
      conn = delete(authed, ~p"/api/v1/device_tokens/#{other_token.id}")
      assert json_response(conn, 404)
    end
  end
end
