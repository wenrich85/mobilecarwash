defmodule MobileCarWash.Marketing.Social.Adapter do
  @moduledoc """
  Behaviour every social-media adapter implements. Real implementations
  (Meta Graph, X API, Buffer, TikTok) arrive in later phases and
  slot in by config.

  Phase 3A ships only the `LogAdapter` default — it doesn't touch
  any network, just logs what would happen and returns a fake id.
  That's enough to exercise the composer + publish worker end-to-end
  today without any API credentials / approvals.
  """

  alias MobileCarWash.Marketing.Post

  @type channel_slug :: String.t()
  @type external_id :: String.t()

  @doc """
  Publish `post` to the given `channel_slug`. Returns the platform's
  post id on success so the Post row can record per-channel external
  ids.
  """
  @callback publish(Post.t(), channel_slug()) ::
              {:ok, external_id()} | {:error, atom() | term()}

  @doc """
  List of channel slugs this adapter handles. The Publisher uses this
  to route each channel on a Post to the right adapter.
  """
  @callback supported_channels() :: [channel_slug()]
end
