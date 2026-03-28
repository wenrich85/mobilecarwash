defmodule MobileCarWash.Fleet.Address do
  @moduledoc """
  A service address where a customer wants their car washed.
  """
  use Ash.Resource,
    otp_app: :mobile_car_wash,
    domain: MobileCarWash.Fleet,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "addresses"
    repo MobileCarWash.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :street, :string do
      allow_nil? false
      public? true
    end

    attribute :city, :string do
      allow_nil? false
      public? true
    end

    attribute :state, :string do
      allow_nil? false
      default "TX"
      public? true
    end

    attribute :zip, :string do
      allow_nil? false
      public? true
    end

    attribute :latitude, :float do
      public? true
    end

    attribute :longitude, :float do
      public? true
    end

    attribute :is_default, :boolean do
      default false
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :customer, MobileCarWash.Accounts.Customer do
      allow_nil? false
    end
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end
end
