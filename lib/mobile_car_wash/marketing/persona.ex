defmodule MobileCarWash.Marketing.Persona do
  @moduledoc """
  A named customer archetype used for targeted marketing.

  The `description` doubles as the prompt fed to the image-generation
  API in Phase 2C — write it the way you'd describe the person to an
  illustrator. The `image_prompt` field lets you override the
  description-as-prompt with a more visually-tuned string.

  `criteria` is a map of simple equality/range predicates evaluated
  by `Marketing.Personas.matches?/2`. Example:

      %{
        "acquired_channel_slug" => "meta_paid",
        "device_type" => "mobile",
        "lifetime_revenue_cents" => %{"gte" => 5_000}
      }
  """
  use Ash.Resource,
    otp_app: :mobile_car_wash,
    domain: MobileCarWash.Marketing,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("personas")
    repo(MobileCarWash.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :slug, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :name, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :description, :string do
      allow_nil?(true)
      default("")
      public?(true)
    end

    attribute :criteria, :map do
      default(%{})
      public?(true)
    end

    attribute(:image_url, :string, public?: true)
    attribute(:image_prompt, :string, public?: true)

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

  relationships do
    has_many :memberships, MobileCarWash.Marketing.PersonaMembership
  end

  actions do
    defaults([:read, :destroy, update: :*])

    create :create do
      accept([
        :slug,
        :name,
        :description,
        :criteria,
        :image_url,
        :image_prompt,
        :active,
        :sort_order
      ])
    end

    read :active do
      filter(expr(active == true))
      prepare(build(sort: [sort_order: :asc, name: :asc]))
    end

    read :by_slug do
      argument(:slug, :string, allow_nil?: false)
      filter(expr(slug == ^arg(:slug)))
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if(always())
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if(expr(^actor(:role) == :admin))
    end
  end
end
