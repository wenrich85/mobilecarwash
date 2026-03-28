defmodule MobileCarWash.Operations.AppointmentChecklist do
  @moduledoc """
  A live checklist instance created when an appointment starts.
  Generated from a Procedure (SOP) — each ProcedureStep becomes a ChecklistItem.
  The technician checks off items as they work. This is the E-Myth system in action.
  """
  use Ash.Resource,
    otp_app: :mobile_car_wash,
    domain: MobileCarWash.Operations,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "appointment_checklists"
    repo MobileCarWash.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :status, :atom do
      constraints one_of: [:not_started, :in_progress, :completed]
      default :not_started
      allow_nil? false
      public? true
    end

    attribute :started_at, :utc_datetime do
      public? true
    end

    attribute :completed_at, :utc_datetime do
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :appointment, MobileCarWash.Scheduling.Appointment do
      allow_nil? false
    end

    belongs_to :procedure, MobileCarWash.Operations.Procedure do
      allow_nil? false
    end

    has_many :items, MobileCarWash.Operations.ChecklistItem do
      destination_attribute :checklist_id
    end
  end

  actions do
    defaults [:read, create: :*, update: :*]

    update :start_checklist do
      change set_attribute(:status, :in_progress)
      change set_attribute(:started_at, &DateTime.utc_now/0)
    end

    update :complete_checklist do
      change set_attribute(:status, :completed)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
    end
  end
end
