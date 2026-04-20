defmodule MobileCarWash.Scheduling.BlockTemplate do
  @moduledoc """
  Drives block generation: one row per (service_type, day_of_week, start_hour).
  The BlockGenerator reads these rows when creating blocks for a date —
  admins can add/edit/deactivate rows to change the weekly schedule without
  code changes.
  """
  use Ash.Resource,
    otp_app: :mobile_car_wash,
    domain: MobileCarWash.Scheduling,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("block_templates")
    repo(MobileCarWash.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :day_of_week, :integer do
      allow_nil?(false)
      constraints(min: 1, max: 7)
      public?(true)
      description("ISO day-of-week: 1 = Monday, 7 = Sunday")
    end

    attribute :start_hour, :integer do
      allow_nil?(false)
      constraints(min: 0, max: 23)
      public?(true)
    end

    attribute :active, :boolean do
      default(true)
      allow_nil?(false)
      public?(true)
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :service_type, MobileCarWash.Scheduling.ServiceType do
      allow_nil?(false)
    end
  end

  identities do
    identity(:unique_slot, [:service_type_id, :day_of_week, :start_hour])
  end

  actions do
    defaults([:read])

    create :create do
      primary?(true)
      accept([:service_type_id, :day_of_week, :start_hour, :active])
    end

    update :update do
      primary?(true)
      require_atomic?(false)
      accept([:day_of_week, :start_hour, :active])
    end

    destroy :destroy do
      primary?(true)
    end
  end
end
