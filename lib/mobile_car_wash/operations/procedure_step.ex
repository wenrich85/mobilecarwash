defmodule MobileCarWash.Operations.ProcedureStep do
  @moduledoc """
  A single step in a Standard Operating Procedure.
  Steps are ordered by step_number and can be required or optional.
  """
  use Ash.Resource,
    otp_app: :mobile_car_wash,
    domain: MobileCarWash.Operations,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("procedure_steps")
    repo(MobileCarWash.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :step_number, :integer do
      allow_nil?(false)
      public?(true)
    end

    attribute :title, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :description, :string do
      public?(true)
    end

    attribute :estimated_minutes, :integer do
      public?(true)
    end

    attribute :required, :boolean do
      default(true)
      public?(true)
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :procedure, MobileCarWash.Operations.Procedure do
      allow_nil?(false)
    end
  end

  actions do
    defaults([:read, :destroy, create: :*, update: :*])
  end
end
