defmodule MobileCarWash.Scheduling.BlockGeneratorTest do
  @moduledoc """
  BlockGenerator creates upcoming AppointmentBlock rows from a schedule template.
  For MVP the template is hardcoded: Mon–Sat, 2 basic-wash blocks per day
  (morning + afternoon), skipping Sundays and BlockedDates.
  """
  use MobileCarWash.DataCase, async: false

  alias MobileCarWash.Scheduling.{AppointmentBlock, BlockGenerator, BlockedDate, ServiceType}
  alias MobileCarWash.Operations.Technician

  require Ash.Query

  defp create_basic_wash do
    ServiceType
    |> Ash.Changeset.for_create(:create, %{
      name: "Basic Wash",
      slug: "basic_wash_gen_#{:rand.uniform(100_000)}",
      base_price_cents: 5000,
      duration_minutes: 45
    })
    |> Ash.create!()
  end

  defp create_technician do
    Technician
    |> Ash.Changeset.for_create(:create, %{name: "Gen Tech"})
    |> Ash.create!()
  end

  defp blocks_on(date) do
    start_of_day = DateTime.new!(date, ~T[00:00:00])
    end_of_day = DateTime.new!(date, ~T[23:59:59])

    AppointmentBlock
    |> Ash.Query.filter(starts_at >= ^start_of_day and starts_at <= ^end_of_day)
    |> Ash.read!()
  end

  describe "generate_for_date/2" do
    test "creates 2 basic-wash blocks on a weekday (Wednesday)" do
      service = create_basic_wash()
      tech = create_technician()
      # Pick a Wednesday well in the future
      wednesday = next_weekday(3)

      :ok = BlockGenerator.generate_for_date(wednesday, technician_id: tech.id)

      blocks = blocks_on(wednesday) |> Enum.filter(&(&1.service_type_id == service.id))
      assert length(blocks) == 2

      starts = Enum.map(blocks, & &1.starts_at.hour) |> Enum.sort()
      assert starts == [8, 13]
    end

    test "creates 0 blocks on a Sunday" do
      _service = create_basic_wash()
      tech = create_technician()
      sunday = next_weekday(7)

      :ok = BlockGenerator.generate_for_date(sunday, technician_id: tech.id)

      assert blocks_on(sunday) == []
    end

    test "creates 0 blocks on a BlockedDate" do
      _service = create_basic_wash()
      tech = create_technician()
      tuesday = next_weekday(2)

      {:ok, _} =
        BlockedDate
        |> Ash.Changeset.for_create(:create, %{date: tuesday, reason: "Holiday"})
        |> Ash.create()

      :ok = BlockGenerator.generate_for_date(tuesday, technician_id: tech.id)

      assert blocks_on(tuesday) == []
    end

    test "is idempotent — running twice does not duplicate blocks" do
      service = create_basic_wash()
      tech = create_technician()
      monday = next_weekday(1)

      :ok = BlockGenerator.generate_for_date(monday, technician_id: tech.id)
      :ok = BlockGenerator.generate_for_date(monday, technician_id: tech.id)

      blocks = blocks_on(monday) |> Enum.filter(&(&1.service_type_id == service.id))
      assert length(blocks) == 2
    end

    test "sets closes_at to midnight the day before block start" do
      service = create_basic_wash()
      tech = create_technician()
      wednesday = next_weekday(3)

      :ok = BlockGenerator.generate_for_date(wednesday, technician_id: tech.id)

      [block | _] = blocks_on(wednesday) |> Enum.filter(&(&1.service_type_id == service.id))
      expected_close = DateTime.new!(Date.add(wednesday, -1), ~T[23:59:59])
      assert DateTime.diff(block.closes_at, expected_close, :second) |> abs() <= 1
    end
  end

  describe "generate_ahead/2" do
    test "creates blocks for the next N days" do
      service = create_basic_wash()
      tech = create_technician()

      :ok = BlockGenerator.generate_ahead(7, technician_id: tech.id)

      # Over a 7-day span there are 6 Mon–Sat days → 12 basic-wash blocks expected.
      total =
        AppointmentBlock
        |> Ash.Query.filter(service_type_id == ^service.id)
        |> Ash.read!()
        |> length()

      assert total == 12
    end
  end

  # --- helpers ---

  # Return the next date with the given day-of-week (1=Mon..7=Sun),
  # at least 2 days out to stay safely in the future.
  defp next_weekday(dow) do
    today = Date.utc_today()
    today_dow = Date.day_of_week(today)
    diff = Integer.mod(dow - today_dow, 7)
    diff = if diff < 2, do: diff + 7, else: diff
    Date.add(today, diff)
  end
end
