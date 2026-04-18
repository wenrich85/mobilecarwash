defmodule MobileCarWash.Scheduling.BlockTemplateTest do
  @moduledoc """
  BlockTemplate drives block generation. Each template row says: "for this
  service, on this day of week, create a block starting at this hour."
  The admin can add/remove rows to change the weekly schedule without
  touching code.
  """
  use MobileCarWash.DataCase, async: false

  alias MobileCarWash.Scheduling.{BlockGenerator, BlockTemplate, AppointmentBlock, ServiceType}
  alias MobileCarWash.Operations.Technician

  require Ash.Query

  defp create_service do
    ServiceType
    |> Ash.Changeset.for_create(:create, %{
      name: "Basic",
      slug: "basic_tmpl_#{:rand.uniform(100_000)}",
      base_price_cents: 5000,
      duration_minutes: 45
    })
    |> Ash.create!()
  end

  defp create_technician do
    Technician
    |> Ash.Changeset.for_create(:create, %{name: "Template Tech"})
    |> Ash.create!()
  end

  defp create_template(service, attrs) do
    defaults = %{
      service_type_id: service.id,
      day_of_week: 3,
      start_hour: 8,
      active: true
    }

    BlockTemplate
    |> Ash.Changeset.for_create(:create, Map.merge(defaults, attrs))
    |> Ash.create!()
  end

  defp next_weekday(dow) do
    today = Date.utc_today()
    today_dow = Date.day_of_week(today)
    diff = Integer.mod(dow - today_dow, 7)
    diff = if diff < 2, do: diff + 7, else: diff
    Date.add(today, diff)
  end

  defp blocks_on(date) do
    start_of_day = DateTime.new!(date, ~T[00:00:00])
    end_of_day = DateTime.new!(date, ~T[23:59:59])

    AppointmentBlock
    |> Ash.Query.filter(starts_at >= ^start_of_day and starts_at <= ^end_of_day)
    |> Ash.read!()
  end

  describe "BlockTemplate resource" do
    test "can be created with service_type, day_of_week, and start_hour" do
      service = create_service()

      {:ok, tmpl} =
        BlockTemplate
        |> Ash.Changeset.for_create(:create, %{
          service_type_id: service.id,
          day_of_week: 1,
          start_hour: 9,
          active: true
        })
        |> Ash.create()

      assert tmpl.day_of_week == 1
      assert tmpl.start_hour == 9
      assert tmpl.active == true
    end
  end

  describe "BlockGenerator using templates" do
    test "creates blocks matching active templates for the day" do
      service = create_service()
      tech = create_technician()
      # Tuesday at 9am and Tuesday at 14:00
      create_template(service, %{day_of_week: 2, start_hour: 9})
      create_template(service, %{day_of_week: 2, start_hour: 14})

      tuesday = next_weekday(2)
      :ok = BlockGenerator.generate_for_date(tuesday, technician_id: tech.id)

      starts =
        blocks_on(tuesday)
        |> Enum.filter(&(&1.service_type_id == service.id))
        |> Enum.map(& &1.starts_at.hour)
        |> Enum.sort()

      assert starts == [9, 14]
    end

    test "skips inactive templates" do
      service = create_service()
      tech = create_technician()
      create_template(service, %{day_of_week: 2, start_hour: 9, active: true})
      create_template(service, %{day_of_week: 2, start_hour: 14, active: false})

      tuesday = next_weekday(2)
      :ok = BlockGenerator.generate_for_date(tuesday, technician_id: tech.id)

      starts =
        blocks_on(tuesday)
        |> Enum.filter(&(&1.service_type_id == service.id))
        |> Enum.map(& &1.starts_at.hour)

      assert starts == [9]
    end

    test "does not create blocks for a day with no matching templates" do
      service = create_service()
      tech = create_technician()
      # Only Wednesday templates
      create_template(service, %{day_of_week: 3, start_hour: 10})

      monday = next_weekday(1)
      :ok = BlockGenerator.generate_for_date(monday, technician_id: tech.id)

      assert blocks_on(monday) |> Enum.filter(&(&1.service_type_id == service.id)) == []
    end
  end
end
