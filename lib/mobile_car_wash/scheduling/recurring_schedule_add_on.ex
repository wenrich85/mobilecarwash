defmodule MobileCarWash.Scheduling.RecurringScheduleAddOn do
  @moduledoc """
  Join row linking a recurring schedule to an add-on. Future auto-generated
  occurrences inherit the schedule's add-on set (charged off-session per
  occurrence by the scheduler).
  """
  use Ash.Resource,
    otp_app: :mobile_car_wash,
    domain: MobileCarWash.Scheduling,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("recurring_schedule_add_ons")
    repo(MobileCarWash.Repo)
  end

  attributes do
    uuid_primary_key(:id)
    create_timestamp(:inserted_at)
  end

  relationships do
    belongs_to :recurring_schedule, MobileCarWash.Scheduling.RecurringSchedule do
      allow_nil?(false)
    end

    belongs_to :add_on, MobileCarWash.Scheduling.AddOn do
      allow_nil?(false)
    end
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      primary?(true)
      accept([:recurring_schedule_id, :add_on_id])
    end

    read :for_schedule do
      argument(:recurring_schedule_id, :uuid, allow_nil?: false)
      filter(expr(recurring_schedule_id == ^arg(:recurring_schedule_id)))
    end
  end
end
