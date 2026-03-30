defmodule MobileCarWash.Fleet.Changes.SetZoneFromZip do
  @moduledoc """
  Ash change that auto-assigns the service zone based on the address zip code.
  Runs on create and update — recalculates whenever zip changes.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :zip) do
      nil ->
        changeset

      zip ->
        zone = MobileCarWash.Zones.zone_for_zip(zip)
        Ash.Changeset.force_change_attribute(changeset, :zone, zone)
    end
  end
end
