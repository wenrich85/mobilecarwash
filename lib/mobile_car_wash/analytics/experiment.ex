defmodule MobileCarWash.Analytics.Experiment do
  @moduledoc """
  A/B test definition. Each experiment has a hypothesis, variants,
  and tracks results to determine statistical significance.
  """
  use Ash.Resource,
    otp_app: :mobile_car_wash,
    domain: MobileCarWash.Analytics,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "experiments"
    repo MobileCarWash.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :hypothesis, :string do
      public? true
      description "What we believe will happen and why"
    end

    attribute :status, :atom do
      constraints one_of: [:draft, :running, :concluded]
      default :draft
      allow_nil? false
      public? true
    end

    attribute :variants, :map do
      default %{"control" => %{}, "treatment" => %{}}
      public? true
    end

    attribute :started_at, :utc_datetime do
      public? true
    end

    attribute :concluded_at, :utc_datetime do
      public? true
    end

    attribute :results, :map do
      public? true
      description "Conversion rates, p-value, winner"
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_name, [:name]
  end

  actions do
    defaults [:read, create: :*, update: :*]

    update :start_experiment do
      change set_attribute(:status, :running)
      change set_attribute(:started_at, &DateTime.utc_now/0)
    end

    update :conclude do
      accept [:results]
      change set_attribute(:status, :concluded)
      change set_attribute(:concluded_at, &DateTime.utc_now/0)
    end
  end
end
