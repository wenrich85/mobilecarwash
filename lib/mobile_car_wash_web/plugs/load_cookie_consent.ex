defmodule MobileCarWashWeb.Plugs.LoadCookieConsent do
  @moduledoc """
  Reads the current CookieConsent row (if any) for the session and
  assigns it to `conn.assigns[:current_consent]`. The root layout
  uses this assign to decide whether to render the consent banner.

  Must run after `EnsureSessionId` so a session_id is guaranteed.
  """
  @behaviour Plug

  import Plug.Conn

  alias MobileCarWash.Analytics

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    sid = conn.assigns[:session_id] || get_session(conn, :session_id)
    assign(conn, :current_consent, Analytics.consent_for_session(sid))
  end
end
