defmodule MobileCarWash.Billing.SubscriptionPlan do
  @moduledoc """
  Defines available subscription tiers:
  - Basic ($90/mo): 2 basic washes + 25% off deep clean
  - Standard ($125/mo): 4 basic washes + 30% off deep clean
  - Premium ($200/mo): 3 basic washes + 1 deep clean + 50% off additional deep clean
  """
  use Ash.Resource,
    otp_app: :mobile_car_wash,
    domain: MobileCarWash.Billing,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("subscription_plans")
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

    attribute :price_cents, :integer do
      allow_nil?(false)
      public?(true)
    end

    attribute :basic_washes_per_month, :integer do
      allow_nil?(false)
      default(0)
      public?(true)
    end

    attribute :deep_cleans_per_month, :integer do
      allow_nil?(false)
      default(0)
      public?(true)
    end

    attribute :deep_clean_discount_percent, :integer do
      allow_nil?(false)
      default(0)
      public?(true)
    end

    attribute :stripe_price_id, :string do
      public?(true)
    end

    attribute :stripe_product_id, :string do
      public?(true)
    end

    attribute :description, :string do
      public?(true)
    end

    attribute :active, :boolean do
      default(true)
      public?(true)
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  identities do
    identity(:unique_slug, [:slug])
  end

  actions do
    defaults([:read])

    create :create do
      primary?(true)

      accept([
        :name,
        :slug,
        :price_cents,
        :basic_washes_per_month,
        :deep_cleans_per_month,
        :deep_clean_discount_percent,
        :description,
        :active
      ])

      change(
        {MobileCarWash.Billing.Changes.SyncStripeCatalog,
         price_attribute: :price_cents, recurring: true}
      )
    end

    update :update do
      primary?(true)
      require_atomic?(false)

      accept([
        :name,
        :slug,
        :price_cents,
        :basic_washes_per_month,
        :deep_cleans_per_month,
        :deep_clean_discount_percent,
        :description,
        :active
      ])

      change(
        {MobileCarWash.Billing.Changes.SyncStripeCatalog,
         price_attribute: :price_cents, recurring: true}
      )
    end
  end
end
