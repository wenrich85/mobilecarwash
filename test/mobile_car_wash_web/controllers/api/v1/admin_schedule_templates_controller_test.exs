defmodule MobileCarWashWeb.Api.V1.AdminScheduleTemplatesControllerTest do
  use MobileCarWashWeb.ApiCase

  alias MobileCarWash.Scheduling.{BlockTemplate, ServiceType}

  describe "GET /api/v1/admin/schedule_templates" do
    test "requires admin role", %{conn: conn} do
      {authed, _customer, _token} = register_and_sign_in(conn)

      conn = get(authed, ~p"/api/v1/admin/schedule_templates")

      assert json_response(conn, 403)
    end

    test "returns schedule templates for native admin schedule management", %{conn: conn} do
      {authed, _admin, _token} = register_and_sign_in_admin(conn)
      service = create_service()
      template = create_template(service)

      conn = get(authed, ~p"/api/v1/admin/schedule_templates")
      body = json_response(conn, 200)

      assert returned = Enum.find(body["data"], &(&1["id"] == template.id))
      assert returned["service_type_id"] == service.id
      assert returned["service_name"] == service.name
      assert returned["day_of_week"] == 2
      assert returned["day_name"] == "Tuesday"
      assert returned["start_hour"] == 9
      assert returned["active"] == true
    end
  end

  describe "POST /api/v1/admin/schedule_templates" do
    test "creates a schedule template", %{conn: conn} do
      {authed, _admin, _token} = register_and_sign_in_admin(conn)
      service = create_service()

      conn =
        post(authed, ~p"/api/v1/admin/schedule_templates", %{
          "service_type_id" => service.id,
          "day_of_week" => 4,
          "start_hour" => 13
        })

      body = json_response(conn, 201)

      assert body["data"]["service_type_id"] == service.id
      assert body["data"]["service_name"] == service.name
      assert body["data"]["day_name"] == "Thursday"
      assert body["data"]["start_hour"] == 13
      assert body["data"]["active"] == true
    end
  end

  describe "POST /api/v1/admin/schedule_templates/:id/toggle" do
    test "toggles a schedule template active state", %{conn: conn} do
      {authed, _admin, _token} = register_and_sign_in_admin(conn)
      service = create_service()
      template = create_template(service)

      conn = post(authed, ~p"/api/v1/admin/schedule_templates/#{template.id}/toggle")
      body = json_response(conn, 200)

      assert body["data"]["id"] == template.id
      assert body["data"]["active"] == false
    end
  end

  describe "DELETE /api/v1/admin/schedule_templates/:id" do
    test "deletes a schedule template", %{conn: conn} do
      {authed, _admin, _token} = register_and_sign_in_admin(conn)
      service = create_service()
      template = create_template(service)

      conn = delete(authed, ~p"/api/v1/admin/schedule_templates/#{template.id}")

      assert json_response(conn, 200) == %{"ok" => true}

      assert {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Query.NotFound{}]}} =
               Ash.get(BlockTemplate, template.id, authorize?: false)
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
      name: "Native Schedule Wash #{unique}",
      slug: "native-schedule-wash-#{unique}",
      description: "Native app schedule service",
      base_price_cents: 9_500,
      duration_minutes: 75,
      active: true,
      window_minutes: 300,
      block_capacity: 3
    })
    |> Ash.create!(authorize?: false)
  end

  defp create_template(service) do
    BlockTemplate
    |> Ash.Changeset.for_create(:create, %{
      service_type_id: service.id,
      day_of_week: 2,
      start_hour: 9,
      active: true
    })
    |> Ash.create!(authorize?: false)
  end
end
