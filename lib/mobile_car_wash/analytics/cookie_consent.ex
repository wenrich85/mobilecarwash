defmodule MobileCarWash.Analytics.CookieConsent do
  @moduledoc """
  GDPR/CCPA cookie consent record. Strict opt-in: every non-essential
  category defaults to false. Essential (session/auth/CSRF) is always
  true because the app can't function without it.

  Model: one row per banner interaction. If the user opens the banner
  a second time and changes their mind, we write a new row rather
  than mutating the old one — it's audit-friendly (we know exactly
  what they consented to and when) and keeps the logic immutable.

  The latest row by `inserted_at` wins when resolving current consent.
  """
  use Ash.Resource,
    otp_app: :mobile_car_wash,
    domain: MobileCarWash.Analytics,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "cookie_consents"
    repo MobileCarWash.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :session_id, :string do
      allow_nil? false
      public? true
    end

    # Always true — can't be disabled at the resource layer.
    attribute :essential, :boolean do
      allow_nil? false
      default true
      public? true
    end

    attribute :analytics, :boolean do
      allow_nil? false
      default false
      public? true
    end

    attribute :marketing, :boolean do
      allow_nil? false
      default false
      public? true
    end

    attribute :source, :string do
      public? true
      default "banner"
      description "Where the consent was captured: banner, preferences_page, api"
    end

    attribute :ip_hash, :string do
      public? true
      description "SHA-256 of the client IP — proof of consent without PII"
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :customer, MobileCarWash.Accounts.Customer do
      allow_nil? true
      public? true
      description "Nullable — consent is captured pre-signup by session_id"
    end
  end

  calculations do
    calculate :status, :atom, expr(
      cond do
        analytics == true and marketing == true -> :accepted_all
        analytics == false and marketing == false -> :essential_only
        true -> :custom
      end
    )
  end

  actions do
    defaults [:read, :destroy]

    create :record do
      accept [:session_id, :analytics, :marketing, :source, :ip_hash, :customer_id]

      # Force essential=true no matter what the caller supplied.
      change set_attribute(:essential, true)

      # Auto-load the status calculation so callers don't have to
      # remember to request it on every create.
      change load(:status)
    end

    read :for_session do
      argument :session_id, :string, allow_nil?: false
      filter expr(session_id == ^arg(:session_id))
      prepare build(sort: [inserted_at: :desc], load: [:status])
    end
  end

  policies do
    # Read is unrestricted — the banner needs to check consent on every
    # page load, long before we have an actor.
    policy action_type(:read) do
      authorize_if always()
    end

    # Create is unrestricted so anonymous visitors can record consent.
    policy action_type(:create) do
      authorize_if always()
    end

    # Destroy only by admin — for "right to be forgotten" handling.
    policy action_type(:destroy) do
      authorize_if expr(^actor(:role) == :admin)
    end
  end
end
