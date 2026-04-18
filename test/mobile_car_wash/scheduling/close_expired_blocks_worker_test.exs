defmodule MobileCarWash.Scheduling.CloseExpiredBlocksWorkerTest do
  @moduledoc """
  Oban worker that runs at midnight and closes (and optimizes) every block
  whose `closes_at` has passed and is still `:open`.
  """
  use MobileCarWash.DataCase, async: false
  use Oban.Testing, repo: MobileCarWash.Repo

  alias MobileCarWash.Scheduling.{AppointmentBlock, CloseExpiredBlocksWorker, ServiceType}
  alias MobileCarWash.Operations.Technician

  defp create_service do
    ServiceType
    |> Ash.Changeset.for_create(:create, %{
      name: "Basic Wash",
      slug: "basic_wash_cron_#{:rand.uniform(100_000)}",
      base_price_cents: 5000,
      duration_minutes: 45
    })
    |> Ash.create!()
  end

  defp create_technician do
    Technician
    |> Ash.Changeset.for_create(:create, %{name: "Cron Tech"})
    |> Ash.create!()
  end

  defp create_block(service, tech, closes_at, starts_at) do
    ends_at = DateTime.add(starts_at, 3 * 3600, :second)

    AppointmentBlock
    |> Ash.Changeset.for_create(:create, %{
      service_type_id: service.id,
      technician_id: tech.id,
      starts_at: starts_at,
      ends_at: ends_at,
      closes_at: closes_at,
      capacity: 3,
      status: :open
    })
    |> Ash.create!()
  end

  test "closes and optimizes every expired :open block" do
    service = create_service()
    tech = create_technician()

    # Expired (closes_at in the past)
    past_close =
      DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.truncate(:second)

    past_start =
      DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second)

    expired = create_block(service, tech, past_close, past_start)

    # Still open (closes_at in the future)
    future_close =
      DateTime.utc_now() |> DateTime.add(86_400, :second) |> DateTime.truncate(:second)

    future_start =
      DateTime.utc_now() |> DateTime.add(2 * 86_400, :second) |> DateTime.truncate(:second)

    still_open = create_block(service, tech, future_close, future_start)

    assert :ok = perform_job(CloseExpiredBlocksWorker, %{})

    reloaded_expired = Ash.get!(AppointmentBlock, expired.id)
    reloaded_open = Ash.get!(AppointmentBlock, still_open.id)

    assert reloaded_expired.status == :scheduled
    assert reloaded_open.status == :open
  end
end
