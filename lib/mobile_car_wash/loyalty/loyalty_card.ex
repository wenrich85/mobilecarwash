defmodule MobileCarWash.Loyalty.LoyaltyCard do
  @moduledoc """
  Tracks a customer's punch card. One card per customer.
  Every completed wash = 1 punch. Every 10 punches = 1 free wash.
  """
  use Ash.Resource,
    otp_app: :mobile_car_wash,
    domain: MobileCarWash.Loyalty,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("loyalty_cards")
    repo(MobileCarWash.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :punch_count, :integer do
      default(0)
      allow_nil?(false)
      public?(true)
      description("Total lifetime punches earned (one per completed wash).")
    end

    attribute :redeemed_count, :integer do
      default(0)
      allow_nil?(false)
      public?(true)
      description("Total free washes redeemed against this card.")
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :customer, MobileCarWash.Accounts.Customer do
      allow_nil?(false)
      public?(true)
    end
  end

  identities do
    identity(:unique_customer, [:customer_id])
  end

  actions do
    defaults([:read])

    create :create do
      accept([:customer_id])
    end

    update :add_punch do
      require_atomic?(false)

      change(fn changeset, _ ->
        current = Ash.Changeset.get_data(changeset, :punch_count) || 0
        Ash.Changeset.change_attribute(changeset, :punch_count, current + 1)
      end)
    end

    update :redeem do
      require_atomic?(false)

      change(fn changeset, _ ->
        current = Ash.Changeset.get_data(changeset, :redeemed_count) || 0
        Ash.Changeset.change_attribute(changeset, :redeemed_count, current + 1)
      end)
    end
  end
end
