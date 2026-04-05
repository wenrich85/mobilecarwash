defmodule MobileCarWash.Notifications.TwilioClient do
  @moduledoc """
  Sends SMS via the Twilio REST API using Req.

  Mockable in tests via `config :mobile_car_wash, :twilio_client`.
  """

  require Logger

  @doc """
  Sends an SMS to the given phone number.

  Returns `{:ok, message_sid}` on success or `{:error, reason}` on failure.
  """
  def send_sms(to, body) do
    case client_module() do
      __MODULE__ -> do_send_sms(to, body)
      mock -> mock.send_sms(to, body)
    end
  end

  defp do_send_sms(to, body) do
    config = Application.get_env(:mobile_car_wash, :twilio)

    with {:ok, account_sid} <- fetch_config(config, :account_sid),
         {:ok, auth_token} <- fetch_config(config, :auth_token),
         {:ok, from_number} <- fetch_config(config, :from_number) do
      url = "https://api.twilio.com/2010-04-01/Accounts/#{account_sid}/Messages.json"

      case Req.post(url,
             auth: {:basic, "#{account_sid}:#{auth_token}"},
             form: [To: to, From: from_number, Body: body]
           ) do
        {:ok, %{status: 201, body: %{"sid" => sid}}} ->
          Logger.info("SMS sent to #{to}: #{sid}")
          {:ok, sid}

        {:ok, %{status: status, body: resp_body}} ->
          Logger.error("Twilio error #{status}: #{inspect(resp_body)}")
          {:error, {:twilio_error, status, resp_body}}

        {:error, reason} ->
          Logger.error("Twilio request failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  defp fetch_config(nil, _key), do: {:error, :sms_not_configured}
  defp fetch_config(config, key) do
    case Keyword.get(config, key) do
      nil -> {:error, :sms_not_configured}
      val -> {:ok, val}
    end
  end

  defp client_module do
    Application.get_env(:mobile_car_wash, :twilio_client, __MODULE__)
  end
end
