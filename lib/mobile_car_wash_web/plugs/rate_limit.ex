defmodule MobileCarWashWeb.Plugs.RateLimit do
  @moduledoc """
  Simple ETS-based rate limiter by IP address.
  No external dependencies — uses a named ETS table.
  """
  import Plug.Conn

  @table :rate_limit_buckets

  def init(opts) do
    # Ensure ETS table exists
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:set, :public, :named_table])
    end

    %{
      max: Keyword.get(opts, :max, 10),
      period: Keyword.get(opts, :period, 60_000),
      message: Keyword.get(opts, :message, "Too many requests. Please try again later.")
    }
  end

  def call(conn, opts) do
    ip = conn.remote_ip |> :inet.ntoa() |> to_string()
    key = "#{conn.request_path}:#{ip}"
    now = System.monotonic_time(:millisecond)

    case check_rate(key, now, opts.period, opts.max) do
      :allow ->
        conn

      :deny ->
        require Logger
        Logger.warning("Rate limit exceeded: #{key}")

        conn
        |> put_resp_content_type("text/html")
        |> send_resp(429, rate_limit_html(opts.message))
        |> halt()
    end
  end

  defp check_rate(key, now, period, max) do
    try do
      case :ets.lookup(@table, key) do
        [{^key, count, window_start}] when now - window_start < period ->
          if count >= max do
            :deny
          else
            :ets.update_counter(@table, key, {2, 1})
            :allow
          end

        _ ->
          # New window or expired
          :ets.insert(@table, {key, 1, now})
          :allow
      end
    rescue
      ArgumentError ->
        # Table doesn't exist yet — allow
        :allow
    end
  end

  defp rate_limit_html(message) do
    """
    <!DOCTYPE html>
    <html><head><title>429 Too Many Requests</title></head>
    <body style="font-family:system-ui;text-align:center;padding:4rem">
    <h1>Too Many Requests</h1>
    <p>#{message}</p>
    <p><a href="/">Go back</a></p>
    </body></html>
    """
  end
end
