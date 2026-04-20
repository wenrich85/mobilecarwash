defmodule MobileCarWash.Billing.SubscriptionUsage do
  @moduledoc """
  Tracks how many washes a subscriber has used in the current billing period.
  One record per subscription per billing period.
  """
  use Ash.Resource,
    otp_app: :mobile_car_wash,
    domain: MobileCarWash.Billing,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("subscription_usages")
    repo(MobileCarWash.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :period_start, :date do
      allow_nil?(false)
      public?(true)
    end

    attribute :period_end, :date do
      allow_nil?(false)
      public?(true)
    end

    attribute :basic_washes_used, :integer do
      default(0)
      public?(true)
    end

    attribute :deep_cleans_used, :integer do
      default(0)
      public?(true)
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :subscription, MobileCarWash.Billing.Subscription do
      allow_nil?(false)
    end
  end

  actions do
    defaults([:read, create: :*, update: :*])
  end
end
