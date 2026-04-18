defmodule MobileCarWashWeb.Admin.BlocksLiveTest do
  @moduledoc """
  Tests for the admin Blocks LiveView — listing upcoming appointment blocks,
  triggering optimization, cancelling.
  """
  use MobileCarWashWeb.ConnCase, async: true

  alias MobileCarWash.Scheduling.{AppointmentBlock, ServiceType}
  alias MobileCarWash.Operations.Technician

  describe "auth guard" do
    test "non-authenticated user is redirected to sign-in", %{conn: conn} do
      conn = get(conn, ~p"/admin/blocks")
      assert redirected_to(conn) == "/sign-in"
    end
  end

  describe "cancelling a block" do
    test "sets status to :cancelled" do
      {:ok, service} =
        ServiceType
        |> Ash.Changeset.for_create(:create, %{
          name: "Basic Wash",
          slug: "basic_wash_cancel_#{:rand.uniform(100_000)}",
          base_price_cents: 5000,
          duration_minutes: 45
        })
        |> Ash.create()

      {:ok, tech} =
        Technician
        |> Ash.Changeset.for_create(:create, %{name: "Cancel Tech"})
        |> Ash.create()

      starts_at =
        DateTime.utc_now() |> DateTime.add(2 * 86_400, :second) |> DateTime.truncate(:second)

      {:ok, block} =
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
        |> Ash.create()

      {:ok, cancelled} =
        block
        |> Ash.Changeset.for_update(:update, %{status: :cancelled})
        |> Ash.update()

      assert cancelled.status == :cancelled
    end
  end
end
