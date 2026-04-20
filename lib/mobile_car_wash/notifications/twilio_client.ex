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

  @doc """
  Normalizes a phone number to E.164 format (`+15125551234`).

  Twilio rejects anything else, but Customer.phone accepts US-style
  formats with dashes / parens / spaces, and an operator might paste
  the Twilio `From` number without the `+1`. This is the one normalizer
  to rule them all.

  Returns `nil` for empty / unparseable / too-short input so callers
  can bail without sending.
  """
  @spec to_e164(String.t() | nil) :: String.t() | nil
  def to_e164(nil), do: nil

  def to_e164(raw) when is_binary(raw) do
    digits = String.replace(raw, ~r/[^\d]/, "")

    cond do
      String.starts_with?(raw, "+") and byte_size(digits) >= 10 ->
        "+" <> digits

      byte_size(digits) == 10 ->
        "+1" <> digits

      byte_size(digits) == 11 and String.starts_with?(digits, "1") ->
        "+" <> digits

      true ->
        nil
    end
  end

  def to_e164(_), do: nil

  defp do_send_sms(to, body) do
    config = Application.get_env(:mobile_car_wash, :twilio)

    with {:ok, account_sid} <- fetch_config(config, :account_sid),
         {:ok, auth_token} <- fetch_config(config, :auth_token),
         {:ok, from_raw} <- fetch_config(config, :from_number),
         {:ok, to_e164} <- normalize_or_error(to, :bad_to_number),
         {:ok, from_e164} <- normalize_or_error(from_raw, :bad_from_number) do
      url = "https://api.twilio.com/2010-04-01/Accounts/#{account_sid}/Messages.json"

      case Req.post(url,
             auth: {:basic, "#{account_sid}:#{auth_token}"},
             form: [To: to_e164, From: from_e164, Body: body]
           ) do
        {:ok, %{status: 201, body: %{"sid" => sid}}} ->
          Logger.info("SMS sent to #{to_e164}: #{sid}")
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

  defp normalize_or_error(raw, error_tag) do
    case to_e164(raw) do
      nil ->
        Logger.error("Twilio: cannot normalize phone number #{inspect(raw)} (#{error_tag})")
        {:error, error_tag}

      e164 ->
        {:ok, e164}
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
