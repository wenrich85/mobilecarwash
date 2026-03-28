defmodule MobileCarWash.Operations.Procedure do
  @moduledoc """
  A Standard Operating Procedure (SOP) — the E-Myth "system."
  Every repeatable business process is documented as a procedure
  with ordered steps. When a technician starts an appointment,
  a live checklist is created from the procedure.

  Categories: wash, admin, customer_service, safety
  """
  use Ash.Resource,
    otp_app: :mobile_car_wash,
    domain: MobileCarWash.Operations,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "procedures"
    repo MobileCarWash.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :slug, :string do
      allow_nil? false
      public? true
    end

    attribute :description, :string do
      public? true
    end

    attribute :category, :atom do
      constraints one_of: [:wash, :admin, :customer_service, :safety]
      default :wash
      public? true
    end

    attribute :active, :boolean do
      default true
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    # Optional link to a service type — "this procedure is for Basic Wash"
    belongs_to :service_type, MobileCarWash.Scheduling.ServiceType do
      allow_nil? true
    end

    has_many :steps, MobileCarWash.Operations.ProcedureStep do
      sort step_number: :asc
    end
  end

  identities do
    identity :unique_slug, [:slug]
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end
end
