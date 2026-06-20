defmodule MobileCarWash.Scheduling.AddOn do
  @moduledoc """
  Optional à-la-carte add-on services (wax, interior shampoo, etc.) offered
  on top of a base service. Admin-managed. Flat-priced: the add-on total is
  added to the appointment charge without size multiplier or discount.
  """
  use Ash.Resource,
    otp_app: :mobile_car_wash,
    domain: MobileCarWash.Scheduling,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("add_ons")
    repo(MobileCarWash.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :name, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :slug, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :description, :string do
      public?(true)
    end

    attribute :price_cents, :integer do
      allow_nil?(false)
      public?(true)
    end

    attribute :icon, :string do
      public?(true)
      description("Hero icon name, e.g. \"sparkles\".")
    end

    attribute :active, :boolean do
      default(true)
      public?(true)
    end

    attribute :sort_order, :integer do
      default(0)
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
      primary?(true)
      accept([:name, :slug, :description, :price_cents, :icon, :active, :sort_order])
    end

    update :update do
      primary?(true)
      accept([:name, :slug, :description, :price_cents, :icon, :active, :sort_order])
    end
  end
end
