defmodule MobileCarWash.Booking.SessionCleanupWorker do
  @moduledoc "Oban cron job that cleans up expired booking sessions."
  use Oban.Worker, queue: :default, max_attempts: 1

  @impl true
  def perform(_job) do
    {:ok, count} = MobileCarWash.Booking.SessionCache.cleanup_expired()

    if count > 0 do
      require Logger
      Logger.info("Cleaned up #{count} expired booking sessions")
    end

    :ok
  end
end
