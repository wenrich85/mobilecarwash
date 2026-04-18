defmodule MobileCarWash.Scheduling.RecurringAppointmentScheduler do
  @moduledoc """
  Oban cron worker that runs daily at 6am.
  Looks 7 days ahead and creates appointments from active recurring schedules
  by booking each into an open AppointmentBlock on its preferred day.
  """
  use Oban.Worker, queue: :default, max_attempts: 1

  alias MobileCarWash.Scheduling.{
    Appointment,
    BlockAvailability,
    BlockGenerator,
    RecurringSchedule,
    ServiceType
  }

  alias MobileCarWash.Operations.Technician

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

    with {:ok, block} <- find_or_generate_block(service_type, date, schedule.preferred_time) do
      Appointment
      |> Ash.Changeset.for_create(:book, %{
        customer_id: schedule.customer_id,
        vehicle_id: schedule.vehicle_id,
        address_id: schedule.address_id,
        service_type_id: schedule.service_type_id,
        scheduled_at: block.starts_at,
        appointment_block_id: block.id,
        price_cents: service_type.base_price_cents,
        duration_minutes: service_type.duration_minutes,
        notes: "Auto-scheduled (recurring)"
      })
      |> Ash.Changeset.force_change_attribute(:recurring_schedule_id, schedule.id)
      |> Ash.create()
    end
  end

  defp find_or_generate_block(service_type, date, preferred_time) do
    case open_block_closest_to(service_type.id, date, preferred_time) do
      nil ->
        with :ok <- ensure_blocks_for(date) do
          case open_block_closest_to(service_type.id, date, preferred_time) do
            nil -> {:error, :no_block_available}
            block -> {:ok, block}
          end
        end

      block ->
        {:ok, block}
    end
  end

  defp open_block_closest_to(service_type_id, date, preferred_time) do
    BlockAvailability.open_blocks_for_service_range(service_type_id, date, date)
    |> Enum.min_by(
      fn block ->
        abs(block.starts_at.hour - preferred_time.hour)
      end,
      fn -> nil end
    )
  end

  defp ensure_blocks_for(date) do
    case default_technician() do
      nil ->
        {:error, :no_technician}

      tech ->
        BlockGenerator.generate_for_date(date, technician_id: tech.id)
    end
  end

  defp default_technician do
    Technician
    |> Ash.Query.filter(active == true)
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.Query.limit(1)
    |> Ash.read!()
    |> List.first()
  end
end
