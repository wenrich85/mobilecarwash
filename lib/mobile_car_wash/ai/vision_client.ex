defmodule MobileCarWash.AI.VisionClient do
  @moduledoc """
  Thin wrapper around Anthropic's Messages API for vision classification.
  Mockable in tests via `config :mobile_car_wash, :vision_client`.

  The Anthropic API accepts image content either as a URL (for remotely-
  hosted images) or base64-encoded bytes. We prefer URL when the photo
  lives on S3 — a presigned GET URL lets Anthropic fetch directly without
  us pulling the bytes through our VM.

  Returns `{:ok, tags_map}` where `tags_map` is the parsed JSON payload
  matching the prompt's schema. Errors are normalised to recognisable
  atoms so the caller can decide on retry vs give-up.
  """

  require Logger

  @anthropic_url "https://api.anthropic.com/v1/messages"
  @model "claude-sonnet-4-6"
  @api_version "2023-06-01"

  @type response :: {:ok, map()} | {:error, atom() | term()}

  @spec classify(String.t(), String.t()) :: response()
  def classify(image_url, prompt) do
    case client_module() do
      __MODULE__ -> do_classify(image_url, prompt)
      mock -> mock.classify(image_url, prompt)
    end
  end

  defp do_classify(image_url, prompt) do
    api_key = Application.get_env(:mobile_car_wash, :anthropic_api_key)

    if is_nil(api_key) or api_key == "" do
      {:error, :anthropic_not_configured}
    else
      body = %{
        model: @model,
        max_tokens: 512,
        system: prompt,
        messages: [
          %{
            role: "user",
            content: [
              %{type: "image", source: %{type: "url", url: image_url}},
              %{type: "text", text: "Classify this photo and return JSON only."}
            ]
          }
        ]
      }

      case Req.post(@anthropic_url,
             headers: [
               {"x-api-key", api_key},
               {"anthropic-version", @api_version},
               {"content-type", "application/json"}
             ],
             json: body,
             receive_timeout: 30_000
           ) do
        {:ok, %{status: 200, body: resp}} -> parse_anthropic_response(resp)
        {:ok, %{status: 429}} -> {:error, :rate_limited}
        {:ok, %{status: status, body: resp}} ->
          Logger.warning("Anthropic API #{status}: #{inspect(resp)}")
          {:error, {:http_error, status}}

        {:error, reason} ->
          Logger.error("Anthropic request failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  # Extract the JSON payload from Anthropic's Messages API response shape.
  # content is a list; we want the first text block.
  defp parse_anthropic_response(%{"content" => [%{"type" => "text", "text" => text} | _]}) do
    case Jason.decode(text) do
      {:ok, tags} when is_map(tags) -> {:ok, tags}
      {:ok, _} -> {:error, :non_object_response}
      {:error, _} -> {:error, :malformed_json}
    end
  end

  defp parse_anthropic_response(_), do: {:error, :unexpected_response_shape}

  defp client_module do
    Application.get_env(:mobile_car_wash, :vision_client, __MODULE__)
  end
end
