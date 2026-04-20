defmodule MobileCarWash.Analytics.Event do
  @moduledoc """
  Tracks every meaningful user action for validated learning.
  Events are the raw data that powers funnel metrics, cohort analysis,
  and experiment results.

  Examples:
  - page.viewed, signup.completed, booking.started, booking.completed
  - payment.succeeded, subscription.started, subscription.cancelled
  - referral.sent, referral.converted
  """
  use Ash.Resource,
    otp_app: :mobile_car_wash,
    domain: MobileCarWash.Analytics,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "events"
    repo MobileCarWash.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :session_id, :string do
      allow_nil? false
      public? true
      description "Anonymous session tracking — ties events before/after signup"
    end

    attribute :event_name, :string do
      allow_nil? false
      public? true
    end

    attribute :source, :string do
      default "web"
      public? true
      description "web, api, email, sms"
    end

    attribute :properties, :map do
      default %{}
      public? true
      description "Flexible key-value data: page, referrer, utm_source, variant_id, etc."
    end

    # --- Phase 2A enrichment: device + page metadata for persona work ---

    attribute :device_type, :atom do
      public? true
      constraints one_of: [:mobile, :tablet, :desktop, :bot, :unknown]
      default :unknown
    end

    attribute :os, :string, public?: true
    attribute :browser, :string, public?: true
    attribute :user_agent, :string, public?: true
    attribute :page_path, :string, public?: true

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :customer, MobileCarWash.Accounts.Customer do
      allow_nil? true
      description "Nullable — anonymous events before signup"
    end
  end

  actions do
    defaults [:read]

    create :track do
      accept [
        :session_id,
        :event_name,
        :source,
        :properties,
        :customer_id,
        :device_type,
        :os,
        :browser,
        :user_agent,
        :page_path
      ]
    end
  end
end
