defmodule MobileCarWash.Scheduling.Appointment do
  @moduledoc """
  An appointment for a car wash service. Tracks the full lifecycle
  from pending → confirmed → in_progress → completed (or cancelled).
  """
  use Ash.Resource,
    otp_app: :mobile_car_wash,
    domain: MobileCarWash.Scheduling,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "appointments"
    repo MobileCarWash.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :scheduled_at, :utc_datetime do
      allow_nil? false
      public? true
    end

    attribute :duration_minutes, :integer do
      allow_nil? false
      public? true
    end

    attribute :status, :atom do
      constraints one_of: [:pending, :confirmed, :in_progress, :completed, :cancelled]
      default :pending
      allow_nil? false
      public? true
    end

    attribute :price_cents, :integer do
      allow_nil? false
      public? true
    end

    attribute :discount_cents, :integer do
      default 0
      public? true
    end

    attribute :notes, :string do
      public? true
    end

    attribute :cancellation_reason, :string do
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :customer, MobileCarWash.Accounts.Customer do
      allow_nil? false
    end

    belongs_to :vehicle, MobileCarWash.Fleet.Vehicle do
      allow_nil? false
    end

    belongs_to :address, MobileCarWash.Fleet.Address do
      allow_nil? false
    end

    belongs_to :service_type, MobileCarWash.Scheduling.ServiceType do
      allow_nil? false
    end

    # Nullable — assigned later or auto-assigned (solo operator for MVP)
    belongs_to :technician, MobileCarWash.Operations.Technician do
      allow_nil? true
    end
  end

  actions do
    defaults [:read, create: :*, update: :*]

    update :confirm do
      change set_attribute(:status, :confirmed)
    end

    update :start do
      change set_attribute(:status, :in_progress)
    end

    update :complete do
      change set_attribute(:status, :completed)
    end

    update :cancel do
      accept [:cancellation_reason]
      change set_attribute(:status, :cancelled)
    end
  end
end
