defmodule MobileCarWash.Marketing.PersonaMembership do
  @moduledoc """
  Join row between a Customer and a Persona. One customer can belong
  to multiple personas simultaneously — they're overlapping
  archetypes, not mutually exclusive buckets.
  """
  use Ash.Resource,
    otp_app: :mobile_car_wash,
    domain: MobileCarWash.Marketing,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "persona_memberships"
    repo MobileCarWash.Repo

    references do
      reference :customer, on_delete: :delete
      reference :persona, on_delete: :delete
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :matched_at, :utc_datetime_usec do
      allow_nil? false
      default &DateTime.utc_now/0
      public? true
    end

    attribute :manually_assigned, :boolean do
      allow_nil? false
      default false
      public? true
      description "True when an admin tagged the customer; false when the rule engine did."
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :customer, MobileCarWash.Accounts.Customer do
      allow_nil? false
      public? true
    end

    belongs_to :persona, MobileCarWash.Marketing.Persona do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_pair, [:customer_id, :persona_id]
  end

  actions do
    defaults [:read, :destroy]

    create :assign do
      accept [:customer_id, :persona_id, :manually_assigned]
    end

    read :for_customer do
      argument :customer_id, :uuid, allow_nil?: false
      filter expr(customer_id == ^arg(:customer_id))
    end

    read :for_persona do
      argument :persona_id, :uuid, allow_nil?: false
      filter expr(persona_id == ^arg(:persona_id))
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    policy action_type([:create, :destroy]) do
      authorize_if expr(^actor(:role) == :admin)
    end
  end
end
