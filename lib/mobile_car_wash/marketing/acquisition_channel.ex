defmodule MobileCarWash.Marketing.AcquisitionChannel do
  @moduledoc """
  Canonical list of places customers come from. Anchors every CAC /
  LTV rollup — one channel row per source ("Google Organic", "Meta
  Paid", "Referral", "Door Hangers", etc.).
  """
  use Ash.Resource,
    otp_app: :mobile_car_wash,
    domain: MobileCarWash.Marketing,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("acquisition_channels")
    repo(MobileCarWash.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :slug, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :display_name, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :category, :atom do
      allow_nil?(false)
      public?(true)
      constraints(one_of: [:paid, :organic, :referral, :offline, :unknown])
    end

    attribute :active, :boolean do
      allow_nil?(false)
      default(true)
      public?(true)
    end

    attribute :sort_order, :integer do
      default(100)
      public?(true)
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  identities do
    identity(:unique_slug, [:slug])
  end

  actions do
    defaults([:read, :destroy, update: :*])

    create :create do
      accept([:slug, :display_name, :category, :active, :sort_order])
    end

    read :active do
      filter(expr(active == true))
      prepare(build(sort: [sort_order: :asc, display_name: :asc]))
    end

    read :by_slug do
      argument(:slug, :string, allow_nil?: false)
      filter(expr(slug == ^arg(:slug)))
    end
  end

  policies do
    # Reads are unrestricted — the plug that captures attribution
    # needs to look channels up without an actor.
    policy action_type(:read) do
      authorize_if(always())
    end

    # Mutations are admin-only.
    policy action_type([:create, :update, :destroy]) do
      authorize_if(expr(^actor(:role) == :admin))
    end
  end
end
