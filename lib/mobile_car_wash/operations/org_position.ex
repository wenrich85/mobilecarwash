defmodule MobileCarWash.Operations.OrgPosition do
  @moduledoc """
  An organizational position in the E-Myth franchise prototype.
  Even as a solo operator, every position is defined — Owner, Operations Manager,
  Lead Technician, Technician, Admin. When you hire, the org chart is ready.

  Hierarchical via parent_position_id (self-referential).
  Level 0 = Owner, Level 1 = direct reports, etc.
  """
  use Ash.Resource,
    otp_app: :mobile_car_wash,
    domain: MobileCarWash.Operations,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("org_positions")
    repo(MobileCarWash.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :name, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :slug, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :description, :string do
      public?(true)
    end

    attribute :level, :integer do
      default(0)
      public?(true)
      description("Hierarchy level: 0=Owner, 1=direct reports, etc.")
    end

    attribute :sort_order, :integer do
      default(0)
      public?(true)
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :parent_position, __MODULE__ do
      allow_nil?(true)
    end

    has_many :child_positions, __MODULE__ do
      destination_attribute(:parent_position_id)
    end

    has_many :contracts, MobileCarWash.Operations.PositionContract do
      destination_attribute(:position_id)
    end
  end

  identities do
    identity(:unique_slug, [:slug])
  end

  actions do
    defaults([:read, :destroy, create: :*, update: :*])
  end
end
