defmodule MobileCarWash.Fleet.Vehicle do
  @moduledoc """
  A customer's vehicle. Size affects pricing for future enhancements.
  """
  use Ash.Resource,
    otp_app: :mobile_car_wash,
    domain: MobileCarWash.Fleet,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("vehicles")
    repo(MobileCarWash.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :make, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :model, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :year, :integer do
      public?(true)
    end

    attribute :color, :string do
      public?(true)
    end

    attribute :size, :atom do
      constraints(one_of: [:car, :suv_van, :pickup])
      default(:car)
      public?(true)
      description("Vehicle type: car (1.0x), suv_van (1.2x), pickup (1.5x price multiplier)")
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :customer, MobileCarWash.Accounts.Customer do
      allow_nil?(false)
    end
  end

  actions do
    defaults([:read, :destroy, create: :*, update: :*])

    read :for_customer do
      argument(:customer_id, :uuid, allow_nil?: false)
      filter(expr(customer_id == ^arg(:customer_id)))
    end
  end
end
