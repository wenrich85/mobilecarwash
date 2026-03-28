defmodule MobileCarWashWeb.Plugs.RawBody do
  @moduledoc """
  Plug that caches the raw request body for webhook signature verification.
  Stripe webhooks require the raw body to verify the signature.
  """

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    {:ok, body, conn} = Plug.Conn.read_body(conn)
    Plug.Conn.assign(conn, :raw_body, body)
  end
end
