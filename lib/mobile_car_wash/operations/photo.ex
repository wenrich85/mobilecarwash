defmodule MobileCarWash.Operations.Photo do
  @moduledoc """
  Photo attached to an appointment — before/after shots, customer problem areas,
  or step completion documentation.

  Photo types:
  - :before — taken by technician at start of job
  - :after — taken by technician at completion
  - :problem_area — uploaded by customer to highlight areas needing attention
  - :step_completion — taken by technician during a specific checklist step

  Car parts (for detailed documentation):
  - :exterior — body panels, hood, doors
  - :windows — windshield, side windows, rear window
  - :wheels — tires, rims, wheel wells
  - :interior — dashboard, seats, carpets, floor mats
  - :trunk — boot/trunk area
  - :engine_bay — under the hood
  - :undercarriage — chassis, underside
  - :mirrors — side and rear view mirrors
  - :headlights_taillights — lighting assembly
  - :bumper — front and rear bumpers
  - :roof — roof panel and trim
  - :sunroof — sunroof area
  """
  use Ash.Resource,
    otp_app: :mobile_car_wash,
    domain: MobileCarWash.Operations,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "photos"
    repo MobileCarWash.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :file_path, :string do
      allow_nil? false
      public? true
    end

    attribute :original_filename, :string do
      public? true
    end

    attribute :content_type, :string do
      public? true
    end

    attribute :photo_type, :atom do
      constraints one_of: [:before, :after, :problem_area, :step_completion]
      allow_nil? false
      public? true
    end

    attribute :caption, :string do
      public? true
    end

    attribute :uploaded_by, :atom do
      constraints one_of: [:customer, :technician]
      default :technician
      public? true
    end

    attribute :car_part, :atom do
      constraints one_of: [
        :exterior, :windows, :wheels, :interior, :trunk, :engine_bay,
        :undercarriage, :mirrors, :headlights_taillights, :bumper, :roof, :sunroof
      ]
      allow_nil? true
      public? true
      description "Specific part of the car being documented (optional)"
    end

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :appointment, MobileCarWash.Scheduling.Appointment do
      allow_nil? false
    end

    belongs_to :checklist_item, MobileCarWash.Operations.ChecklistItem do
      allow_nil? true
    end
  end

  actions do
    defaults [:read, :destroy]

    create :upload do
      accept [:file_path, :original_filename, :content_type, :photo_type, :caption, :uploaded_by, :car_part]
    end

    read :for_appointment do
      argument :appointment_id, :uuid, allow_nil?: false
      filter expr(appointment_id == ^arg(:appointment_id))
    end

    read :problem_areas do
      argument :appointment_id, :uuid, allow_nil?: false
      filter expr(appointment_id == ^arg(:appointment_id) and photo_type == :problem_area)
    end

    read :before_after do
      argument :appointment_id, :uuid, allow_nil?: false
      filter expr(appointment_id == ^arg(:appointment_id) and photo_type in [:before, :after])
    end
  end
end
