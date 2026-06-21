defmodule MobileCarWash.Fleet.GeocoderClient do
  @moduledoc """
  Address autocomplete / geocoding via Req. Server-side only; no client keys.

  Default provider: US Census onelineaddress geocoder (free, no key, US-only).
  Falls back to Photon (OSM) when Census errors or returns no matches.

  Mockable in tests via `config :mobile_car_wash, :geocoder_client` so
  suggestions never hit the network. Mirrors `Vehicles.NhtsaClient`.
  """
  require Logger

  @census "https://geocoding.geo.census.gov/geocoder/locations/onelineaddress"
  @photon "https://photon.komoot.io/api"

  @type suggestion :: %{
          label: String.t(),
          street: String.t(),
          city: String.t(),
          state: String.t(),
          zip: String.t(),
          lat: float(),
          lng: float()
        }

  @doc """
  Address suggestions for a free-text query. Returns up to a handful of
  matches, or `{:ok, []}` when nothing matches. Never raises on network error.
  """
  @spec suggest(String.t()) :: {:ok, [suggestion()]} | {:error, term()}
  def suggest(query) do
    case client_module() do
      __MODULE__ -> do_suggest(query)
      mock -> mock.suggest(query)
    end
  end

  defp do_suggest(query) do
    case census_suggest(query) do
      {:ok, []} -> photon_suggest(query)
      {:ok, results} -> {:ok, results}
      {:error, _} -> photon_suggest(query)
    end
  end

  # --- US Census ---
  defp census_suggest(query) do
    params = [address: query, benchmark: "Public_AR_Current", format: "json"]

    case Req.get(@census, params: params) do
      {:ok, %{status: 200, body: %{"result" => %{"addressMatches" => matches}}}}
      when is_list(matches) ->
        {:ok, matches |> Enum.map(&census_match/1) |> Enum.reject(&is_nil/1)}

      {:ok, %{status: status}} ->
        Logger.error("Census geocoder error #{status}")
        {:error, {:census_error, status}}

      {:error, reason} ->
        Logger.error("Census geocoder request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp census_match(%{
         "matchedAddress" => matched,
         "coordinates" => %{"x" => lng, "y" => lat},
         "addressComponents" => comp
       })
       when is_number(lat) and is_number(lng) do
    street =
      matched
      |> to_string()
      |> String.split(",")
      |> List.first()
      |> to_string()
      |> String.trim()

    %{
      label: matched,
      street: street,
      city: comp["city"] || "",
      state: comp["state"] || "",
      zip: comp["zip"] || "",
      lat: lat * 1.0,
      lng: lng * 1.0
    }
  end

  defp census_match(_), do: nil

  # --- Photon (OSM) fallback ---
  defp photon_suggest(query) do
    params = [q: query, limit: 5]

    case Req.get(@photon, params: params) do
      {:ok, %{status: 200, body: %{"features" => features}}} when is_list(features) ->
        {:ok, features |> Enum.map(&photon_feature/1) |> Enum.reject(&is_nil/1)}

      {:ok, %{status: status}} ->
        Logger.error("Photon geocoder error #{status}")
        {:error, {:photon_error, status}}

      {:error, reason} ->
        Logger.error("Photon geocoder request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp photon_feature(%{
         "geometry" => %{"coordinates" => [lng, lat]},
         "properties" => props
       })
       when is_number(lat) and is_number(lng) do
    street =
      [props["housenumber"], props["street"] || props["name"]]
      |> Enum.reject(&(is_nil(&1) or &1 == ""))
      |> Enum.join(" ")

    %{
      label: photon_label(street, props),
      street: street,
      city: props["city"] || "",
      state: props["state"] || "",
      zip: props["postcode"] || "",
      lat: lat * 1.0,
      lng: lng * 1.0
    }
  end

  defp photon_feature(_), do: nil

  defp photon_label(street, props) do
    [street, props["city"], props["state"], props["postcode"]]
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> Enum.join(", ")
  end

  defp client_module do
    Application.get_env(:mobile_car_wash, :geocoder_client, __MODULE__)
  end
end
