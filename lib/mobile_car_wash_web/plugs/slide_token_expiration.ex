defmodule MobileCarWashWeb.Plugs.SlideTokenExpiration do
  @moduledoc """
  Sliding expiration / "soft" token rotation for authenticated requests.

  Runs after the session/bearer auth step. If the current user's token
  has less than `threshold_seconds` remaining (default 48h on a 7-day
  life), mints a new full-lifetime token and attaches it two ways:

    * API callers (Bearer auth): returned as an `x-refresh-token`
      response header. Clients save it and swap over on the next
      request.
    * Browser callers (session): written back into the session as
      `customer_token` so the cookie gets updated automatically when
      Plug.Session writes out.

  The old token is left alone — it expires on its own timeline. That
  keeps rotation "soft" and avoids races when a user has two tabs /
  devices making concurrent calls.

  Closes SECURITY_AUDIT_REPORT MEDIUM #5.
  """
  import Plug.Conn

  require Logger

  @default_threshold_seconds 48 * 3600

  @type opts :: [threshold_seconds: non_neg_integer()]

  @spec init(opts) :: map
  def init(opts) do
    %{
      threshold_seconds:
        Keyword.get(
          opts,
          :threshold_seconds,
          Application.get_env(
            :mobile_car_wash,
            :token_refresh_threshold_seconds,
            @default_threshold_seconds
          )
        )
    }
  end

  @spec call(Plug.Conn.t(), map) :: Plug.Conn.t()
  def call(conn, opts) do
    with user when not is_nil(user) <- current_user(conn),
         {:ok, token, exp} <- fetch_current_token(conn),
         true <- seconds_remaining(exp) <= opts.threshold_seconds,
         {:ok, new_token, _claims} <-
           AshAuthentication.Jwt.token_for_user(user, %{}, resource: user.__struct__) do
      conn
      |> put_resp_header("x-refresh-token", new_token)
      |> maybe_update_session(new_token, token)
    else
      _ -> conn
    end
  end

  defp current_user(conn), do: conn.assigns[:current_user] || conn.assigns[:current_customer]

  defp fetch_current_token(conn) do
    token_string =
      case get_req_header(conn, "authorization") do
        ["Bearer " <> token] -> token
        _ -> session_token(conn)
      end

    with token when is_binary(token) <- token_string,
         {:ok, %{"exp" => exp}} <- AshAuthentication.Jwt.peek(token) do
      {:ok, token, exp}
    else
      _ -> :error
    end
  end

  # Only attempts to read the session if one has been fetched. Plug.Conn
  # raises if you call get_session/2 before fetch_session/2, so we gate
  # on private[:plug_session].
  defp session_token(conn) do
    case conn.private[:plug_session] do
      %{"customer_token" => token} when is_binary(token) -> token
      _ -> nil
    end
  end

  defp seconds_remaining(exp) do
    exp - System.system_time(:second)
  end

  defp maybe_update_session(conn, new_token, old_token) do
    case conn.private[:plug_session] do
      # Only rewrite the session if the old token was in it (i.e. this is
      # a browser request). API callers use the header path and shouldn't
      # have their session cookie touched.
      %{"customer_token" => ^old_token} ->
        put_session(conn, "customer_token", new_token)

      _ ->
        conn
    end
  end
end
