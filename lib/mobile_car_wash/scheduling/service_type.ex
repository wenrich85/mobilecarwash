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

    attribute :window_minutes, :integer do
      public? true
      description "Length of one appointment block for this service. Defaults to duration_minutes * 3 + 60."
    end

    attribute :block_capacity, :integer do
      allow_nil? false
      default 3
      public? true
      description "Max appointments per block window."
    end

    attribute :stripe_product_id, :string do
      public? true
    end

    attribute :stripe_price_id, :string do
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_slug, [:slug]
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [
        :name,
        :slug,
        :description,
        :base_price_cents,
        :duration_minutes,
        :active,
        :window_minutes,
        :block_capacity
      ]

      change MobileCarWash.Scheduling.Changes.DefaultWindowMinutes

      change {MobileCarWash.Billing.Changes.SyncStripeCatalog,
              price_attribute: :base_price_cents, recurring: false}
    end

    update :update do
      primary? true
      require_atomic? false
      accept [
        :name,
        :slug,
        :description,
        :base_price_cents,
        :duration_minutes,
        :active,
        :window_minutes,
        :block_capacity
      ]

      change {MobileCarWash.Billing.Changes.SyncStripeCatalog,
              price_attribute: :base_price_cents, recurring: false}
    end
  end
end
