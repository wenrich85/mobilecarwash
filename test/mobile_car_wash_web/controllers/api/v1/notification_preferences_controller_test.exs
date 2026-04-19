defmodule MobileCarWashWeb.Api.V1.NotificationPreferencesControllerTest do
  use MobileCarWashWeb.ApiCase

  describe "GET /api/v1/notification_preferences" do
    test "requires authentication", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/notification_preferences")
      assert json_response(conn, 401)
    end

    test "returns the current customer's opt-in state", %{conn: conn} do
      {authed, _customer, _} = register_and_sign_in(conn)

      conn = get(authed, ~p"/api/v1/notification_preferences")
      body = json_response(conn, 200)

      assert body["data"]["sms_opt_in"] == false
      assert body["data"]["push_opt_in"] == true
    end
  end

  describe "PATCH /api/v1/notification_preferences" do
    test "requires authentication", %{conn: conn} do
      conn = patch(conn, ~p"/api/v1/notification_preferences", %{sms_opt_in: true})
      assert json_response(conn, 401)
    end

    test "updates only the provided fields", %{conn: conn} do
      {authed, customer, _} = register_and_sign_in(conn)

      conn =
        patch(authed, ~p"/api/v1/notification_preferences", %{
          sms_opt_in: true,
          push_opt_in: false
        })

      body = json_response(conn, 200)
      assert body["data"]["sms_opt_in"] == true
      assert body["data"]["push_opt_in"] == false

      # Verify persistence
      {:ok, reloaded} =
        Ash.get(MobileCarWash.Accounts.Customer, customer.id, authorize?: false)

      assert reloaded.sms_opt_in == true
      assert reloaded.push_opt_in == false
    end

    test "partial update leaves unspecified fields alone", %{conn: conn} do
      {authed, _customer, _} = register_and_sign_in(conn)

      # Toggle push off first
      patch(authed, ~p"/api/v1/notification_preferences", %{push_opt_in: false})

      # Now update only sms — push_opt_in should stay false
      body =
        authed
        |> patch(~p"/api/v1/notification_preferences", %{sms_opt_in: true})
        |> json_response(200)

      assert body["data"]["sms_opt_in"] == true
      assert body["data"]["push_opt_in"] == false
    end
  end
end
