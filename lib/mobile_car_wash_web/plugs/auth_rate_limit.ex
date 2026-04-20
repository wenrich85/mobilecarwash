defmodule MobileCarWashWeb.Plugs.AuthRateLimit do
  @moduledoc """
  Per-IP rate limiter for authentication POST endpoints. Designed to sit
  in both the `:browser` and `:api` pipelines and short-circuit when the
  current request is one of the sensitive auth routes. Other requests
  pass through untouched.

  Closes SECURITY_AUDIT_REPORT HIGH #3: the existing `SignInRateLimit`
  on_mount hook only gates the sign-in LiveView mount; the POST endpoints
  that actually accept credentials (`/auth/customer/password/sign_in`,
  the AshAuthentication register / reset routes, and `/api/v1/auth/*`)
  were unrestricted.

  ETS-backed, same `:rate_limit_buckets` table as the other limiters so
  one connection's bucket is visible to every path that uses it. The
  default window is 60 seconds with a cap of 10 requests per IP per
  bucket.

  Each auth path gets its OWN bucket (keyed on path + IP) so rate-limiting
  one doesn't throttle another. A user hitting both sign-in and register
  still has two separate 10-per-minute budgets.
  """
  import Plug.Conn

  @table :rate_limit_buckets
  @max 10
  @period_ms 60_000

  # Paths we care about. Matched as prefixes so AshAuthentication's
  # subpaths (confirm, reset, etc.) pick up the same guard automatically.
  @auth_prefixes [
    "/auth/customer/password/sign_in",
    "/auth/customer/password/register",
    "/auth/customer/password/reset",
    "/api/v1/auth/sign_in",
    "/api/v1/auth/register"
  ]

  def init(opts), do: opts

  def call(%{method: "POST"} = conn, _opts) do
    if auth_path?(conn.request_path) do
      check(conn)
    else
      conn
    end
  end

  def call(conn, _opts), do: conn

  # ---

  defp auth_path?(path), do: Enum.any?(@auth_prefixes, &String.starts_with?(path, &1))

  defp check(conn) do
    ensure_table()
    ip = conn.remote_ip |> :inet.ntoa() |> to_string()
    # Distinct bucket per endpoint so sign-in attempts don't eat into the
    # register budget (or vice versa).
    key = "auth:#{conn.request_path}:#{ip}"
    now = System.monotonic_time(:millisecond)

    case rate_check(key, now) do
      :allow ->
        conn

      :deny ->
        require Logger
        Logger.warning("Auth rate limit exceeded: #{key}")

        conn
        |> put_resp_header("retry-after", "60")
        |> put_resp_content_type("application/json")
        |> send_resp(
          429,
          ~s({"error":"rate_limited","message":"Too many auth attempts. Please wait a minute and try again."})
        )
        |> halt()
    end
  end

  defp rate_check(key, now) do
    try do
      case :ets.lookup(@table, key) do
        [{^key, count, window_start}] when now - window_start < @period_ms ->
          if count >= @max do
            :deny
          else
            :ets.update_counter(@table, key, {2, 1})
            :allow
          end

        _ ->
          :ets.insert(@table, {key, 1, now})
          :allow
      end
    rescue
      _ -> :allow
    end
  end

  defp ensure_table do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:set, :public, :named_table])
    end
  end
end
