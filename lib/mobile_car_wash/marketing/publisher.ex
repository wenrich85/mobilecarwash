defmodule MobileCarWash.Marketing.Publisher do
  @moduledoc """
  Fan-out module that takes a Post and publishes it to every channel
  in its `channels` list, routing each to the configured SocialAdapter.

  Phase 3A routes every channel through `LogAdapter` (no network).
  Later phases register real adapters per channel via
  `:channel_adapters` app env:

      config :mobile_car_wash, :channel_adapters,
        meta: MobileCarWash.Marketing.Social.MetaAdapter,
        x: MobileCarWash.Marketing.Social.XAdapter
  """
  require Logger

  alias MobileCarWash.Marketing.Post
  alias MobileCarWash.Marketing.Social.LogAdapter

  @doc """
  Publish the post identified by `id`. Returns the updated Post on
  success, an error tuple on failure.
  """
  @spec publish(binary()) ::
          {:ok, Post.t()} | {:error, :not_found | :already_published | :no_channels | term()}
  def publish(id) when is_binary(id) do
    case Ash.get(Post, id, authorize?: false) do
      {:ok, %Post{status: :published}} -> {:error, :already_published}
      {:ok, %Post{channels: []}} -> {:error, :no_channels}
      {:ok, post} -> do_publish(post)
      _ -> {:error, :not_found}
    end
  end

  defp do_publish(%Post{channels: channels} = post) do
    {successes, failures} =
      Enum.reduce(channels, {%{}, []}, fn channel, {ok, errs} ->
        case adapter_for(channel).publish(post, channel) do
          {:ok, external_id} ->
            {Map.put(ok, channel, external_id), errs}

          {:error, reason} ->
            {ok, [{channel, reason} | errs]}
        end
      end)

    cond do
      failures != [] and successes == %{} ->
        mark_failed(post, format_failures(failures))

      true ->
        mark_published(post, successes, failures)
    end
  end

  defp mark_published(post, external_ids, failures) do
    result =
      post
      |> Ash.Changeset.for_update(:mark_published, %{external_ids: external_ids})
      |> Ash.update(authorize?: false)

    if failures != [] do
      Logger.warning("Partial publish for #{post.id}: #{format_failures(failures)}")
    end

    result
  end

  defp mark_failed(post, error_message) do
    {:ok, _} =
      post
      |> Ash.Changeset.for_update(:mark_failed, %{error_message: error_message})
      |> Ash.update(authorize?: false)

    {:error, error_message}
  end

  defp adapter_for(channel) do
    case Application.get_env(:mobile_car_wash, :channel_adapters, %{}) do
      %{} = map -> Map.get(map, channel, LogAdapter)
      list when is_list(list) -> Keyword.get(list, String.to_atom(channel), LogAdapter)
      _ -> LogAdapter
    end
  end

  defp format_failures(failures) do
    failures
    |> Enum.map(fn {ch, reason} -> "#{ch}: #{inspect(reason)}" end)
    |> Enum.join("; ")
  end
end
