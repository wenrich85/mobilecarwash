defmodule MobileCarWash.Vehicles.NhtsaClient do
  @moduledoc """
  NHTSA vPIC API client — VIN decode + makes/models — via Req.

  Free, no API key. Mockable in tests via `config :mobile_car_wash, :nhtsa_client`.
  Models (keyed by make AND year) are cached in `NhtsaCache` (~30d TTL).
  """
  require Logger

  alias MobileCarWash.Vehicles.NhtsaCache

  @base "https://vpic.nhtsa.dot.gov/api/vehicles"

  # NHTSA vehicleType filter tokens → our pricing size atom.
  @typed_buckets [{"car", :car}, {"truck", :pickup}, {"mpv", :suv_van}]

  # Size precedence when a model appears in more than one bucket (bias larger).
  @size_rank %{pickup: 2, suv_van: 1, car: 0}

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

  @doc """
  Models for a make+year, each tagged with our pricing size. Returns
  {:ok, [%{name: String.t(), size: :car | :suv_van | :pickup}]} (sorted by
  name, name-deduped) or {:error, reason}. Cached.
  """
  @spec models_for_make_year(String.t(), integer() | String.t()) ::
          {:ok, [%{name: String.t(), size: :car | :suv_van | :pickup}]} | {:error, term()}
  def models_for_make_year(make, year) do
    case client_module() do
      __MODULE__ -> do_models_for_make_year(make, year)
      mock -> mock.models_for_make_year(make, year)
    end
  end

  @doc "Map an NHTSA vehicle-type token to our pricing size atom."
  @spec vehicle_type_to_size(String.t()) :: :car | :suv_van | :pickup
  def vehicle_type_to_size(type) when is_binary(type) do
    case String.downcase(type) do
      "truck" -> :pickup
      "mpv" -> :suv_van
      _ -> :car
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
        case fetch_typed_models(make, year) do
          {:ok, models} ->
            NhtsaCache.put(key, models)
            {:ok, models}

          # Every typed call failed — fall back to untyped names (size :car).
          # Not cached, so a later call can retry the richer typed path.
          :all_failed ->
            fetch_untyped_models(make, year)
        end
    end
  end

  # Query the car/truck/mpv buckets and merge into a sorted, size-tagged list.
  # Returns :all_failed only when every bucket request errored.
  defp fetch_typed_models(make, year) do
    results =
      Enum.map(@typed_buckets, fn {token, size} ->
        {size, fetch_models_of_type(make, year, token)}
      end)

    if Enum.all?(results, fn {_size, r} -> match?({:error, _}, r) end) do
      :all_failed
    else
      merged =
        results
        |> Enum.flat_map(fn
          {size, {:ok, names}} -> Enum.map(names, &{&1, size})
          {_size, {:error, _}} -> []
        end)
        |> merge_by_name()

      {:ok, merged}
    end
  end

  defp fetch_models_of_type(make, year, type) do
    url =
      "#{@base}/GetModelsForMakeYear/make/#{URI.encode(make, &URI.char_unreserved?/1)}" <>
        "/modelyear/#{year}/vehicleType/#{type}?format=json"

    case Req.get(url) do
      {:ok, %{status: 200, body: %{"Results" => results}}} when is_list(results) ->
        names =
          results
          |> Enum.map(& &1["Model_Name"])
          |> Enum.reject(&(is_nil(&1) or &1 == ""))

        {:ok, names}

      {:ok, %{status: status}} ->
        Logger.error("NHTSA models error #{status} (#{type})")
        {:error, {:nhtsa_error, status}}

      {:error, reason} ->
        Logger.error("NHTSA models request failed (#{type}): #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp fetch_untyped_models(make, year) do
    url =
      "#{@base}/GetModelsForMakeYear/make/#{URI.encode(make, &URI.char_unreserved?/1)}/modelyear/#{year}?format=json"

    case Req.get(url) do
      {:ok, %{status: 200, body: %{"Results" => results}}} when is_list(results) ->
        models =
          results
          |> Enum.map(& &1["Model_Name"])
          |> Enum.reject(&(is_nil(&1) or &1 == ""))
          |> Enum.map(&{&1, :car})
          |> merge_by_name()

        {:ok, models}

      {:ok, %{status: status}} ->
        Logger.error("NHTSA models error #{status}")
        {:error, {:nhtsa_error, status}}

      {:error, reason} ->
        Logger.error("NHTSA models request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Merge {name, size} pairs into a sorted, name-deduped list of %{name, size},
  # keeping the highest-ranked size (pickup > suv_van > car) on a collision.
  defp merge_by_name(pairs) do
    pairs
    |> Enum.reduce(%{}, fn {name, size}, acc ->
      Map.update(acc, name, size, fn existing ->
        if @size_rank[size] > @size_rank[existing], do: size, else: existing
      end)
    end)
    |> Enum.map(fn {name, size} -> %{name: name, size: size} end)
    |> Enum.sort_by(& &1.name)
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
