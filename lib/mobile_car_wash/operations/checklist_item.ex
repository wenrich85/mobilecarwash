defmodule MobileCarWash.Operations.ChecklistItem do
  @moduledoc """
  A single item in an appointment checklist — corresponds to one ProcedureStep.
  The technician taps to complete each item during the wash.
  """
  use Ash.Resource,
    otp_app: :mobile_car_wash,
    domain: MobileCarWash.Operations,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "checklist_items"
    repo MobileCarWash.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :step_number, :integer do
      allow_nil? false
      public? true
    end

    attribute :title, :string do
      allow_nil? false
      public? true
    end

    attribute :description, :string do
      public? true
    end

    attribute :required, :boolean do
      default true
      public? true
    end

    attribute :completed, :boolean do
      default false
      public? true
    end

    attribute :completed_at, :utc_datetime do
      public? true
    end

    attribute :notes, :string do
      public? true
      description "Technician notes for this step (e.g., 'scratch found on driver door')"
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :checklist, MobileCarWash.Operations.AppointmentChecklist do
      allow_nil? false
    end

    belongs_to :procedure_step, MobileCarWash.Operations.ProcedureStep do
      allow_nil? false
    end
  end

  actions do
    defaults [:read, create: :*, update: :*]

    update :check do
      change set_attribute(:completed, true)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
    end

    update :uncheck do
      change set_attribute(:completed, false)
      change set_attribute(:completed_at, nil)
    end

    update :add_note do
      accept [:notes]
    end
  end
end
