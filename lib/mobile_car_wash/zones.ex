defmodule MobileCarWash.Zones do
  @moduledoc """
  Pure functional zone logic for San Antonio service area.
  Maps zip codes to 4 quadrants (NW, NE, SW, SE) split by I-35 and city center.
  No external dependencies — compile-time constant map.
  """

  @type zone :: :nw | :ne | :sw | :se

  @zones [:nw, :ne, :sw, :se]

  # San Antonio center point (Alamo / downtown)
  @center_lat 29.4241
  @center_lng -98.4936

  # Zip-to-zone mapping for San Antonio metro
  # Split roughly by I-35 (east/west) and US-90/downtown (north/south)
  @zip_to_zone %{
    # Northwest — north of center, west of I-35
    "78201" => :nw, "78207" => :nw, "78228" => :nw, "78229" => :nw,
    "78230" => :nw, "78238" => :nw, "78240" => :nw, "78249" => :nw,
    "78250" => :nw, "78251" => :nw, "78252" => :nw, "78253" => :nw,
    "78254" => :nw, "78256" => :nw, "78257" => :nw,

    # Northeast — north of center, east of I-35
    "78208" => :ne, "78209" => :ne, "78212" => :ne, "78213" => :ne,
    "78215" => :ne, "78216" => :ne, "78217" => :ne, "78218" => :ne,
    "78231" => :ne, "78232" => :ne, "78233" => :ne, "78247" => :ne,
    "78248" => :ne, "78258" => :ne, "78259" => :ne, "78260" => :ne,
    "78261" => :ne, "78266" => :ne,

    # Southwest — south of center, west of I-35
    "78204" => :sw, "78205" => :sw, "78210" => :sw, "78211" => :sw,
    "78224" => :sw, "78225" => :sw, "78226" => :sw, "78227" => :sw,
    "78236" => :sw, "78237" => :sw, "78242" => :sw, "78245" => :sw,
    "78246" => :sw,

    # Southeast — south of center, east of I-35
    "78202" => :se, "78203" => :se, "78206" => :se, "78214" => :se,
    "78219" => :se, "78220" => :se, "78221" => :se, "78222" => :se,
    "78223" => :se, "78234" => :se, "78235" => :se, "78239" => :se,
    "78244" => :se, "78263" => :se, "78264" => :se
  }

  @doc "All valid zones."
  @spec all() :: [zone()]
  def all, do: @zones

  @doc "Look up zone by zip code. Returns nil if zip is outside service area."
  @spec zone_for_zip(String.t()) :: zone() | nil
  def zone_for_zip(zip) when is_binary(zip) do
    # Normalize — take first 5 digits
    zip = String.slice(zip, 0, 5)
    Map.get(@zip_to_zone, zip)
  end

  def zone_for_zip(_), do: nil

  @doc "Determine zone from latitude/longitude coordinates."
  @spec zone_for_coordinates(float(), float()) :: zone()
  def zone_for_coordinates(lat, lng) when is_number(lat) and is_number(lng) do
    north? = lat >= @center_lat
    west? = lng <= @center_lng

    case {north?, west?} do
      {true, true} -> :nw
      {true, false} -> :ne
      {false, true} -> :sw
      {false, false} -> :se
    end
  end

  @doc "Check if a zip code is in our service area."
  @spec serviced_zip?(String.t()) :: boolean()
  def serviced_zip?(zip), do: zone_for_zip(zip) != nil

  @doc "Full zone label."
  @spec label(zone()) :: String.t()
  def label(:nw), do: "Northwest"
  def label(:ne), do: "Northeast"
  def label(:sw), do: "Southwest"
  def label(:se), do: "Southeast"
  def label(_), do: "Unknown"

  @doc "Short zone label."
  @spec short_label(zone()) :: String.t()
  def short_label(:nw), do: "NW"
  def short_label(:ne), do: "NE"
  def short_label(:sw), do: "SW"
  def short_label(:se), do: "SE"
  def short_label(_), do: "?"

  @doc "Approximate center coordinates for a zone (for map display)."
  @spec zone_center(zone()) :: {float(), float()}
  def zone_center(:nw), do: {29.52, -98.58}
  def zone_center(:ne), do: {29.52, -98.42}
  def zone_center(:sw), do: {29.36, -98.58}
  def zone_center(:se), do: {29.36, -98.42}
  def zone_center(_), do: {@center_lat, @center_lng}

  # Approximate coordinates per zip (center of zip code area)
  @zip_coords %{
    "78201" => {29.4608, -98.5250}, "78202" => {29.4270, -98.4700},
    "78203" => {29.4150, -98.4630}, "78204" => {29.4330, -98.5100},
    "78205" => {29.4241, -98.4936}, "78206" => {29.4180, -98.4570},
    "78207" => {29.4380, -98.5350}, "78208" => {29.4530, -98.4600},
    "78209" => {29.4820, -98.4570}, "78210" => {29.3980, -98.5000},
    "78211" => {29.3730, -98.5400}, "78212" => {29.4700, -98.4900},
    "78213" => {29.5100, -98.5150}, "78214" => {29.3700, -98.4750},
    "78215" => {29.4450, -98.4800}, "78216" => {29.5250, -98.4950},
    "78217" => {29.5250, -98.4400}, "78218" => {29.4900, -98.4100},
    "78219" => {29.4400, -98.4000}, "78220" => {29.3900, -98.4200},
    "78221" => {29.3450, -98.4950}, "78222" => {29.3600, -98.4350},
    "78223" => {29.3550, -98.4500}, "78224" => {29.3550, -98.5350},
    "78225" => {29.4050, -98.5250}, "78226" => {29.4100, -98.5500},
    "78227" => {29.3950, -98.5850}, "78228" => {29.4650, -98.5550},
    "78229" => {29.5000, -98.5700}, "78230" => {29.5350, -98.5600},
    "78231" => {29.5450, -98.5300}, "78232" => {29.5700, -98.4800},
    "78233" => {29.5600, -98.4100}, "78234" => {29.4500, -98.4450},
    "78235" => {29.3700, -98.4500}, "78236" => {29.4100, -98.6100},
    "78237" => {29.4300, -98.5650}, "78238" => {29.4800, -98.5900},
    "78239" => {29.5100, -98.3700}, "78240" => {29.5100, -98.6050},
    "78242" => {29.3900, -98.5600}, "78244" => {29.4700, -98.3600},
    "78245" => {29.3700, -98.6400}, "78247" => {29.5600, -98.4450},
    "78248" => {29.5800, -98.5100}, "78249" => {29.5600, -98.6100},
    "78250" => {29.5050, -98.6350}, "78251" => {29.4700, -98.6600},
    "78252" => {29.4500, -98.7000}, "78253" => {29.5300, -98.7100},
    "78254" => {29.5500, -98.6700}, "78256" => {29.6100, -98.6200},
    "78257" => {29.6200, -98.5900}, "78258" => {29.6100, -98.5100},
    "78259" => {29.6100, -98.4600}, "78260" => {29.6300, -98.4900},
    "78261" => {29.6500, -98.4200}, "78263" => {29.3200, -98.3800},
    "78264" => {29.2700, -98.4800}, "78266" => {29.6700, -98.3900}
  }

  @doc "Get approximate coordinates for a zip code (for map pins)."
  @spec coordinates_for_zip(String.t()) :: {float(), float()} | nil
  def coordinates_for_zip(zip) when is_binary(zip) do
    zip = String.slice(zip, 0, 5)
    Map.get(@zip_coords, zip)
  end

  def coordinates_for_zip(_), do: nil

  @doc "Get coordinates for an address — prefer stored lat/lng, fall back to zip lookup."
  @spec coordinates_for_address(map()) :: {float(), float()} | nil
  def coordinates_for_address(%{latitude: lat, longitude: lng}) when is_number(lat) and is_number(lng) do
    {lat, lng}
  end

  def coordinates_for_address(%{zip: zip}) when is_binary(zip) do
    coordinates_for_zip(zip)
  end

  def coordinates_for_address(_), do: nil

  @doc "DaisyUI badge class for zone color."
  @spec badge_class(zone()) :: String.t()
  def badge_class(:nw), do: "badge-primary"
  def badge_class(:ne), do: "badge-secondary"
  def badge_class(:sw), do: "badge-accent"
  def badge_class(:se), do: "badge-info"
  def badge_class(_), do: "badge-ghost"
end
