defmodule MobileCarWashWeb.Plugs.CacheBodyReader do
  @moduledoc """
  A `Plug.Parsers` body reader that caches the raw request body for the Stripe
  webhook path.

  `Plug.Parsers` consumes the request body while parsing, so the raw bytes must
  be captured *during* parsing — re-reading the body afterwards yields nothing.
  Stripe signature verification must run over the exact bytes Stripe signed, so
  we stash them in `conn.assigns[:raw_body]` for the webhook endpoint only
  (every other request skips the assign to avoid retaining bodies needlessly).
  """

  @webhook_path "/webhooks/stripe"

  @doc false
  def read_body(conn, opts) do
    {:ok, body, conn} = Plug.Conn.read_body(conn, opts)

    conn =
      if conn.request_path == @webhook_path do
        Plug.Conn.assign(conn, :raw_body, body)
      else
        conn
      end

    {:ok, body, conn}
  end
end
