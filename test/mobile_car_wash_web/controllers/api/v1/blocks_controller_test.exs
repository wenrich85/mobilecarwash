defmodule MobileCarWashWeb.Api.V1.BlocksControllerTest do
  use MobileCarWashWeb.ApiCase

  alias MobileCarWash.Scheduling.{AppointmentBlock, ServiceType}
  alias MobileCarWash.Operations.Technician

  defp create_service do
    ServiceType
    |> Ash.Changeset.for_create(:create, %{
      name: "Basic",
      slug: "basic_api_blk_#{:rand.uniform(100_000)}",
      base_price_cents: 5000,
      duration_minutes: 45
    })
    |> Ash.create!()
  end

  defp create_block(service, hour_offset_days \\ 2) do
    {:ok, tech} =
      Technician |> Ash.Changeset.for_create(:create, %{name: "T"}) |> Ash.create()

    starts_at =
      DateTime.utc_now() |> DateTime.add(hour_offset_days * 86_400, :second) |> DateTime.truncate(:second)

    AppointmentBlock
    |> Ash.Changeset.for_create(:create, %{
      service_type_id: service.id,
      technician_id: tech.id,
      starts_at: starts_at,
      ends_at: DateTime.add(starts_at, 3 * 3600, :second),
      closes_at: DateTime.add(starts_at, -3600, :second),
      capacity: 3,
      status: :open
    })
    |> Ash.create!()
  end

  describe "GET /api/v1/blocks" do
    test "requires authentication", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/blocks")
      assert json_response(conn, 401)
    end

    test "returns open blocks for a given service across a date range", %{conn: conn} do
      {authed, _, _} = register_and_sign_in(conn)
      service = create_service()
      block = create_block(service)

      date = DateTime.to_date(block.starts_at) |> Date.to_iso8601()

      conn =
        get(
          authed,
          ~p"/api/v1/blocks?service_id=#{service.id}&from=#{date}&to=#{date}"
        )

      body = json_response(conn, 200)
      assert [returned] = body["data"]
      assert returned["id"] == block.id
      assert returned["capacity"] == 3
      assert returned["appointment_count"] == 0
      assert returned["spots_left"] == 3
    end

    test "returns 422 when service_id is missing", %{conn: conn} do
      {authed, _, _} = register_and_sign_in(conn)
      conn = get(authed, ~p"/api/v1/blocks?from=2030-01-01&to=2030-01-01")
      assert json_response(conn, 422)
    end
  end
end
