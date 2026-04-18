defmodule MobileCarWash.Scheduling.BlockGenerator do
  @moduledoc """
  Creates upcoming AppointmentBlock rows from BlockTemplate rows.

  For each active service on a given date, looks up matching templates
  (service + day_of_week + active). Each template produces one block per
  target date. Sundays and BlockedDates are skipped. Idempotent.

  **Backward compat**: if a service has NO templates defined at all, falls
  back to a sensible default of morning (8am) + afternoon (1pm) so fresh
  envs and unmodified tests keep working without seed data.
  """
  alias MobileCarWash.Scheduling.{AppointmentBlock, BlockedDate, BlockTemplate, ServiceType}

  require Ash.Query

  @default_slot_hours [8, 13]

  @doc "Creates blocks for a single date. Pass `technician_id:` for the tech owning the block."
  def generate_for_date(%Date{} = date, opts) do
    cond do
      Date.day_of_week(date) == 7 -> :ok
      blocked?(date) -> :ok
      true -> do_generate(date, opts)
    end
  end

  @doc "Creates blocks for the next `days` days starting tomorrow."
  def generate_ahead(days, opts) when is_integer(days) and days > 0 do
    today = Date.utc_today()

    Enum.each(1..days, fn offset ->
      generate_for_date(Date.add(today, offset), opts)
    end)

    :ok
  end

  # --- Internals ---

  defp blocked?(date) do
    BlockedDate
    |> Ash.Query.filter(date == ^date)
    |> Ash.read!()
    |> Enum.any?()
  end

  defp do_generate(date, opts) do
    technician_id = Keyword.fetch!(opts, :technician_id)
    services = active_services()
    day_of_week = Date.day_of_week(date)

    Enum.each(services, fn service ->
      hours = slot_hours_for(service, day_of_week)

      Enum.each(hours, fn hour ->
        starts_at = DateTime.new!(date, Time.new!(hour, 0, 0))
        window = service.window_minutes || service.duration_minutes * 3 + 60
        ends_at = DateTime.add(starts_at, window * 60, :second)
        closes_at = DateTime.new!(Date.add(date, -1), ~T[23:59:59])

        unless block_exists?(service.id, starts_at) do
          {:ok, _} =
            AppointmentBlock
            |> Ash.Changeset.for_create(:create, %{
              service_type_id: service.id,
              technician_id: technician_id,
              starts_at: starts_at,
              ends_at: ends_at,
              closes_at: closes_at,
              capacity: service.block_capacity,
              status: :open
            })
            |> Ash.create()
        end
      end)
    end)

    :ok
  end

  # Returns the hours at which blocks should start for this service on this
  # day. Prefers active templates matching (service, day_of_week); falls back
  # to the default slot hours only if the service has NO templates at all
  # (legacy / unmigrated data).
  defp slot_hours_for(service, day_of_week) do
    all_templates =
      BlockTemplate
      |> Ash.Query.filter(service_type_id == ^service.id)
      |> Ash.read!()

    case all_templates do
      [] ->
        @default_slot_hours

      templates ->
        templates
        |> Enum.filter(fn t -> t.active and t.day_of_week == day_of_week end)
        |> Enum.map(& &1.start_hour)
        |> Enum.sort()
    end
  end

  defp active_services do
    ServiceType
    |> Ash.Query.filter(active == true)
    |> Ash.read!()
  end

  defp block_exists?(service_id, starts_at) do
    AppointmentBlock
    |> Ash.Query.filter(service_type_id == ^service_id and starts_at == ^starts_at)
    |> Ash.read!()
    |> Enum.any?()
  end
end
