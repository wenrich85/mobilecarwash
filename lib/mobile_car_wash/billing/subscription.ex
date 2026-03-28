defmodule MobileCarWash.Billing.Subscription do
  @moduledoc """
  A customer's active subscription to a plan. Tracks Stripe subscription ID
  and billing period.
  """
  use Ash.Resource,
    otp_app: :mobile_car_wash,
    domain: MobileCarWash.Billing,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "subscriptions"
    repo MobileCarWash.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :stripe_subscription_id, :string do
      public? true
    end

    attribute :status, :atom do
      constraints one_of: [:active, :paused, :cancelled, :past_due]
      default :active
      allow_nil? false
      public? true
    end

    attribute :current_period_start, :date do
      public? true
    end

    attribute :current_period_end, :date do
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :customer, MobileCarWash.Accounts.Customer do
      allow_nil? false
    end

    belongs_to :plan, MobileCarWash.Billing.SubscriptionPlan do
      allow_nil? false
    end

    has_many :usage_records, MobileCarWash.Billing.SubscriptionUsage
  end

  actions do
    defaults [:read, create: :*, update: :*]

    update :cancel do
      change set_attribute(:status, :cancelled)
    end

    update :pause do
      change set_attribute(:status, :paused)
    end
  end
end
