defmodule MobileCarWash.Scheduling.DailyBlockGeneratorWorker do
  @moduledoc """
  Oban cron worker that creates AppointmentBlocks for the next `@horizon_days`
  days. Runs each morning so the booking UI always has a rolling window of
  available slots. Idempotent — blocks already generated are left alone.
  """
  use Oban.Worker, queue: :default, max_attempts: 1

  alias MobileCarWash.Scheduling.BlockGenerator
  alias MobileCarWash.Operations.Technician

  require Ash.Query
  require Logger

  @horizon_days 14

  @impl Oban.Worker
  def perform(_job) do
    case default_technician() do
      nil ->
        Logger.warning("DailyBlockGeneratorWorker: no active technician, skipping")
        :ok

      tech ->
        BlockGenerator.generate_ahead(@horizon_days, technician_id: tech.id)
        Logger.info("DailyBlockGeneratorWorker: generated blocks for next #{@horizon_days} days")
        :ok
    end
  end

  defp default_technician do
    Technician
    |> Ash.Query.filter(active == true)
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.Query.limit(1)
    |> Ash.read!()
    |> List.first()
  end
end
