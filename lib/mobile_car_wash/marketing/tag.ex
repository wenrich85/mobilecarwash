defmodule MobileCarWash.Marketing.Tag do
  @moduledoc """
  Admin-applied operational flag on a customer — VIP, At Risk, Do Not
  Service, Veteran, etc. Purpose-distinct from Persona: personas are
  analytical archetypes assigned by a rule engine; tags are decisions
  ("don't service this address", "white-glove this customer") made by
  a human.

  Seeded tags with `protected: true` can be deactivated but not
  deleted — they may be referenced by booking-flow checks, so nuking
  them silently would be unsafe.
  """
  use Ash.Resource,
    otp_app: :mobile_car_wash,
    domain: MobileCarWash.Marketing,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  require Ash.Query

  postgres do
    table("tags")
    repo(MobileCarWash.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :slug, :string do
      allow_nil?(false)
      public?(true)
      constraints(match: ~r/^[a-z0-9_]+$/, min_length: 2, max_length: 50)
    end

    attribute :name, :string do
      allow_nil?(false)
      public?(true)
      constraints(min_length: 1, max_length: 60)
    end

    attribute :description, :string do
      public?(true)
      constraints(max_length: 500)
    end

    # Drives the DaisyUI badge class — `"badge-{color}"`.
    attribute :color, :atom do
      constraints(one_of: [:primary, :success, :warning, :error, :info, :neutral])
      default(:neutral)
      allow_nil?(false)
      public?(true)
    end

    # Optional hero icon name, e.g. "hero-star".
    attribute :icon, :string do
      public?(true)
      constraints(max_length: 60)
    end

    # Flag to the booking flow. D3 will wire this up; for now it's just
    # stored so admins can declare intent.
    attribute :affects_booking, :boolean do
      default(false)
      allow_nil?(false)
      public?(true)
    end

    # Seeded tags set this to prevent accidental deletion.
    attribute :protected, :boolean do
      default(false)
      allow_nil?(false)
      public?(true)
    end

    attribute :active, :boolean do
      default(true)
      allow_nil?(false)
      public?(true)
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  identities do
    identity(:unique_slug, [:slug])
  end

  actions do
    defaults([:read])

    create :create do
      accept([:slug, :name, :description, :color, :icon, :affects_booking, :protected, :active])
    end

    update :update do
      accept([:name, :description, :color, :icon, :affects_booking, :active])
    end

    destroy :destroy do
      primary?(true)

      # Protected tags cannot be deleted — soft-archive via :active=false
      # instead.
      validate(fn changeset, _ctx ->
        if changeset.data.protected do
          {:error, field: :base, message: "Protected tags cannot be deleted; deactivate instead."}
        else
          :ok
        end
      end)
    end

    read :active do
      filter(expr(active == true))
      prepare(build(sort: [name: :asc]))
    end

    read :by_slug do
      argument(:slug, :string, allow_nil?: false)
      filter(expr(slug == ^arg(:slug)))
    end
  end

  policies do
    # Read is open to any signed-in actor so tags can surface on the
    # customer's own views later if we want. Writes are admin-only.
    policy action_type(:read) do
      authorize_if(always())
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if(expr(^actor(:role) == :admin))
    end
  end
end
