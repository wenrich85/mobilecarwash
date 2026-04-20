defmodule MobileCarWash.Marketing.Social.LogAdapter do
  @moduledoc """
  Phase 3A default SocialAdapter: logs what would be published and
  returns a fake external id. No network calls, no credentials
  required. Lets the composer + publish flow work end-to-end before
  any API approvals land.

  Handles any channel slug — we register it for every platform in
  `channels_to_adapters/0` so unconfigured channels fall through
  harmlessly to the logger.
  """
  @behaviour MobileCarWash.Marketing.Social.Adapter

  require Logger

  alias MobileCarWash.Marketing.Post

  @impl true
  def publish(%Post{} = post, channel) do
    id =
      "log_#{channel}_#{System.unique_integer([:positive])}_#{System.os_time(:second)}"

    Logger.info(
      "[SocialAdapter.Log] would publish to #{channel}: #{inspect(%{title: post.title, body_length: String.length(post.body || ""), image_url: post.image_url, target_personas: post.persona_ids})}"
    )

    {:ok, id}
  end

  @impl true
  def supported_channels do
    ~w(log meta x tiktok linkedin buffer google)
  end
end
