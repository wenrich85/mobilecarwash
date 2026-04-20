defmodule MobileCarWash.Scheduling.AppointmentBlockTest do
  @moduledoc """
  An AppointmentBlock is a typed time window that holds up to `capacity`
  appointments of one service type. The route optimizer runs at block close
  and assigns each appointment its exact arrival time.
  """
  use MobileCarWash.DataCase, async: false

  alias MobileCarWash.Scheduling.AppointmentBlock
  alias MobileCarWash.Scheduling.ServiceType
  alias MobileCarWash.Operations.Technician

  require Ash.Query

  defp create_service(attrs \\ %{}) do
    ServiceType
    |> Ash.Changeset.for_create(
      :create,
      Map.merge(
        %{
          name: "Basic Wash",
          slug: "basic_wash_#{:rand.uniform(100_000)}",
          base_price_cents: 5000,
          duration_minutes: 45
        },
        attrs
      )
    )
    |> Ash.create!()
  end

  defp create_technician do
    Technician
    |> Ash.Changeset.for_create(:create, %{name: "Test Tech"})
    |> Ash.create!()
  end

  defp future_dt(days_ahead, hour) do
    date = Date.add(Date.utc_today(), days_ahead)
    {:ok, dt} = DateTime.new(date, Time.new!(hour, 0, 0))
    dt
  end

  describe "creating a block" do
    test "requires service_type, starts_at, ends_at, capacity, technician_id" do
      service = create_service()
      tech = create_technician()

      {:ok, block} =
        AppointmentBlock
        |> Ash.Changeset.for_create(:create, %{
          service_type_id: service.id,
          technician_id: tech.id,
          starts_at: future_dt(1, 8),
          ends_at: future_dt(1, 11),
          capacity: 3,
          closes_at: future_dt(0, 23)
        })
        |> Ash.create()

      assert block.status == :open
      assert block.capacity == 3
      assert block.service_type_id == service.id
      assert block.technician_id == tech.id
    end

    test "defaults status to :open" do
      service = create_service()
      tech = create_technician()

      {:ok, block} =
        AppointmentBlock
        |> Ash.Changeset.for_create(:create, %{
          service_type_id: service.id,
          technician_id: tech.id,
          starts_at: future_dt(1, 8),
          ends_at: future_dt(1, 11),
          capacity: 3,
          closes_at: future_dt(0, 23)
        })
        |> Ash.create()

      assert block.status == :open
    end
  end

  describe "open?/1" do
    test "is true when status=open, not at capacity, and closes_at in future" do
      service = create_service()
      tech = create_technician()

      {:ok, block} =
        AppointmentBlock
        |> Ash.Changeset.for_create(:create, %{
          service_type_id: service.id,
          technician_id: tech.id,
          starts_at: future_dt(2, 8),
          ends_at: future_dt(2, 11),
          capacity: 3,
          closes_at: future_dt(1, 23)
        })
        |> Ash.create()

      assert AppointmentBlock.open?(block) == true
    end

    test "is false when status is not :open" do
      service = create_service()
      tech = create_technician()

      {:ok, block} =
        AppointmentBlock
        |> Ash.Changeset.for_create(:create, %{
          service_type_id: service.id,
          technician_id: tech.id,
          starts_at: future_dt(2, 8),
          ends_at: future_dt(2, 11),
          capacity: 3,
          closes_at: future_dt(1, 23)
        })
        |> Ash.create()

      {:ok, closed} =
        block
        |> Ash.Changeset.for_update(:update, %{status: :scheduled})
        |> Ash.update()

      assert AppointmentBlock.open?(closed) == false
    end

    test "is false when closes_at is in the past" do
      service = create_service()
      tech = create_technician()

      # Create a block that was supposed to close yesterday.
      past_close =
        DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.truncate(:second)

      {:ok, block} =
        AppointmentBlock
        |> Ash.Changeset.for_create(:create, %{
          service_type_id: service.id,
          technician_id: tech.id,
          starts_at: future_dt(2, 8),
          ends_at: future_dt(2, 11),
          capacity: 3,
          closes_at: past_close
        })
        |> Ash.create()

      assert AppointmentBlock.open?(block) == false
    end
  end
end
