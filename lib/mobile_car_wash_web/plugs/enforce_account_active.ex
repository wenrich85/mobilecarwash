defmodule MobileCarWashWeb.Plugs.EnforceAccountActive do
  @moduledoc """
  Soft-delete gate. After the auth layer has loaded
  `current_user` / `current_customer`, this plug checks their
  `disabled_at`. If set, it:

    * Clears the session and halts with a redirect to `/sign-in` for
      browser requests (with a flash explaining why).
    * Returns `401 {"error": "account_disabled"}` for JSON / API
      requests so mobile clients can handle re-auth and messaging.

  Runs AFTER `load_from_session` / `load_from_bearer` in the pipeline.
  No-ops when no user is assigned, so the cost on public pages is a
  single map lookup.
  """
  import Plug.Conn
  import Phoenix.Controller

  use MobileCarWashWeb, :verified_routes

  def init(opts), do: opts

  def call(conn, _opts) do
    user = conn.assigns[:current_user] || conn.assigns[:current_customer]

    case user do
      %{disabled_at: %DateTime{}} ->
        block(conn)

      _ ->
        conn
    end
  end

  defp block(conn) do
    if json_request?(conn) do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(401, ~s({"error":"account_disabled"}))
      |> halt()
    else
      conn
      |> clear_session()
      |> put_flash(
        :error,
        "Your account has been disabled. Contact support if you believe this is in error."
      )
      |> redirect(to: ~p"/sign-in")
      |> halt()
    end
  end

  defp json_request?(conn) do
    case get_req_header(conn, "accept") do
      [accept | _] -> String.contains?(accept, "application/json")
      _ -> String.starts_with?(conn.request_path, "/api/")
    end
  end
end
