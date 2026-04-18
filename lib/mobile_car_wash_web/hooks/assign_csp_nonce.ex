defmodule MobileCarWashWeb.AssignCspNonce do
  @moduledoc """
  LiveView `on_mount` hook that copies the per-request CSP nonce from the
  session into the socket assigns as `:csp_nonce`, so LiveView templates can
  render `<script nonce={@csp_nonce}>` with the same value declared in the
  CSP response header.

  Paired with `MobileCarWashWeb.Plugs.CspNonce`, which writes the nonce to
  the session during the initial HTTP render.
  """

  import Phoenix.Component, only: [assign: 3]

  def on_mount(:default, _params, session, socket) do
    {:cont, assign(socket, :csp_nonce, Map.get(session, "csp_nonce"))}
  end
end
