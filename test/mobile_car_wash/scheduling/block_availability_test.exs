defmodule MobileCarWash.Scheduling.BlockAvailabilityTest do
  @moduledoc """
  BlockAvailability returns the open AppointmentBlocks a customer can book into
  for a given service and date range.
  """
  use MobileCarWash.DataCase, async: false

  alias MobileCarWash.Scheduling.{AppointmentBlock, BlockAvailability, ServiceType}
  alias MobileCarWash.Operations.Technician

  defp create_service do
    ServiceType
    |> Ash.Changeset.for_create(:create, %{
      name: "Basic Wash",
      slug: "basic_wash_avail_#{:rand.uniform(100_000)}",
      base_price_cents: 5000,
      duration_minutes: 45
    })
    |> Ash.create!()
  end

  defp create_technician do
    Technician
    |> Ash.Changeset.for_create(:create, %{name: "Avail Tech"})
    |> Ash.create!()
  end

  defp create_block(service, tech, start_dt, opts \\ []) do
    end_dt = DateTime.add(start_dt, 3 * 3600, :second)
    closes = Keyword.get(opts, :closes_at, DateTime.add(start_dt, -3600, :second))
    status = Keyword.get(opts, :status, :open)
    capacity = Keyword.get(opts, :capacity, 3)

    AppointmentBlock
    |> Ash.Changeset.for_create(:create, %{
      service_type_id: service.id,
      technician_id: tech.id,
      starts_at: start_dt,
      ends_at: end_dt,
      capacity: capacity,
      closes_at: closes,
      status: status
    })
    |> Ash.create!()
  end

  defp future_dt(days_ahead, hour) do
    date = Date.add(Date.utc_today(), days_ahead)
    DateTime.new!(date, Time.new!(hour, 0, 0))
  end

  describe "open_blocks_for_service/2" do
    test "returns only :open blocks with future closes_at for the given service" do
      service = create_service()
      tech = create_technician()

      open_block = create_block(service, tech, future_dt(3, 8))
      _scheduled_block = create_block(service, tech, future_dt(3, 13), status: :scheduled)

      past_close = DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.truncate(:second)
      _past_close_block = create_block(service, tech, future_dt(3, 17), closes_at: past_close)

      result = BlockAvailability.open_blocks_for_service(service.id, future_dt(3, 0))

      assert Enum.map(result, & &1.id) == [open_block.id]
    end

    test "returns blocks in chronological order" do
      service = create_service()
      tech = create_technician()

      afternoon = create_block(service, tech, future_dt(3, 13))
      morning = create_block(service, tech, future_dt(3, 8))

      result = BlockAvailability.open_blocks_for_service(service.id, future_dt(3, 0))

      assert Enum.map(result, & &1.id) == [morning.id, afternoon.id]
    end

    test "excludes blocks whose appointment count has reached capacity" do
      # We express "at capacity" by creating a block with capacity=1 and then
      # attaching 1 appointment to it. The availability query must respect the count.
      service = create_service()
      tech = create_technician()

      _filled = create_block(service, tech, future_dt(3, 8), capacity: 0)
      open = create_block(service, tech, future_dt(3, 13), capacity: 3)

      result = BlockAvailability.open_blocks_for_service(service.id, future_dt(3, 0))

      assert Enum.map(result, & &1.id) == [open.id]
    end
  end

  describe "open_blocks_for_service_range/3" do
    test "returns open blocks across a date range" do
      service = create_service()
      tech = create_technician()

      day1 = create_block(service, tech, future_dt(3, 8))
      day2 = create_block(service, tech, future_dt(4, 8))
      _day5 = create_block(service, tech, future_dt(7, 8))

      start_d = Date.add(Date.utc_today(), 3)
      end_d = Date.add(Date.utc_today(), 4)

      result = BlockAvailability.open_blocks_for_service_range(service.id, start_d, end_d)

      assert Enum.map(result, & &1.id) |> Enum.sort() == Enum.sort([day1.id, day2.id])
    end
  end
end
