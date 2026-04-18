defmodule MobileCarWash.Fleet.Changes.AutoGeocodeFromZip do
  @moduledoc """
  Fills in `latitude` + `longitude` from the ZIP code's known centroid when
  the caller doesn't supply them. The route optimizer uses these coordinates
  for haversine distance calculation; ZIP-level accuracy is sufficient for
  MVP. On update, only refreshes coords if ZIP changed and lat/lng weren't
  explicitly set.
  """
  use Ash.Resource.Change

  alias MobileCarWash.Zones

  @impl true
  def change(changeset, _opts, _context) do
    if caller_set_coords?(changeset) do
      changeset
    else
      maybe_geocode(changeset)
    end
  end

  defp caller_set_coords?(changeset) do
    Ash.Changeset.changing_attribute?(changeset, :latitude) or
      Ash.Changeset.changing_attribute?(changeset, :longitude)
  end

  defp maybe_geocode(changeset) do
    zip = Ash.Changeset.get_attribute(changeset, :zip)

    cond do
      # On update: only geocode if ZIP is actually changing
      changeset.action.type == :update and
          not Ash.Changeset.changing_attribute?(changeset, :zip) ->
        changeset

      true ->
        case Zones.coordinates_for_zip(zip) do
          {lat, lng} ->
            changeset
            |> Ash.Changeset.force_change_attribute(:latitude, lat)
            |> Ash.Changeset.force_change_attribute(:longitude, lng)

          _ ->
            changeset
        end
    end
  end
end
