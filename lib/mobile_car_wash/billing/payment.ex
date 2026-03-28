defmodule MobileCarWash.Billing.Payment do
  @moduledoc """
  Payment record — tracks both one-time appointment payments
  and subscription billing events via Stripe.
  """
  use Ash.Resource,
    otp_app: :mobile_car_wash,
    domain: MobileCarWash.Billing,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "payments"
    repo MobileCarWash.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :stripe_payment_intent_id, :string do
      public? true
    end

    attribute :amount_cents, :integer do
      allow_nil? false
      public? true
    end

    attribute :status, :atom do
      constraints one_of: [:pending, :succeeded, :failed, :refunded]
      default :pending
      allow_nil? false
      public? true
    end

    attribute :paid_at, :utc_datetime do
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :customer, MobileCarWash.Accounts.Customer do
      allow_nil? false
    end

    belongs_to :appointment, MobileCarWash.Scheduling.Appointment do
      allow_nil? true
    end

    belongs_to :subscription, MobileCarWash.Billing.Subscription do
      allow_nil? true
    end
  end

  actions do
    defaults [:read, create: :*, update: :*]
  end
end
