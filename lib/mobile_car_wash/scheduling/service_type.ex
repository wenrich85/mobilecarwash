defmodule MobileCarWash.Scheduling.ServiceType do
  @moduledoc """
  Defines the types of services offered (basic wash, deep clean, etc.).
  Seeded at startup — rarely changed.
  """
  use Ash.Resource,
    otp_app: :mobile_car_wash,
    domain: MobileCarWash.Scheduling,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "service_types"
    repo MobileCarWash.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :slug, :string do
      allow_nil? false
      public? true
    end

    attribute :description, :string do
      public? true
    end

    attribute :base_price_cents, :integer do
      allow_nil? false
      public? true
    end

    attribute :duration_minutes, :integer do
      allow_nil? false
      public? true
    end

    attribute :active, :boolean do
      default true
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_slug, [:slug]
  end

  actions do
    defaults [:read, create: :*, update: :*]
  end
end
