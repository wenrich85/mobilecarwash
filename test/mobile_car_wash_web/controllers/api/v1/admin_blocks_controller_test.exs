defmodule MobileCarWashWeb.Api.V1.AdminBlocksControllerTest do
  use MobileCarWashWeb.ApiCase

  alias MobileCarWash.Operations.Technician
  alias MobileCarWash.Scheduling.{AppointmentBlock, ServiceType}

  describe "GET /api/v1/admin/blocks" do
    test "requires admin role", %{conn: conn} do
      {authed, _customer, _token} = register_and_sign_in(conn)

      conn = get(authed, ~p"/api/v1/admin/blocks")

      assert json_response(conn, 403)
    end

    test "returns upcoming blocks for native admin block management", %{conn: conn} do
      {authed, _admin, _token} = register_and_sign_in_admin(conn)
      service = create_service()
      technician = create_technician()
      upcoming = create_block(service, technician, 2)
      _past = create_block(service, technician, -2)

      conn = get(authed, ~p"/api/v1/admin/blocks")
      body = json_response(conn, 200)

      assert returned = Enum.find(body["data"], &(&1["id"] == upcoming.id))
      refute Enum.any?(body["data"], &(&1["starts_at"] < DateTime.to_iso8601(DateTime.utc_now())))
      assert returned["service_type_id"] == service.id
      assert returned["service_name"] == service.name
      assert returned["technician_id"] == technician.id
      assert returned["technician_name"] == technician.name
      assert returned["capacity"] == 4
      assert returned["appointment_count"] == 0
      assert returned["spots_left"] == 4
      assert returned["status"] == "open"
    end
  end

  describe "POST /api/v1/admin/blocks/generate" do
    test "generates upcoming blocks for a technician", %{conn: conn} do
      {authed, _admin, _token} = register_and_sign_in_admin(conn)
      service = create_service()
      technician = create_technician()

      conn =
        post(authed, ~p"/api/v1/admin/blocks/generate", %{
          "technician_id" => technician.id
        })

      body = json_response(conn, 200)

      assert Enum.any?(body["data"], fn block ->
               block["service_type_id"] == service.id and
                 block["technician_id"] == technician.id
             end)
    end
  end

  describe "POST /api/v1/admin/blocks/:id/optimize" do
    test "closes and optimizes a block", %{conn: conn} do
      {authed, _admin, _token} = register_and_sign_in_admin(conn)
      service = create_service()
      technician = create_technician()
      block = create_block(service, technician, 2)

      conn = post(authed, ~p"/api/v1/admin/blocks/#{block.id}/optimize")
      body = json_response(conn, 200)

      assert body["data"]["id"] == block.id
      assert body["data"]["status"] == "scheduled"
    end
  end

  describe "POST /api/v1/admin/blocks/:id/cancel" do
    test "cancels a block", %{conn: conn} do
      {authed, _admin, _token} = register_and_sign_in_admin(conn)
      service = create_service()
      technician = create_technician()
      block = create_block(service, technician, 2)

      conn = post(authed, ~p"/api/v1/admin/blocks/#{block.id}/cancel")
      body = json_response(conn, 200)

      assert body["data"]["id"] == block.id
      assert body["data"]["status"] == "cancelled"
    end
  end

  describe "PATCH /api/v1/admin/blocks/:id/close" do
    test "updates the block close time", %{conn: conn} do
      {authed, _admin, _token} = register_and_sign_in_admin(conn)
      service = create_service()
      technician = create_technician()
      block = create_block(service, technician, 2)
      closes_at = DateTime.add(block.starts_at, -2, :hour)

      conn =
        patch(authed, ~p"/api/v1/admin/blocks/#{block.id}/close", %{
          "closes_at" => DateTime.to_iso8601(closes_at)
        })

      body = json_response(conn, 200)

      assert body["data"]["id"] == block.id
      assert body["data"]["closes_at"] == DateTime.to_iso8601(closes_at)
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
      name: "Native Block Wash #{unique}",
      slug: "native-block-wash-#{unique}",
      description: "Native app block service",
      base_price_cents: 8_500,
      duration_minutes: 60,
      active: true,
      window_minutes: 240,
      block_capacity: 4
    })
    |> Ash.create!(authorize?: false)
  end

  defp create_technician do
    Technician
    |> Ash.Changeset.for_create(:create, %{
      name: "Native Blocks Tech",
      active: true,
      status: :available
    })
    |> Ash.create!(authorize?: false)
  end

  defp create_block(service, technician, day_offset) do
    starts_at =
      DateTime.utc_now()
      |> DateTime.add(day_offset, :day)
      |> DateTime.truncate(:second)

    AppointmentBlock
    |> Ash.Changeset.for_create(:create, %{
      service_type_id: service.id,
      technician_id: technician.id,
      starts_at: starts_at,
      ends_at: DateTime.add(starts_at, 4, :hour),
      closes_at: DateTime.add(starts_at, -1, :hour),
      capacity: 4,
      status: :open
    })
    |> Ash.create!(authorize?: false)
  end
end
