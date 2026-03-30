defmodule MobileCarWash.Scheduling.Availability do
  @moduledoc """
  Generates available time slots for booking appointments.

  Pure functional module — no database dependencies. Accepts existing
  appointments as input so it can be tested without a database.

  Business rules:
  - Operating hours: 8am-6pm Monday-Saturday (configurable)
  - Buffer time between appointments: 15 minutes (configurable)
  - No appointments on Sundays
  - No slots in the past

  Future multi-tech support:
  - Pass `technician_id` option to filter appointments by technician
  """

  @default_open_time ~T[08:00:00]
  @default_close_time ~T[18:00:00]
  @default_buffer_minutes 15
  # Sunday = 7 in Date.day_of_week/1
  @closed_days [7]

  @type slot :: %{starts_at: DateTime.t(), ends_at: DateTime.t()}

  @doc """
  Returns available time slots for a given date and service duration.

  ## Parameters
  - `date` - The date to check availability for
  - `duration_minutes` - How long the service takes
  - `existing_appointments` - List of maps with `:scheduled_at` and `:duration_minutes`
  - `opts` - Optional configuration:
    - `:timezone` - Timezone string (default: "America/Chicago")
    - `:open_time` - Opening time (default: ~T[08:00:00])
    - `:close_time` - Closing time (default: ~T[18:00:00])
    - `:buffer_minutes` - Buffer between appointments (default: 15)
    - `:technician_id` - Filter appointments by technician (future use)

  ## Returns
  List of `%{starts_at: DateTime.t(), ends_at: DateTime.t()}` maps
  """
  @spec available_slots(Date.t(), pos_integer(), list(map()), keyword()) :: [slot()]
  def available_slots(date, duration_minutes, existing_appointments, opts \\ []) do
    timezone = Keyword.get(opts, :timezone, "America/Chicago")
    open_time = Keyword.get(opts, :open_time, @default_open_time)
    close_time = Keyword.get(opts, :close_time, @default_close_time)
    buffer = Keyword.get(opts, :buffer_minutes, @default_buffer_minutes)

    cond do
      closed_day?(date) ->
        []

      past_date?(date) ->
        []

      true ->
        generate_slots(date, duration_minutes, existing_appointments, timezone, open_time, close_time, buffer)
    end
  end

  @doc """
  Checks if a specific datetime is available for a service of the given duration.
  """
  @spec slot_available?(DateTime.t(), pos_integer(), list(map()), keyword()) :: boolean()
  def slot_available?(datetime, duration_minutes, existing_appointments, opts \\ []) do
    buffer = Keyword.get(opts, :buffer_minutes, @default_buffer_minutes)
    open_time = Keyword.get(opts, :open_time, @default_open_time)
    close_time = Keyword.get(opts, :close_time, @default_close_time)

    date = DateTime.to_date(datetime)
    time = DateTime.to_time(datetime)
    end_time = Time.add(time, duration_minutes * 60)

    cond do
      closed_day?(date) -> false
      past_date?(date) -> false
      Time.compare(time, open_time) == :lt -> false
      Time.compare(end_time, close_time) == :gt -> false
      conflicts?(datetime, duration_minutes, existing_appointments, buffer) -> false
      true -> true
    end
  end

  # --- Private ---

  defp generate_slots(date, duration_minutes, existing_appointments, _timezone, open_time, close_time, buffer) do
    slot_step = duration_minutes + buffer
    now = DateTime.utc_now()
    is_today = Date.compare(date, DateTime.to_date(now)) == :eq

    # Generate candidate start times
    open_minutes = time_to_minutes(open_time)
    close_minutes = time_to_minutes(close_time)

    Stream.iterate(open_minutes, &(&1 + slot_step))
    |> Stream.take_while(fn start_min ->
      end_min = start_min + duration_minutes
      end_min <= close_minutes
    end)
    |> Enum.reduce([], fn start_min, acc ->
      start_time = minutes_to_time(start_min)
      end_time = minutes_to_time(start_min + duration_minutes)

      {:ok, starts_at} = DateTime.new(date, start_time)
      {:ok, ends_at} = DateTime.new(date, end_time)

      cond do
        is_today and DateTime.compare(starts_at, now) == :lt -> acc
        conflicts?(starts_at, duration_minutes, existing_appointments, buffer) -> acc
        true -> acc ++ [%{starts_at: starts_at, ends_at: ends_at}]
      end
    end)
  end

  defp conflicts?(starts_at, duration_minutes, existing_appointments, buffer) do
    slot_start = starts_at
    slot_end = DateTime.add(starts_at, duration_minutes * 60)

    Enum.any?(existing_appointments, fn appt ->
      appt_start = appt.scheduled_at
      appt_end = DateTime.add(appt_start, appt.duration_minutes * 60)

      # Add buffer to the existing appointment's window
      appt_start_with_buffer = DateTime.add(appt_start, -buffer * 60)
      appt_end_with_buffer = DateTime.add(appt_end, buffer * 60)

      # Check if new slot overlaps with buffered existing appointment
      DateTime.compare(slot_start, appt_end_with_buffer) == :lt and
        DateTime.compare(slot_end, appt_start_with_buffer) == :gt
    end)
  end

  defp closed_day?(date) do
    Date.day_of_week(date) in @closed_days
  end

  defp past_date?(date) do
    Date.compare(date, Date.utc_today()) == :lt
  end

  defp time_to_minutes(%Time{hour: h, minute: m}), do: h * 60 + m

  defp minutes_to_time(minutes) do
    Time.new!(div(minutes, 60), rem(minutes, 60), 0)
  end
end
