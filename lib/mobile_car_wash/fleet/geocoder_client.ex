defmodule MobileCarWash.Fleet.GeocoderClient do
  @moduledoc """
  Address autocomplete / geocoding via Req. Server-side only; no client keys.

  Default provider: US Census onelineaddress geocoder (free, no key, US-only).
  Falls back to Photon (OSM) when Census errors or returns no matches.

  Suggestions are biased toward the service region and **hard-filtered to the
  service area** (ZIP in `MobileCarWash.Zones`), so the typeahead only ever
  offers addresses we actually service. Out-of-area addresses remain reachable
  via manual entry (which still shows the outside-service-area banner).

  Mockable in tests via `config :mobile_car_wash, :geocoder_client` so
  suggestions never hit the network. Mirrors `Vehicles.NhtsaClient`.
  """
  require Logger

  alias MobileCarWash.Zones

  @census "https://geocoding.geo.census.gov/geocoder/locations/onelineaddress"
  @photon "https://photon.komoot.io/api"

  # Service-region biasing — San Antonio metro (matches `MobileCarWash.Zones`).
  @service_region "San Antonio, TX"
  @service_center_lat 29.4241
  @service_center_lng -98.4936
  # Photon bounding box "minLon,minLat,maxLon,maxLat" covering the SA metro.
  @service_bbox "-98.75,29.2,-98.3,29.7"

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

  @doc """
  Keep only suggestions whose ZIP is in the service area (`Zones`); drop the
  rest. Public for testability — applied to every provider's results so
  out-of-area addresses never reach the typeahead.
  """
  @spec filter_to_service_area([suggestion()]) :: [suggestion()]
  def filter_to_service_area(suggestions) do
    Enum.filter(suggestions, fn %{zip: zip} -> Zones.serviced_zip?(zip) end)
  end

  @doc """
  Bias a bare street query toward the service region. A query that already
  contains a comma (street + city/state typed by the user) is respected as-is.
  """
  @spec census_query(String.t()) :: String.t()
  def census_query(query) do
    if String.contains?(query, ","), do: query, else: query <> ", " <> @service_region
  end

  # Try Census first, filtered to the service area; fall back to Photon (also
  # filtered) when Census errors or yields nothing serviceable.
  defp do_suggest(query) do
    case census_suggest(query) do
      {:ok, results} ->
        case filter_to_service_area(results) do
          [] -> photon_fallback(query)
          serviced -> {:ok, serviced}
        end

      {:error, _} ->
        photon_fallback(query)
    end
  end

  defp photon_fallback(query) do
    case photon_suggest(query) do
      {:ok, results} -> {:ok, filter_to_service_area(results)}
      error -> error
    end
  end

  # --- US Census ---
  defp census_suggest(query) do
    params = [address: census_query(query), benchmark: "Public_AR_Current", format: "json"]

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
    params = [
      q: query,
      limit: 5,
      lat: @service_center_lat,
      lon: @service_center_lng,
      bbox: @service_bbox
    ]

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

    # A street-less result (city/POI only) can't autofill a booking address — drop it.
    if street == "" do
      nil
    else
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
