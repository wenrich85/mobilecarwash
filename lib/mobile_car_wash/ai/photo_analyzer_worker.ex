defmodule MobileCarWash.AI.PhotoAnalyzerWorker do
  @moduledoc """
  Oban worker that runs the vision model against a single Photo row.

  Enqueued from `PhotoUpload.save_file/5` for customer-uploaded
  `:problem_area` photos. Delegates to `PhotoAnalyzer.analyze/1` so
  the feature-flag + idempotency logic lives in one place.

  Returns `{:error, reason}` on API failure so Oban can retry with
  backoff; permanent configuration errors also retry but will error
  the same way each time until the flag / key is fixed.
  """
  use Oban.Worker, queue: :notifications, max_attempts: 3

  alias MobileCarWash.AI.PhotoAnalyzer

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"photo_id" => photo_id}}) do
    PhotoAnalyzer.analyze(photo_id)
  end
end
