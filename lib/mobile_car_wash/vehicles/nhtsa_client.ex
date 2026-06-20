defmodule MobileCarWash.Vehicles.NhtsaClient do
  @moduledoc """
  NHTSA vPIC API client — VIN decode + makes/models — via Req.

  Free, no API key. Mockable in tests via `config :mobile_car_wash, :nhtsa_client`.
  Models (keyed by make AND year) are cached in `NhtsaCache` (~30d TTL).
  """
  require Logger

  alias MobileCarWash.Vehicles.NhtsaCache

  @base "https://vpic.nhtsa.dot.gov/api/vehicles"

  # Curated list of popular makes shown first in the dropdown (alphabetical).
  @popular_makes [
    "Acura",
    "Audi",
    "BMW",
    "Buick",
    "Cadillac",
    "Chevrolet",
    "Chrysler",
    "Dodge",
    "Ford",
    "GMC",
    "Honda",
    "Hyundai",
    "Infiniti",
    "Jeep",
    "Kia",
    "Land Rover",
    "Lexus",
    "Lincoln",
    "Mazda",
    "Mercedes-Benz",
    "Mini",
    "Mitsubishi",
    "Nissan",
    "Porsche",
    "Ram",
    "Subaru",
    "Tesla",
    "Toyota",
    "Volkswagen",
    "Volvo"
  ]

  @doc "Curated list of popular makes shown first in the dropdown."
  @spec popular_makes() :: [String.t()]
  def popular_makes, do: @popular_makes

  @doc "Decode a VIN. Returns {:ok, map} (make/model/year/body_class/size) or {:error, reason}."
  @spec decode_vin(String.t()) :: {:ok, map()} | {:error, term()}
  def decode_vin(vin) do
    case client_module() do
      __MODULE__ -> do_decode_vin(vin)
      mock -> mock.decode_vin(vin)
    end
  end

  @doc "Models for a make+year. Returns {:ok, [String.t()]} or {:error, reason}. Cached."
  @spec models_for_make_year(String.t(), integer() | String.t()) ::
          {:ok, [String.t()]} | {:error, term()}
  def models_for_make_year(make, year) do
    case client_module() do
      __MODULE__ -> do_models_for_make_year(make, year)
      mock -> mock.models_for_make_year(make, year)
    end
  end

  @doc "Map an NHTSA BodyClass string to our pricing size atom."
  @spec body_class_to_size(String.t() | nil) :: :car | :suv_van | :pickup
  def body_class_to_size(nil), do: :car

  def body_class_to_size(body_class) when is_binary(body_class) do
    bc = String.downcase(body_class)

    cond do
      String.contains?(bc, "pickup") -> :pickup
      String.contains?(bc, ["truck", "cab"]) -> :pickup
      String.contains?(bc, ["sport utility", "suv", "minivan", "van", "wagon", "mpv"]) -> :suv_van
      true -> :car
    end
  end

  # --- Real HTTP implementations ---

  defp do_decode_vin(vin) do
    url = "#{@base}/DecodeVinValues/#{URI.encode(vin, &URI.char_unreserved?/1)}?format=json"

    case Req.get(url) do
      {:ok, %{status: 200, body: %{"Results" => [row | _]}}} ->
        make = row["Make"]

        if is_binary(make) and make != "" do
          body_class = blank_to_nil(row["BodyClass"])

          {:ok,
           %{
             make: titleize(make),
             model: blank_to_nil(row["Model"]),
             year: parse_year(row["ModelYear"]),
             body_class: body_class,
             size: body_class_to_size(body_class)
           }}
        else
          {:error, :vin_not_decoded}
        end

      {:ok, %{status: status}} ->
        Logger.error("NHTSA VIN decode error #{status}")
        {:error, {:nhtsa_error, status}}

      {:error, reason} ->
        Logger.error("NHTSA VIN request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp do_models_for_make_year(make, year) do
    key = {:models, String.downcase(make), to_string(year)}

    case NhtsaCache.get(key) do
      {:ok, models} ->
        {:ok, models}

      :miss ->
        url =
          "#{@base}/GetModelsForMakeYear/make/#{URI.encode(make, &URI.char_unreserved?/1)}/modelyear/#{year}?format=json"

        case Req.get(url) do
          {:ok, %{status: 200, body: %{"Results" => results}}} when is_list(results) ->
            models =
              results
              |> Enum.map(& &1["Model_Name"])
              |> Enum.reject(&(is_nil(&1) or &1 == ""))
              |> Enum.uniq()
              |> Enum.sort()

            NhtsaCache.put(key, models)
            {:ok, models}

          {:ok, %{status: status}} ->
            Logger.error("NHTSA models error #{status}")
            {:error, {:nhtsa_error, status}}

          {:error, reason} ->
            Logger.error("NHTSA models request failed: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  # --- Helpers ---

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(s) when is_binary(s), do: s

  defp parse_year(nil), do: nil
  defp parse_year(y) when is_integer(y), do: y

  defp parse_year(y) when is_binary(y) do
    case Integer.parse(y) do
      {int, _} -> int
      :error -> nil
    end
  end

  defp titleize(s) do
    s |> String.split(" ") |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp client_module do
    Application.get_env(:mobile_car_wash, :nhtsa_client, __MODULE__)
  end
end
