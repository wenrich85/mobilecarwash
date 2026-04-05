defmodule MobileCarWash.Scheduling.RecurringAppointmentScheduler do
  @moduledoc """
  Oban cron worker that runs daily at 6am.
  Looks 7 days ahead and creates appointments from active recurring schedules.
  """
  use Oban.Worker, queue: :default, max_attempts: 1

  alias MobileCarWash.Scheduling.{RecurringSchedule, Appointment, ServiceType, Availability}

  require Ash.Query
  require Logger

  @horizon_days 7

  @impl Oban.Worker
  def perform(_job) do
    today = Date.utc_today()
    horizon = Date.add(today, @horizon_days)

    schedules =
      RecurringSchedule
      |> Ash.Query.for_read(:active_schedules)
      |> Ash.read!()

    Enum.each(schedules, fn schedule ->
      next_dates = calculate_next_dates(schedule, today, horizon)

      Enum.each(next_dates, fn date ->
        unless appointment_exists?(schedule, date) do
          case create_appointment(schedule, date) do
            {:ok, _appointment} ->
              schedule
              |> Ash.Changeset.for_update(:mark_scheduled, %{last_scheduled_date: date})
              |> Ash.update!()

              Logger.info("Recurring appointment created for schedule #{schedule.id} on #{date}")

            {:error, reason} ->
              Logger.warning("Skipped recurring appointment for schedule #{schedule.id} on #{date}: #{inspect(reason)}")
          end
        end
      end)
    end)

    :ok
  end

  defp calculate_next_dates(schedule, today, horizon) do
    # Generate candidate dates within [today+1, horizon]
    tomorrow = Date.add(today, 1)

    Date.range(tomorrow, horizon)
    |> Enum.filter(fn date ->
      Date.day_of_week(date) == schedule.preferred_day && matches_frequency?(schedule, date)
    end)
  end

  defp matches_frequency?(schedule, date) do
    case schedule.frequency do
      :weekly ->
        true

      :biweekly ->
        case schedule.last_scheduled_date do
          nil -> true
          last -> Date.diff(date, last) >= 12
        end

      :monthly ->
        case schedule.last_scheduled_date do
          nil -> true
          last -> Date.diff(date, last) >= 26
        end
    end
  end

  defp appointment_exists?(schedule, date) do
    {:ok, day_start} = DateTime.new(date, ~T[00:00:00])
    {:ok, day_end} = DateTime.new(Date.add(date, 1), ~T[00:00:00])

    Appointment
    |> Ash.Query.filter(
      recurring_schedule_id == ^schedule.id and
        scheduled_at >= ^day_start and
        scheduled_at < ^day_end
    )
    |> Ash.read!()
    |> Enum.any?()
  end

  defp create_appointment(schedule, date) do
    {:ok, service_type} = Ash.get(ServiceType, schedule.service_type_id)
    {:ok, scheduled_at} = DateTime.new(date, schedule.preferred_time)

    # Check availability
    existing =
      Appointment
      |> Ash.Query.filter(
        scheduled_at >= ^DateTime.add(scheduled_at, -3600) and
          scheduled_at <= ^DateTime.add(scheduled_at, 3600) and
          status in [:pending, :confirmed, :in_progress]
      )
      |> Ash.read!()

    existing_maps = Enum.map(existing, fn a -> %{scheduled_at: a.scheduled_at, duration_minutes: a.duration_minutes} end)

    if Availability.slot_available?(scheduled_at, service_type.duration_minutes, existing_maps) do
      Appointment
      |> Ash.Changeset.for_create(:book, %{
        customer_id: schedule.customer_id,
        vehicle_id: schedule.vehicle_id,
        address_id: schedule.address_id,
        service_type_id: schedule.service_type_id,
        scheduled_at: scheduled_at,
        price_cents: service_type.base_price_cents,
        duration_minutes: service_type.duration_minutes,
        notes: "Auto-scheduled (recurring)"
      })
      |> Ash.Changeset.force_change_attribute(:recurring_schedule_id, schedule.id)
      |> Ash.create()
    else
      {:error, :slot_unavailable}
    end
  end
end
