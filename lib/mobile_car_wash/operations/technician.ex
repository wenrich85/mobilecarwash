defmodule MobileCarWash.Operations.Technician do
  @moduledoc """
  A technician who performs car washes. For MVP, there's only one (the owner).
  Multi-technician support is Phase 2.
  """
  use Ash.Resource,
    otp_app: :mobile_car_wash,
    domain: MobileCarWash.Operations,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "technicians"
    repo MobileCarWash.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :phone, :string do
      public? true
    end

    attribute :active, :boolean do
      default true
      public? true
    end

    attribute :pay_rate_cents, :integer do
      default 2500
      public? true
      description "Per-wash pay rate in cents (e.g., 2500 = $25.00/wash)"
    end

    attribute :pay_period_start_day, :integer do
      default 1
      public? true
      description "Day of week pay period starts: 1=Monday..7=Sunday"
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :van, MobileCarWash.Operations.Van do
      allow_nil? true
    end

    belongs_to :user_account, MobileCarWash.Accounts.Customer do
      allow_nil? true
      description "Links this technician to a login account"
    end
  end

  actions do
    defaults [:read, create: :*, update: :*]
  end
end
