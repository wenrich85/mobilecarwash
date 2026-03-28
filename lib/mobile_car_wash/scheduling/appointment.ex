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

    create :book do
      @doc "Books an appointment — the primary action for the booking flow"
      accept [:scheduled_at, :notes, :customer_id, :vehicle_id, :address_id, :service_type_id]

      argument :price_cents, :integer, allow_nil?: false
      argument :duration_minutes, :integer, allow_nil?: false
      argument :discount_cents, :integer, default: 0

      change set_attribute(:price_cents, arg(:price_cents))
      change set_attribute(:duration_minutes, arg(:duration_minutes))
      change set_attribute(:discount_cents, arg(:discount_cents))
      change set_attribute(:status, :pending)

      validate compare(:scheduled_at, greater_than: &DateTime.utc_now/0),
        message: "must be in the future"
    end

    read :for_customer do
      argument :customer_id, :uuid, allow_nil?: false
      filter expr(customer_id == ^arg(:customer_id))
    end

    read :upcoming do
      argument :customer_id, :uuid, allow_nil?: false

      filter expr(
               customer_id == ^arg(:customer_id) and
                 status in [:pending, :confirmed] and
                 scheduled_at > ^DateTime.utc_now()
             )
    end

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
