defmodule MobileCarWash.Operations.PhotoCleanupWorker do
  @moduledoc """
  Daily Oban job that deletes photos older than the configured retention period.

  Retention is set via:
    config :mobile_car_wash, :photo_retention_days, 90

  For each expired photo it:
    1. Deletes the file from storage (S3 object or local disk file)
    2. Deletes the database record

  Step 1 is attempted before step 2. If the file delete fails the record is
  left intact and a warning is logged — the job still returns :ok so Oban does
  not retry the entire batch. Individual failures won't block the rest.
  """
  use Oban.Worker, queue: :maintenance, max_attempts: 3

  require Ash.Query
  require Logger

  alias MobileCarWash.Operations.{Photo, PhotoUpload}

  @impl true
  def perform(_job) do
    retention_days = Application.get_env(:mobile_car_wash, :photo_retention_days, 90)
    cutoff = DateTime.add(DateTime.utc_now(), -retention_days * 86_400)

    photos =
      Photo
      |> Ash.Query.filter(inserted_at < ^cutoff)
      |> Ash.read!(authorize?: false)

    {deleted, failed} =
      Enum.reduce(photos, {0, 0}, fn photo, {ok_count, err_count} ->
        case delete_one(photo) do
          :ok ->
            {ok_count + 1, err_count}

          {:error, reason} ->
            Logger.warning("PhotoCleanup: failed to delete photo #{photo.id}: #{inspect(reason)}")
            {ok_count, err_count + 1}
        end
      end)

    Logger.info("PhotoCleanup: deleted #{deleted} photos, #{failed} skipped")
    :ok
  end

  defp delete_one(photo) do
    with :ok <- PhotoUpload.delete_file(photo) do
      case Ash.destroy(photo, authorize?: false) do
        :ok -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end
end
