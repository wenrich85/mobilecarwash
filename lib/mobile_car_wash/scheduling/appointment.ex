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

    attribute :referral_code_used, :string do
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

    # Links to the recurring schedule that auto-created this appointment
    belongs_to :recurring_schedule, MobileCarWash.Scheduling.RecurringSchedule do
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
      require_atomic? false

      validate fn changeset, _context ->
        record = changeset.data
        if record.technician_id do
          :ok
        else
          {:error, field: :technician_id, message: "a technician must be assigned before confirming"}
        end
      end

      change set_attribute(:status, :confirmed)
    end

    # Auto-confirm after payment — no technician required yet
    update :payment_confirm do
      change set_attribute(:status, :confirmed)
    end

    update :start do
      require_atomic? false
      change set_attribute(:status, :in_progress)

      change after_action(fn _changeset, record, _context ->
        MobileCarWash.Scheduling.AppointmentTracker.broadcast_started(record.id)
        # SMS: tech is on the way
        %{appointment_id: record.id}
        |> MobileCarWash.Notifications.SMSTechOnTheWayWorker.new(queue: :notifications)
        |> Oban.insert()
        {:ok, record}
      end)
    end

    update :complete do
      require_atomic? false
      change set_attribute(:status, :completed)

      change after_action(fn _changeset, record, _context ->
        MobileCarWash.Scheduling.AppointmentTracker.broadcast_completed(record.id)
        # Enqueue wash completed notification (email + SMS)
        %{appointment_id: record.id}
        |> MobileCarWash.Notifications.WashCompletedWorker.new(queue: :notifications)
        |> Oban.insert()
        %{appointment_id: record.id}
        |> MobileCarWash.Notifications.SMSWashCompletedWorker.new(queue: :notifications)
        |> Oban.insert()
        # Request a review 2 hours after completion
        %{appointment_id: record.id}
        |> MobileCarWash.Notifications.SMSReviewRequestWorker.new(
          queue: :notifications,
          scheduled_at: DateTime.add(DateTime.utc_now(), 2 * 3600)
        )
        |> Oban.insert()
        # Award loyalty punch for this customer
        MobileCarWash.Loyalty.add_punch(record.customer_id)
        {:ok, record}
      end)
    end

    # Technician assignment handled via Scheduling.Dispatch module (direct Ecto for FK)

    update :cancel do
      accept [:cancellation_reason]
      change set_attribute(:status, :cancelled)
    end

    read :todays_appointments do
      prepare fn query, _context ->
        today = Date.utc_today()
        {:ok, day_start} = DateTime.new(today, ~T[00:00:00])
        {:ok, day_end} = DateTime.new(Date.add(today, 1), ~T[00:00:00])

        require Ash.Query
        query
        |> Ash.Query.filter(scheduled_at >= ^day_start and scheduled_at < ^day_end and status != :cancelled)
        |> Ash.Query.sort(scheduled_at: :asc)
      end
    end

    read :for_date do
      argument :date, :date, allow_nil?: false

      prepare fn query, _context ->
        date = Ash.Query.get_argument(query, :date)
        {:ok, day_start} = DateTime.new(date, ~T[00:00:00])
        {:ok, day_end} = DateTime.new(Date.add(date, 1), ~T[00:00:00])

        require Ash.Query
        query
        |> Ash.Query.filter(scheduled_at >= ^day_start and scheduled_at < ^day_end and status != :cancelled)
        |> Ash.Query.sort(scheduled_at: :asc)
      end
    end

    read :unassigned do
      prepare fn query, _context ->
        require Ash.Query
        Ash.Query.filter(query, is_nil(technician_id) and status in [:pending, :confirmed])
      end
    end

    read :active do
      prepare fn query, _context ->
        require Ash.Query
        Ash.Query.filter(query, status == :in_progress)
      end
    end
  end
end
