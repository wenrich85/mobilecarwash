defmodule MobileCarWash.Scheduling.BlockedDate do
  use Ash.Resource,
    otp_app: :mobile_car_wash,
    domain: MobileCarWash.Scheduling,
    data_layer: AshPostgres.DataLayer

  require Ash.Query

  postgres do
    table("blocked_dates")
    repo(MobileCarWash.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :date, :date do
      allow_nil?(false)
      public?(true)
    end

    attribute :reason, :string do
      public?(true)
    end

    create_timestamp(:inserted_at)
  end

  identities do
    identity(:unique_date, [:date])
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      accept([:date, :reason])
    end

    read :for_range do
      argument(:start_date, :date, allow_nil?: false)
      argument(:end_date, :date, allow_nil?: false)
      filter(expr(date >= ^arg(:start_date) and date <= ^arg(:end_date)))
    end
  end

  @doc "Returns true if the given date is blocked."
  def blocked?(date) do
    __MODULE__
    |> Ash.Query.filter(date == ^date)
    |> Ash.read!()
    |> Enum.any?()
  end
end
