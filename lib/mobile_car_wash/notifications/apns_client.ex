defmodule MobileCarWash.Notifications.ApnsClient do
  @moduledoc """
  Sends APNs push notifications via Pigeon.

  Mockable in tests via `config :mobile_car_wash, :apns_client`. The real
  implementation is gated by `config :mobile_car_wash, :push_enabled` —
  environments without Apple Developer credentials (dev, staging pre-launch)
  short-circuit with `{:ok, :disabled}` so the rest of the pipeline can run
  end-to-end without ever touching Apple's servers.

  Enabling in production requires three things at once:
    1. `APNS_TEAM_ID`, `APNS_KEY_ID`, `APNS_P8_KEY`, `APNS_TOPIC` env vars set
    2. `MobileCarWash.Notifications.ApnsDispatcher` started in the app supervisor
    3. `config :mobile_car_wash, :push_enabled, true` (auto-set in runtime.exs
       when APNS_TEAM_ID is present)
  """

  require Logger

  @type push_response ::
          {:ok, term()}
          | {:error,
             :bad_device_token
             | :unregistered
             | :device_token_not_for_topic
             | :too_many_requests
             | :payload_too_large
             | :expired_provider_token
             | :apns_not_configured
             | term()}

  @doc """
  Sends an APNs notification payload to the given token.

  Returns `{:ok, :disabled}` when push is turned off at the config level —
  callers should treat that as a successful no-op, identical to SMS skipping
  when `sms_opt_in` is false.
  """
  @spec push(String.t(), map(), keyword()) :: push_response()
  def push(token, payload, opts \\ []) do
    case client_module() do
      __MODULE__ -> do_push(token, payload, opts)
      mock -> mock.push(token, payload, opts)
    end
  end

  defp do_push(_token, _payload, _opts) do
    if push_enabled?() do
      # Real delivery wire-up lands once Apple Developer credentials are
      # provisioned and Pigeon.Dispatcher is started in application.ex.
      # Fails loudly so an accidentally-flipped flag is obvious.
      Logger.error(
        "push_enabled: true but ApnsDispatcher is not wired yet. Flip push_enabled: false or finish APNs setup."
      )

      {:error, :apns_not_configured}
    else
      {:ok, :disabled}
    end
  end

  defp push_enabled? do
    Application.get_env(:mobile_car_wash, :push_enabled, false)
  end

  defp client_module do
    Application.get_env(:mobile_car_wash, :apns_client, __MODULE__)
  end
end
