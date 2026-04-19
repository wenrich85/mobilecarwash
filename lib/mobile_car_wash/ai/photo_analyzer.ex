defmodule MobileCarWash.AI.PhotoAnalyzer do
  @moduledoc """
  Orchestrates vision-model tagging for a single Photo row:
    1. Loads the photo (short-circuits if already processed).
    2. Resolves a URL the vision model can fetch (presigned S3 URL or
       local `/uploads/...` path — local only works if the tests use
       the mock, which they do).
    3. Calls `VisionClient.classify/2` with the prompt from `Prompts.system/0`.
    4. Persists the structured response via `Photo.apply_ai_tags`.

  Feature-flag gated via `config :mobile_car_wash, :ai_photo_analysis,
  enabled: bool`. When disabled, analyze/1 no-ops so Oban workers that
  enqueue against it don't do any work.
  """

  alias MobileCarWash.AI.{Prompts, VisionClient}
  alias MobileCarWash.Operations.{Photo, PhotoUpload}
  alias Phoenix.PubSub

  require Logger

  @pubsub MobileCarWash.PubSub

  @doc "Subscribe to AI-tag updates for a single photo."
  def subscribe(photo_id), do: PubSub.subscribe(@pubsub, "photo:#{photo_id}:ai")

  @doc """
  Runs the vision model against `photo_id`. Returns:
    * `:ok` — tags applied, or the feature is off, or the photo is already
      processed (idempotent).
    * `{:error, reason}` — the vision client erred or the photo couldn't
      be loaded. Caller (Oban worker) should retry.
  """
  @spec analyze(String.t()) :: :ok | {:error, term()}
  def analyze(photo_id) do
    cond do
      not enabled?() ->
        :ok

      true ->
        with {:ok, photo} <- load_photo(photo_id),
             :not_processed <- already_processed?(photo),
             url when is_binary(url) <- PhotoUpload.url_for(photo),
             {:ok, tags} <- VisionClient.classify(url, Prompts.system()) do
          apply_tags(photo, tags)
        else
          :already_processed -> :ok
          {:error, _} = err -> err
        end
    end
  end

  defp enabled? do
    Application.get_env(:mobile_car_wash, :ai_photo_analysis, [])
    |> Keyword.get(:enabled, false)
  end

  defp load_photo(photo_id) do
    case Ash.get(Photo, photo_id, authorize?: false) do
      {:ok, photo} -> {:ok, photo}
      {:error, reason} -> {:error, reason}
    end
  end

  defp already_processed?(%Photo{ai_processed_at: nil}), do: :not_processed
  defp already_processed?(_), do: :already_processed

  defp apply_tags(photo, tags) do
    case photo
         |> Ash.Changeset.for_update(:apply_ai_tags, %{ai_tags: tags})
         |> Ash.update(authorize?: false) do
      {:ok, updated} ->
        PubSub.broadcast(@pubsub, "photo:#{updated.id}:ai", {:ai_tags, updated})
        :ok

      {:error, reason} ->
        Logger.error("Failed to persist AI tags for #{photo.id}: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
