defmodule MobileCarWash.Notifications.DeviceToken do
  @moduledoc """
  An APNs (or FCM, later) push-notification token issued by a mobile device.

  Tokens upsert on the token string: if iOS reissues the same token after a
  reinstall, or the device is signed in by a different customer, the existing
  row is rebound and reactivated rather than a duplicate being created.

  When APNs returns `Unregistered` / `BadDeviceToken`, the delivery worker
  calls `:mark_failed`, which deactivates the row and records the reason so
  future sends skip it. A dead-token pruning job can later hard-delete rows
  that have been `active: false` for > 90 days.
  """
  use Ash.Resource,
    otp_app: :mobile_car_wash,
    domain: MobileCarWash.Notifications,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "device_tokens"
    repo MobileCarWash.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :token, :string do
      allow_nil? false
      public? true
    end

    attribute :platform, :atom do
      constraints one_of: [:ios, :android]
      allow_nil? false
      default :ios
      public? true
    end

    attribute :active, :boolean do
      default true
      allow_nil? false
      public? true
    end

    attribute :app_version, :string, public?: true
    attribute :device_model, :string, public?: true
    attribute :last_seen_at, :utc_datetime_usec, public?: true
    attribute :failed_at, :utc_datetime_usec, public?: true
    attribute :failure_reason, :string, public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :customer, MobileCarWash.Accounts.Customer do
      allow_nil? false
      attribute_writable? true
    end
  end

  identities do
    identity :unique_token, [:token]
  end

  actions do
    defaults [:read, :destroy]

    create :register do
      accept [:token, :platform, :app_version, :device_model]
      argument :customer_id, :uuid, allow_nil?: false

      change set_attribute(:active, true)
      change set_attribute(:failed_at, nil)
      change set_attribute(:failure_reason, nil)

      change fn changeset, _ ->
        customer_id = Ash.Changeset.get_argument(changeset, :customer_id)

        changeset
        |> Ash.Changeset.force_change_attribute(:customer_id, customer_id)
        |> Ash.Changeset.force_change_attribute(:last_seen_at, DateTime.utc_now())
      end

      upsert? true
      upsert_identity :unique_token

      upsert_fields [
        :customer_id,
        :platform,
        :app_version,
        :device_model,
        :active,
        :last_seen_at,
        :failed_at,
        :failure_reason
      ]
    end

    update :deactivate do
      accept []
      change set_attribute(:active, false)
    end

    update :mark_failed do
      require_atomic? false
      accept [:failure_reason]
      change set_attribute(:active, false)

      change fn changeset, _ ->
        Ash.Changeset.force_change_attribute(
          changeset,
          :failed_at,
          DateTime.utc_now()
        )
      end
    end

    read :active_for_customer do
      argument :customer_id, :uuid, allow_nil?: false
      filter expr(customer_id == ^arg(:customer_id) and active == true)
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if expr(customer_id == ^actor(:id))
      authorize_if expr(^actor(:role) == :admin)
    end

    # Register requires an actor; the :customer_id argument is enforced to
    # match the actor in the controller (defense-in-depth).
    policy action(:register) do
      authorize_if actor_present()
    end

    policy action(:deactivate) do
      authorize_if expr(customer_id == ^actor(:id))
      authorize_if expr(^actor(:role) == :admin)
    end

    policy action(:mark_failed) do
      authorize_if expr(^actor(:role) == :admin)
    end

    policy action_type(:destroy) do
      authorize_if expr(customer_id == ^actor(:id))
      authorize_if expr(^actor(:role) == :admin)
    end
  end
end
