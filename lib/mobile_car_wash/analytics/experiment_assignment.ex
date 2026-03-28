defmodule MobileCarWash.Analytics.ExperimentAssignment do
  @moduledoc """
  Assigns a session to an experiment variant. Ensures each user
  sees a consistent variant throughout their session.
  """
  use Ash.Resource,
    otp_app: :mobile_car_wash,
    domain: MobileCarWash.Analytics,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "experiment_assignments"
    repo MobileCarWash.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :session_id, :string do
      allow_nil? false
      public? true
    end

    attribute :variant, :string do
      allow_nil? false
      public? true
    end

    create_timestamp :assigned_at
  end

  relationships do
    belongs_to :experiment, MobileCarWash.Analytics.Experiment do
      allow_nil? false
    end
  end

  identities do
    identity :unique_session_experiment, [:session_id, :experiment_id]
  end

  actions do
    defaults [:read]

    create :assign do
      accept [:session_id, :variant, :experiment_id]
    end
  end
end
