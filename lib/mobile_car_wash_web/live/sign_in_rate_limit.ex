defmodule MobileCarWashWeb.SignInRateLimit do
  @moduledoc """
  LiveView on_mount hook that rate-limits access to the sign-in page.

  Uses the same ETS table as the RateLimit plug. Limits sign-in page
  loads per IP to prevent automated credential stuffing. Max 15 loads
  per minute before the socket is halted.

  The IP is read from the LiveView peer data (requires :peer_data in
  connect_info). Falls back gracefully if peer data is unavailable.
  """
  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 2]

  @table :rate_limit_buckets
  @max 15
  @period 60_000

  def on_mount(:limit_sign_in, _params, _session, socket) do
    ip = get_peer_ip(socket)
    key = "sign_in:#{ip}"
    now = System.monotonic_time(:millisecond)

    case check_rate(key, now) do
      :allow ->
        {:cont, socket}

      :deny ->
        require Logger
        Logger.warning("Sign-in rate limit exceeded from #{ip}")

        {:halt,
         socket
         |> put_flash(:error, "Too many sign-in attempts. Please wait a minute and try again.")
         |> redirect(to: "/")}
    end
  end

  defp get_peer_ip(socket) do
    case get_connect_info(socket, :peer_data) do
      %{address: ip} -> ip |> :inet.ntoa() |> to_string()
      _ -> "unknown"
    end
  end

  defp check_rate(key, now) do
    try do
      ensure_table()

      case :ets.lookup(@table, key) do
        [{^key, count, window_start}] when now - window_start < @period ->
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
