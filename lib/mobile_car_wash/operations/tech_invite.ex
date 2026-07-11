defmodule MobileCarWash.Operations.TechInvite do
  @moduledoc """
  One-time setup invite for an admin-created technician account.
  """
  use Ash.Resource,
    otp_app: :mobile_car_wash,
    domain: MobileCarWash.Operations,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("tech_invites")
    repo(MobileCarWash.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :token_hash, :string do
      allow_nil?(false)
      sensitive?(true)
      public?(true)
    end

    attribute :status, :atom do
      constraints(one_of: [:pending, :accepted, :revoked, :expired])
      default(:pending)
      allow_nil?(false)
      public?(true)
    end

    attribute :expires_at, :utc_datetime_usec do
      allow_nil?(false)
      public?(true)
    end

    attribute :accepted_at, :utc_datetime_usec do
      public?(true)
    end

    attribute :revoked_at, :utc_datetime_usec do
      public?(true)
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :customer, MobileCarWash.Accounts.Customer do
      allow_nil?(false)
      attribute_writable?(true)
      public?(true)
    end

    belongs_to :technician, MobileCarWash.Operations.Technician do
      allow_nil?(false)
      attribute_writable?(true)
      public?(true)
    end
  end

  identities do
    identity(:unique_token_hash, [:token_hash])
  end

  actions do
    defaults([:read, update: :*])

    create :create do
      accept([:token_hash, :expires_at, :customer_id, :technician_id])
    end
  end
end
