defmodule MobileCarWash.Scheduling.BlockClosesAtEditTest do
  @moduledoc """
  Admins can shift an AppointmentBlock's `closes_at` — e.g. to close the
  block early before the optimizer's normal midnight run, or to extend
  booking if they decide to keep a window open longer.
  """
  use MobileCarWash.DataCase, async: false

  alias MobileCarWash.Scheduling.{AppointmentBlock, ServiceType}
  alias MobileCarWash.Operations.Technician

  defp create_block do
    {:ok, service} =
      ServiceType
      |> Ash.Changeset.for_create(:create, %{
        name: "Basic",
        slug: "basic_closes_#{:rand.uniform(100_000)}",
        base_price_cents: 5000,
        duration_minutes: 45
      })
      |> Ash.create()

    {:ok, tech} =
      Technician |> Ash.Changeset.for_create(:create, %{name: "T"}) |> Ash.create()

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

    block
  end

  test "admin can update closes_at via the :update action" do
    block = create_block()
    new_close = DateTime.add(block.closes_at, 3600, :second)

    {:ok, updated} =
      block
      |> Ash.Changeset.for_update(:update, %{closes_at: new_close})
      |> Ash.update()

    assert DateTime.compare(updated.closes_at, new_close) == :eq
  end
end
