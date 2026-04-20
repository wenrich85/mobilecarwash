defmodule MobileCarWash.AI.ImageGenerator do
  @moduledoc """
  OpenAI DALL-E 3 image generator, used to visualize personas.

  Calls `POST /v1/images/generations` with model `dall-e-3`, size
  1024×1024, quality `standard` (cheapest tier — ~$0.04/image).

  Mockable via `config :mobile_car_wash, :image_generator`. Tests
  never hit OpenAI; production reads the key from the
  `:openai_api_key` app env (set at runtime from the `OPENAI_API_KEY`
  env var — never committed).
  """
  require Logger

  @openai_url "https://api.openai.com/v1/images/generations"
  @model "dall-e-3"
  @size "1024x1024"
  @quality "standard"

  @type result :: {:ok, String.t()} | {:error, atom() | term()}

  @spec generate(String.t()) :: result()
  def generate(prompt) when is_binary(prompt) do
    case client_module() do
      __MODULE__ -> do_generate(prompt)
      mock -> mock.generate(prompt)
    end
  end

  defp do_generate(prompt) do
    case Application.get_env(:mobile_car_wash, :openai_api_key) do
      nil ->
        {:error, :openai_not_configured}

      "" ->
        {:error, :openai_not_configured}

      key ->
        body = %{
          model: @model,
          prompt: prompt,
          n: 1,
          size: @size,
          quality: @quality
        }

        case Req.post(@openai_url,
               headers: [
                 {"authorization", "Bearer #{key}"},
                 {"content-type", "application/json"}
               ],
               json: body,
               receive_timeout: 60_000
             ) do
          {:ok, %{status: 200, body: %{"data" => [%{"url" => url} | _]}}} ->
            {:ok, url}

          {:ok, %{status: 429}} ->
            {:error, :rate_limited}

          {:ok, %{status: status, body: body}} ->
            Logger.warning("OpenAI images #{status}: #{inspect(body)}")
            {:error, {:http_error, status}}

          {:error, reason} ->
            Logger.error("OpenAI images request failed: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  defp client_module do
    Application.get_env(:mobile_car_wash, :image_generator, __MODULE__)
  end
end
