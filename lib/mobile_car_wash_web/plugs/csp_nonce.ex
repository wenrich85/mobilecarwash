defmodule MobileCarWashWeb.Plugs.CspNonce do
  @moduledoc """
  Generates a per-request CSP nonce, assigns it to the conn for the root layout,
  and stores it in the session so LiveView `on_mount` hooks can hydrate the
  same value into the socket — guaranteeing the nonce in a LiveView-rendered
  inline `<script nonce=...>` matches the one declared in the CSP header.

  Must run after `:fetch_session` and before the security-headers plug.
  """
  import Plug.Conn

  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    nonce = :crypto.strong_rand_bytes(18) |> Base.url_encode64(padding: false)

    conn
    |> assign(:csp_nonce, nonce)
    |> put_session(:csp_nonce, nonce)
  end
end
