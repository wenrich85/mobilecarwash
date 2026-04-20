defmodule MobileCarWash.Compliance.TaskCategory do
  @moduledoc """
  Categories for business formation tasks:
  - Texas State Formation
  - Federal Requirements
  - Disabled Veteran Certifications
  - Compliance & Renewals
  """
  use Ash.Resource,
    otp_app: :mobile_car_wash,
    domain: MobileCarWash.Compliance,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("task_categories")
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

    attribute :sort_order, :integer do
      default(0)
      public?(true)
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  identities do
    identity(:unique_slug, [:slug])
  end

  actions do
    defaults([:read, create: :*, update: :*])
  end
end
