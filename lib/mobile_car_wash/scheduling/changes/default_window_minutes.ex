defmodule MobileCarWash.Scheduling.Changes.DefaultWindowMinutes do
  @moduledoc """
  Fills in `window_minutes` on a ServiceType create when the caller didn't
  provide one. Default = `duration_minutes * 3 + 60` — fits 3 services plus
  a travel budget of ~20 minutes between stops.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :window_minutes) do
      nil ->
        case Ash.Changeset.get_attribute(changeset, :duration_minutes) do
          duration when is_integer(duration) ->
            Ash.Changeset.force_change_attribute(changeset, :window_minutes, duration * 3 + 60)

          _ ->
            changeset
        end

      _ ->
        changeset
    end
  end
end
