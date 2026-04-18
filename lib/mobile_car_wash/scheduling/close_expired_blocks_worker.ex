defmodule MobileCarWash.Scheduling.CloseExpiredBlocksWorker do
  @moduledoc """
  Oban cron worker that runs at midnight and closes every `:open` block whose
  `closes_at` has passed. Each closed block is optimized immediately so
  customers get their confirmed arrival times first thing in the morning.
  """
  use Oban.Worker, queue: :default, max_attempts: 1

  alias MobileCarWash.Scheduling.{AppointmentBlock, BlockOptimizer}

  require Ash.Query
  require Logger

  @impl Oban.Worker
  def perform(_job) do
    now = DateTime.utc_now()

    expired =
      AppointmentBlock
      |> Ash.Query.filter(status == :open and closes_at <= ^now)
      |> Ash.read!()

    Enum.each(expired, fn block ->
      case BlockOptimizer.close_and_optimize(block.id) do
        {:ok, _} ->
          Logger.info("Closed + optimized block #{block.id}")

        {:error, reason} ->
          Logger.warning("Failed to close block #{block.id}: #{inspect(reason)}")
      end
    end)

    :ok
  end
end
