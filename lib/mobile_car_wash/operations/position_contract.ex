defmodule MobileCarWash.Operations.PositionContract do
  @moduledoc """
  A position contract (E-Myth "position agreement") defines the responsibilities,
  standards, and linked SOPs for a position. This is the job description
  built from the systems that run the business.
  """
  use Ash.Resource,
    otp_app: :mobile_car_wash,
    domain: MobileCarWash.Operations,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("position_contracts")
    repo(MobileCarWash.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :title, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :purpose, :string do
      public?(true)
      description("The primary purpose of this position")
    end

    attribute :responsibilities, :string do
      public?(true)
      description("Detailed list of responsibilities (markdown)")
    end

    attribute :standards, :string do
      public?(true)
      description("Performance standards and metrics")
    end

    attribute :active, :boolean do
      default(true)
      public?(true)
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :position, MobileCarWash.Operations.OrgPosition do
      allow_nil?(false)
    end
  end

  actions do
    defaults([:read, :destroy, create: :*, update: :*])
  end
end
