defmodule MobileCarWash.Scheduling.BlockAvailability do
  @moduledoc """
  Queries that tell the booking UI which AppointmentBlocks are open for a
  customer to book into. A block is bookable when:
    * its status is `:open`,
    * its `closes_at` is still in the future, and
    * its appointment count hasn't reached capacity.
  """
  alias MobileCarWash.Scheduling.AppointmentBlock

  require Ash.Query

  @doc "Open blocks for the given service on the calendar date of `date_dt`, chronological."
  def open_blocks_for_service(service_id, %DateTime{} = date_dt) do
    date = DateTime.to_date(date_dt)
    open_blocks_for_service_range(service_id, date, date)
  end

  @doc "Open blocks for the given service across an inclusive date range."
  def open_blocks_for_service_range(service_id, %Date{} = start_date, %Date{} = end_date) do
    range_start = DateTime.new!(start_date, ~T[00:00:00])
    range_end = DateTime.new!(end_date, ~T[23:59:59])
    now = DateTime.utc_now()

    AppointmentBlock
    |> Ash.Query.filter(
      service_type_id == ^service_id and
        status == :open and
        closes_at > ^now and
        starts_at >= ^range_start and
        starts_at <= ^range_end
    )
    |> Ash.Query.load(:appointment_count)
    |> Ash.Query.sort(starts_at: :asc)
    |> Ash.read!()
    |> Enum.filter(fn b -> b.appointment_count < b.capacity end)
  end
end
