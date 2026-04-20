defmodule MobileCarWashWeb.Plugs.EnsureSessionId do
  @moduledoc """
  Stamps every inbound browser request with a stable `:session_id` in
  the Phoenix session. Downstream features (cookie consent, attribution,
  behavior tracking) key off this id.

  The id is stored in the Phoenix session cookie — already an essential
  cookie, so no consent required. Format: `sess_<url-safe base64>`.
  """
  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    sid =
      case get_session(conn, :session_id) do
        sid when is_binary(sid) and sid != "" -> sid
        _ -> generate()
      end

    conn
    |> put_session(:session_id, sid)
    |> assign(:session_id, sid)
  end

  defp generate do
    "sess_" <> Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
  end
end
