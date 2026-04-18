defmodule MobileCarWash.Routing.Haversine do
  @moduledoc """
  Great-circle distance + estimated drive time between two lat/lng points.

  Haversine gives straight-line distance; real roads detour, so we apply a
  detour factor (default 1.4) and divide by a configured travel speed to
  estimate minutes. This is an MVP approximation — swap for Google Distance
  Matrix or OSRM when traffic/route accuracy starts to matter.
  """

  @earth_radius_miles 3959.0

  @doc "Great-circle distance in miles between two {lat, lng} points."
  def distance_miles({lat1, lng1}, {lat2, lng2}) do
    rlat1 = deg_to_rad(lat1)
    rlat2 = deg_to_rad(lat2)
    dlat = deg_to_rad(lat2 - lat1)
    dlng = deg_to_rad(lng2 - lng1)

    a =
      :math.sin(dlat / 2) * :math.sin(dlat / 2) +
        :math.cos(rlat1) * :math.cos(rlat2) *
          :math.sin(dlng / 2) * :math.sin(dlng / 2)

    c = 2 * :math.atan2(:math.sqrt(a), :math.sqrt(1 - a))
    @earth_radius_miles * c
  end

  @doc """
  Estimated driving minutes between two points, rounded up.
  Applies `travel_detour_factor` (default 1.4) and divides by `travel_speed_mph`
  (default 30), both overridable via application config.
  """
  def travel_minutes(from, to) do
    speed = Application.get_env(:mobile_car_wash, :travel_speed_mph, 30)
    factor = Application.get_env(:mobile_car_wash, :travel_detour_factor, 1.4)

    miles = distance_miles(from, to)
    hours = miles * factor / speed
    minutes = hours * 60

    trunc(Float.ceil(minutes))
  end

  defp deg_to_rad(deg), do: deg * :math.pi() / 180
end
