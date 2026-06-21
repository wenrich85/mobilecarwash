defmodule MobileCarWash.Marketing.Waitlist do
  @moduledoc """
  Out-of-area lead capture. When a customer's address falls outside the
  service zones, the booking flow blocks payment and records the lead here
  for later outreach.
  """
  use Ash.Resource,
    otp_app: :mobile_car_wash,
    domain: MobileCarWash.Marketing,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("waitlist_entries")
    repo(MobileCarWash.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :email, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute(:name, :string, public?: true)
    attribute(:phone, :string, public?: true)

    attribute :address_text, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :zip, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute(:latitude, :float, public?: true)
    attribute(:longitude, :float, public?: true)
    attribute(:requested_service_slug, :string, public?: true)

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  actions do
    defaults([:read])

    create :join do
      accept([
        :email,
        :name,
        :phone,
        :address_text,
        :zip,
        :latitude,
        :longitude,
        :requested_service_slug
      ])
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if(always())
    end

    policy action_type(:create) do
      authorize_if(always())
    end
  end
end
