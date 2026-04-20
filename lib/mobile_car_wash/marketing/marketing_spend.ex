defmodule MobileCarWash.Marketing.MarketingSpend do
  @moduledoc """
  One row per channel + day (or campaign). Denominator of every CAC
  calculation. Admin-entered for now — later phases can ingest from
  Google Ads / Meta Ads APIs into the same table.
  """
  use Ash.Resource,
    otp_app: :mobile_car_wash,
    domain: MobileCarWash.Marketing,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("marketing_spends")
    repo(MobileCarWash.Repo)

    references do
      reference(:channel, on_delete: :restrict)
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute :spent_on, :date do
      allow_nil?(false)
      public?(true)
    end

    attribute :amount_cents, :integer do
      allow_nil?(false)
      public?(true)
      constraints(min: 0)
    end

    attribute :notes, :string do
      public?(true)
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :channel, MobileCarWash.Marketing.AcquisitionChannel do
      allow_nil?(false)
      public?(true)
    end
  end

  actions do
    defaults([:read, :destroy, update: :*])

    create :record do
      accept([:channel_id, :spent_on, :amount_cents, :notes])
    end

    read :in_range do
      argument(:from, :date, allow_nil?: false)
      argument(:to, :date, allow_nil?: false)
      filter(expr(spent_on >= ^arg(:from) and spent_on <= ^arg(:to)))
      prepare(build(sort: [spent_on: :desc, inserted_at: :desc]))
    end

    read :by_channel do
      argument(:channel_id, :uuid, allow_nil?: false)
      filter(expr(channel_id == ^arg(:channel_id)))
      prepare(build(sort: [spent_on: :desc]))
    end

    read :recent do
      argument(:limit, :integer, default: 20)
      prepare(build(sort: [inserted_at: :desc]))
      prepare(build(limit: 20))
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
