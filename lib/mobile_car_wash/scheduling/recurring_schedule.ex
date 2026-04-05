defmodule MobileCarWash.Scheduling.RecurringSchedule do
  use Ash.Resource,
    otp_app: :mobile_car_wash,
    domain: MobileCarWash.Scheduling,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "recurring_schedules"
    repo MobileCarWash.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :frequency, :atom do
      constraints one_of: [:weekly, :biweekly, :monthly]
      allow_nil? false
      public? true
    end

    attribute :preferred_day, :integer do
      allow_nil? false
      public? true
    end

    attribute :preferred_time, :time do
      allow_nil? false
      public? true
    end

    attribute :active, :boolean do
      default true
      allow_nil? false
      public? true
    end

    attribute :last_scheduled_date, :date do
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :customer, MobileCarWash.Accounts.Customer, allow_nil?: false
    belongs_to :vehicle, MobileCarWash.Fleet.Vehicle, allow_nil?: false
    belongs_to :address, MobileCarWash.Fleet.Address, allow_nil?: false
    belongs_to :service_type, MobileCarWash.Scheduling.ServiceType, allow_nil?: false
    belongs_to :subscription, MobileCarWash.Billing.Subscription, allow_nil?: true
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:frequency, :preferred_day, :preferred_time]
    end

    update :deactivate do
      change set_attribute(:active, false)
    end

    update :activate do
      change set_attribute(:active, true)
    end

    update :mark_scheduled do
      accept [:last_scheduled_date]
    end

    read :active_schedules do
      filter expr(active == true)
    end

    read :for_customer do
      argument :customer_id, :uuid, allow_nil?: false
      filter expr(customer_id == ^arg(:customer_id))
    end
  end
end
