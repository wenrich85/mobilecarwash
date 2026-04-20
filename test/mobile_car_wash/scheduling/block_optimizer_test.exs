defmodule MobileCarWash.Scheduling.BlockOptimizerTest do
  @moduledoc """
  The BlockOptimizer takes an AppointmentBlock (with appointments + addresses
  loaded) and does three things:
    1. orders the appointments by nearest-neighbor from the shop origin,
    2. assigns each appointment a real `scheduled_at` (ETA) and `route_position`,
    3. closes the block (status → :scheduled) and enqueues SMS confirmations.
  """
  use MobileCarWash.DataCase, async: false
  use Oban.Testing, repo: MobileCarWash.Repo

  alias MobileCarWash.Scheduling.{AppointmentBlock, BlockOptimizer, Booking, ServiceType}
  alias MobileCarWash.Operations.Technician
  alias MobileCarWash.Notifications.TwilioClientMock

  require Ash.Query

  defp create_customer(suffix) do
    {:ok, customer} =
      MobileCarWash.Accounts.Customer
      |> Ash.Changeset.for_create(:create_guest, %{
        email: "optimizer-#{suffix}-#{:rand.uniform(100_000)}@example.com",
        name: "Optimizer #{suffix}",
        phone: "+1512555010#{:rand.uniform(9)}"
      })
      |> Ash.create()

    {:ok, opted_in} =
      customer
      |> Ash.Changeset.for_update(:update, %{sms_opt_in: true})
      |> Ash.update(authorize?: false)

    opted_in
  end

  defp create_service do
    ServiceType
    |> Ash.Changeset.for_create(:create, %{
      name: "Basic Wash",
      slug: "basic_wash_opt_#{:rand.uniform(100_000)}",
      base_price_cents: 5000,
      duration_minutes: 45
    })
    |> Ash.create!()
  end

  defp create_vehicle(customer_id) do
    MobileCarWash.Fleet.Vehicle
    |> Ash.Changeset.for_create(:create, %{make: "Test", model: "Car", size: :car})
    |> Ash.Changeset.force_change_attribute(:customer_id, customer_id)
    |> Ash.create!()
  end

  # Create an address with explicit lat/lng so distance math is deterministic.
  defp create_address(customer_id, lat, lng, zip \\ "78261") do
    MobileCarWash.Fleet.Address
    |> Ash.Changeset.for_create(:create, %{
      street: "#{trunc(:rand.uniform() * 10_000)} Test St",
      city: "San Antonio",
      state: "TX",
      zip: zip,
      latitude: lat,
      longitude: lng
    })
    |> Ash.Changeset.force_change_attribute(:customer_id, customer_id)
    |> Ash.create!()
  end

  defp create_technician do
    Technician
    |> Ash.Changeset.for_create(:create, %{name: "Optimizer Tech"})
    |> Ash.create!()
  end

  defp create_block(service, tech) do
    starts_at =
      DateTime.utc_now()
      |> DateTime.add(2 * 86_400, :second)
      |> DateTime.truncate(:second)
      |> then(fn dt -> %{dt | minute: 0, second: 0, microsecond: {0, 0}, hour: 8} end)

    ends_at = DateTime.add(starts_at, 3 * 3600, :second)
    closes_at = DateTime.add(starts_at, -3600, :second)

    # Capacity > number of bookings we'll place, to keep auto-close
    # from firing prematurely and letting tests drive close_and_optimize directly.
    AppointmentBlock
    |> Ash.Changeset.for_create(:create, %{
      service_type_id: service.id,
      technician_id: tech.id,
      starts_at: starts_at,
      ends_at: ends_at,
      closes_at: closes_at,
      capacity: 5,
      status: :open
    })
    |> Ash.create!()
  end

  defp book_customer(customer, service, block, lat, lng) do
    vehicle = create_vehicle(customer.id)
    address = create_address(customer.id, lat, lng)

    {:ok, %{appointment: appt}} =
      Booking.create_booking(%{
        customer_id: customer.id,
        service_type_id: service.id,
        vehicle_id: vehicle.id,
        address_id: address.id,
        appointment_block_id: block.id
      })

    appt
  end

  describe "close_and_optimize/1" do
    setup do
      # These tests exercise nearest-neighbor ordering across appointments
      # spread ~22 miles apart, which violates the default intra-block
      # proximity cap. Loosen it so the optimizer tests run independently
      # of that gate (proximity is covered in booking_block_proximity_test).
      {:ok, _} =
        MobileCarWash.Scheduling.SchedulingSettings.update(%{max_intra_block_drive_minutes: 300})

      service = create_service()
      tech = create_technician()
      block = create_block(service, tech)

      # Three customers at distinct distances from shop origin (29.65, -98.42).
      #   close ~ 1mi, mid ~ 4mi, far ~ 22mi.
      c_far = create_customer("far")
      c_mid = create_customer("mid")
      c_close = create_customer("close")

      a_far = book_customer(c_far, service, block, 29.50, -98.70)
      a_mid = book_customer(c_mid, service, block, 29.60, -98.45)
      a_close = book_customer(c_close, service, block, 29.64, -98.41)

      %{block: block, service: service, far: a_far, mid: a_mid, close: a_close}
    end

    test "closes the block (status :scheduled)", %{block: block} do
      assert {:ok, _} = BlockOptimizer.close_and_optimize(block.id)

      reloaded = Ash.get!(AppointmentBlock, block.id)
      assert reloaded.status == :scheduled
    end

    test "assigns route_position 1..N in nearest-neighbor order from shop origin", %{
      block: block,
      close: close,
      mid: mid,
      far: far
    } do
      assert {:ok, _} = BlockOptimizer.close_and_optimize(block.id)

      [close, mid, far] =
        [close, mid, far]
        |> Enum.map(&Ash.get!(MobileCarWash.Scheduling.Appointment, &1.id))

      # Shop is in 78261; closest first, then mid, then far.
      assert close.route_position == 1
      assert mid.route_position == 2
      assert far.route_position == 3
    end

    test "assigns scheduled_at chronologically — first stop after shop-to-first travel", %{
      block: block,
      close: close
    } do
      assert {:ok, _} = BlockOptimizer.close_and_optimize(block.id)

      reloaded = Ash.get!(MobileCarWash.Scheduling.Appointment, close.id)
      # Should be AFTER block.starts_at (we had to drive out) but within ~30 min.
      assert DateTime.compare(reloaded.scheduled_at, block.starts_at) == :gt
      delta = DateTime.diff(reloaded.scheduled_at, block.starts_at, :second)
      assert delta > 0 and delta < 30 * 60
    end

    test "scheduled_at values are in strictly increasing order", %{
      block: block,
      close: close,
      mid: mid,
      far: far
    } do
      assert {:ok, _} = BlockOptimizer.close_and_optimize(block.id)

      times =
        [close, mid, far]
        |> Enum.map(&Ash.get!(MobileCarWash.Scheduling.Appointment, &1.id).scheduled_at)

      [t1, t2, t3] = times
      assert DateTime.compare(t1, t2) == :lt
      assert DateTime.compare(t2, t3) == :lt
    end

    test "sends a confirmation SMS to every opted-in customer", %{block: block} do
      TwilioClientMock.init()

      assert {:ok, _} = BlockOptimizer.close_and_optimize(block.id)

      messages = TwilioClientMock.messages()
      assert length(messages) == 3

      Enum.each(messages, fn {_phone, body} ->
        assert body =~ "confirmed"
      end)
    end

    test "is idempotent — re-running on a :scheduled block does nothing (returns :already_optimized)" do
      service = create_service()
      tech = create_technician()
      block = create_block(service, tech)

      {:ok, _} = BlockOptimizer.close_and_optimize(block.id)

      assert {:error, :already_optimized} = BlockOptimizer.close_and_optimize(block.id)
    end
  end

  describe "close_and_optimize/1 with no appointments" do
    test "closes the block even if empty" do
      service = create_service()
      tech = create_technician()
      block = create_block(service, tech)

      assert {:ok, _} = BlockOptimizer.close_and_optimize(block.id)

      reloaded = Ash.get!(AppointmentBlock, block.id)
      assert reloaded.status == :scheduled
    end
  end
end
