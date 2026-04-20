defmodule MobileCarWash.Operations.ChecklistItem do
  @moduledoc """
  A single item in an appointment checklist — corresponds to one ProcedureStep.
  Tracks actual time spent vs estimated time for process optimization.
  """
  use Ash.Resource,
    otp_app: :mobile_car_wash,
    domain: MobileCarWash.Operations,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("checklist_items")
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

    attribute :completed, :boolean do
      default(false)
      public?(true)
    end

    attribute :started_at, :utc_datetime do
      public?(true)
      description("When the technician started this step")
    end

    attribute :completed_at, :utc_datetime do
      public?(true)
    end

    attribute :actual_seconds, :integer do
      public?(true)
      description("Actual time in seconds — for comparing against estimated_minutes")
    end

    attribute :notes, :string do
      public?(true)
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :checklist, MobileCarWash.Operations.AppointmentChecklist do
      allow_nil?(false)
    end

    belongs_to :procedure_step, MobileCarWash.Operations.ProcedureStep do
      allow_nil?(false)
    end
  end

  actions do
    defaults([:read, create: :*, update: :*])

    update :start_step do
      change(set_attribute(:started_at, &DateTime.utc_now/0))
    end

    update :check do
      require_atomic?(false)
      change(set_attribute(:completed, true))
      change(set_attribute(:completed_at, &DateTime.utc_now/0))

      change(
        after_action(fn _changeset, record, _context ->
          # Calculate actual_seconds from started_at to completed_at
          if record.started_at && record.completed_at do
            seconds = DateTime.diff(record.completed_at, record.started_at)

            {:ok, updated} =
              record
              |> Ash.Changeset.for_update(:update, %{actual_seconds: seconds})
              |> Ash.update()

            {:ok, updated}
          else
            {:ok, record}
          end
        end)
      )
    end

    update :uncheck do
      change(set_attribute(:completed, false))
      change(set_attribute(:completed_at, nil))
      change(set_attribute(:actual_seconds, nil))
    end

    update :add_note do
      accept([:notes])
    end
  end
end
