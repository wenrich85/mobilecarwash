defmodule MobileCarWash.Scheduling.SchedulingSettings do
  @moduledoc """
  Singleton resource holding admin-tunable scheduling knobs.

  Currently just one field (`max_intra_block_drive_minutes`), but the
  resource is designed to accrete future knobs (travel speed, detour
  factor, shop origin) without forcing a separate settings infrastructure.

  Access through `get/0` (creates the row on first call) and
  `update/1` (operates on the singleton row). Callers should never rely
  on there being more than one row in this table.
  """
  use Ash.Resource,
    otp_app: :mobile_car_wash,
    domain: MobileCarWash.Scheduling,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "scheduling_settings"
    repo MobileCarWash.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :max_intra_block_drive_minutes, :integer do
      default 20
      allow_nil? false
      public? true
      description "When joining a block that already has appointments, the customer's address must be within this many drive-minutes of at least one existing appointment."
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  validations do
    validate compare(:max_intra_block_drive_minutes, greater_than: 0),
      message: "must be positive"
  end

  actions do
    defaults [:read]

    create :initialize do
      accept [:max_intra_block_drive_minutes]
    end

    update :update do
      accept [:max_intra_block_drive_minutes]
    end
  end

  policies do
    # Reads are open — anyone authenticated may look up the current settings.
    # Writes are admin-only (enforced by the admin-auth pipeline on the UI
    # route + the one caller in SettingsLive).
    policy action_type(:read) do
      authorize_if always()
    end

    policy action_type([:create, :update]) do
      authorize_if expr(^actor(:role) == :admin)
      authorize_if always()
    end
  end

  # -----------------------------------------------------------------
  # Convenience API
  # -----------------------------------------------------------------

  @doc """
  Returns the singleton settings row, creating it with defaults on first
  access. Safe to call from any context.
  """
  def get do
    case Ash.read!(__MODULE__, authorize?: false) do
      [settings | _] ->
        settings

      [] ->
        __MODULE__
        |> Ash.Changeset.for_create(:initialize, %{})
        |> Ash.create!(authorize?: false)
    end
  end

  @doc """
  Updates the singleton row. Returns `{:ok, settings}` or
  `{:error, changeset}`.
  """
  def update(attrs) do
    get()
    |> Ash.Changeset.for_update(:update, attrs)
    |> Ash.update(authorize?: false)
  end
end
