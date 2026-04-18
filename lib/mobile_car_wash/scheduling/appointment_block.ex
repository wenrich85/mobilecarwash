defmodule MobileCarWash.Scheduling.AppointmentBlock do
  @moduledoc """
  A time window that holds up to `capacity` appointments of a single service type.
  Assigned to one technician (and one van). Bookings are accepted until either
  `capacity` is reached or `closes_at` passes — at which point the route optimizer
  runs, assigns arrival times to each appointment, and sets status to `:scheduled`.
  """
  use Ash.Resource,
    otp_app: :mobile_car_wash,
    domain: MobileCarWash.Scheduling,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "appointment_blocks"
    repo MobileCarWash.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :starts_at, :utc_datetime do
      allow_nil? false
      public? true
    end

    attribute :ends_at, :utc_datetime do
      allow_nil? false
      public? true
    end

    attribute :closes_at, :utc_datetime do
      allow_nil? false
      public? true
      description "Cutoff for accepting new bookings (default: midnight the day before starts_at)"
    end

    attribute :capacity, :integer do
      allow_nil? false
      default 3
      public? true
    end

    attribute :status, :atom do
      constraints one_of: [:open, :scheduled, :in_progress, :completed, :cancelled]
      default :open
      allow_nil? false
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :service_type, MobileCarWash.Scheduling.ServiceType do
      allow_nil? false
    end

    belongs_to :technician, MobileCarWash.Operations.Technician do
      allow_nil? false
    end

    belongs_to :van, MobileCarWash.Operations.Van do
      allow_nil? true
    end

    has_many :appointments, MobileCarWash.Scheduling.Appointment do
      destination_attribute :appointment_block_id
    end
  end

  aggregates do
    count :appointment_count, :appointments
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [
        :service_type_id,
        :technician_id,
        :van_id,
        :starts_at,
        :ends_at,
        :closes_at,
        :capacity,
        :status
      ]
    end

    update :update do
      primary? true
      require_atomic? false
      accept [
        :starts_at,
        :ends_at,
        :closes_at,
        :capacity,
        :status,
        :technician_id,
        :van_id
      ]
    end
  end

  @doc """
  True when the block is accepting bookings: status is :open and closes_at
  hasn't passed. Capacity check is done separately by the availability query
  (since it needs to count appointments, which isn't an attribute).
  """
  def open?(%{status: :open, closes_at: %DateTime{} = closes_at}) do
    DateTime.compare(closes_at, DateTime.utc_now()) == :gt
  end

  def open?(_), do: false
end
