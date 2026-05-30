defmodule MobileCarWashWeb.Api.V1.AdminSettingsControllerTest do
  use MobileCarWashWeb.ConnCase, async: false

  import MobileCarWashWeb.ApiCase

  alias MobileCarWash.Scheduling.{BlockedDate, SchedulingSettings}

  describe "GET /api/v1/admin/settings" do
    test "requires admin role", %{conn: conn} do
      {authed, _customer, _token} = register_and_sign_in(conn)

      conn = get(authed, ~p"/api/v1/admin/settings")

      assert json_response(conn, 403)
    end

    test "returns scheduling settings and blocked dates for native admin settings", %{conn: conn} do
      {authed, _admin, _token} = register_and_sign_in_admin(conn)
      {:ok, settings} = SchedulingSettings.update(%{max_intra_block_drive_minutes: 37})
      blocked = create_blocked_date(~D[2031-02-03], "Team offsite")

      conn = get(authed, ~p"/api/v1/admin/settings")
      body = json_response(conn, 200)

      assert body["data"]["scheduling"]["max_intra_block_drive_minutes"] ==
               settings.max_intra_block_drive_minutes

      assert returned = Enum.find(body["data"]["blocked_dates"], &(&1["id"] == blocked.id))
      assert returned["date"] == "2031-02-03"
      assert returned["reason"] == "Team offsite"
    end
  end

  describe "PATCH /api/v1/admin/settings/scheduling" do
    test "updates scheduling settings", %{conn: conn} do
      {authed, _admin, _token} = register_and_sign_in_admin(conn)

      conn =
        patch(authed, ~p"/api/v1/admin/settings/scheduling", %{
          "max_intra_block_drive_minutes" => 42
        })

      body = json_response(conn, 200)

      assert body["data"]["max_intra_block_drive_minutes"] == 42
      assert SchedulingSettings.get().max_intra_block_drive_minutes == 42
    end
  end

  describe "POST /api/v1/admin/settings/blocked_dates" do
    test "creates a blocked date", %{conn: conn} do
      {authed, _admin, _token} = register_and_sign_in_admin(conn)

      conn =
        post(authed, ~p"/api/v1/admin/settings/blocked_dates", %{
          "date" => "2031-04-05",
          "reason" => "Maintenance"
        })

      body = json_response(conn, 201)

      assert body["data"]["date"] == "2031-04-05"
      assert body["data"]["reason"] == "Maintenance"
    end
  end

  describe "DELETE /api/v1/admin/settings/blocked_dates/:id" do
    test "deletes a blocked date", %{conn: conn} do
      {authed, _admin, _token} = register_and_sign_in_admin(conn)
      blocked = create_blocked_date(~D[2031-05-06], "Cleanup")

      conn = delete(authed, ~p"/api/v1/admin/settings/blocked_dates/#{blocked.id}")

      assert response(conn, 204) == ""

      assert {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Query.NotFound{}]}} =
               Ash.get(BlockedDate, blocked.id)
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

  defp create_blocked_date(date, reason) do
    BlockedDate
    |> Ash.Changeset.for_create(:create, %{date: date, reason: reason})
    |> Ash.create!(authorize?: false)
  end
end
