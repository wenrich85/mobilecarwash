defmodule MobileCarWash.Scheduling.BookingBlockTest do
  @moduledoc """
  Block-based booking: the customer picks an appointment block (time window)
  and the system creates an appointment attached to it with a tentative
  `scheduled_at` = block.starts_at. Route optimization later assigns the
  real arrival time.
  """
  use MobileCarWash.DataCase, async: false

  alias MobileCarWash.Scheduling.{AppointmentBlock, Booking, ServiceType}
  alias MobileCarWash.Operations.Technician

  require Ash.Query

  defp create_customer do
    MobileCarWash.Accounts.Customer
    |> Ash.Changeset.for_create(:create_guest, %{
      email: "block-booking-#{:rand.uniform(100_000)}@example.com",
      name: "Block Booker",
      phone: "512-555-0000"
    })
    |> Ash.create!()
  end

  defp create_service do
    ServiceType
    |> Ash.Changeset.for_create(:create, %{
      name: "Basic Wash",
      slug: "basic_wash_bb_#{:rand.uniform(100_000)}",
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

  defp create_address(customer_id) do
    MobileCarWash.Fleet.Address
    |> Ash.Changeset.for_create(:create, %{
      street: "123 Test St",
      city: "San Antonio",
      state: "TX",
      zip: "78261"
    })
    |> Ash.Changeset.force_change_attribute(:customer_id, customer_id)
    |> Ash.create!()
  end

  defp create_technician do
    Technician
    |> Ash.Changeset.for_create(:create, %{name: "Block Tech"})
    |> Ash.create!()
  end

  defp create_block(service, tech, opts \\ []) do
    starts_at =
      Keyword.get_lazy(opts, :starts_at, fn ->
        DateTime.utc_now()
        |> DateTime.add(2 * 86_400, :second)
        |> DateTime.truncate(:second)
      end)

    ends_at = DateTime.add(starts_at, 3 * 3600, :second)
    closes_at = Keyword.get(opts, :closes_at, DateTime.add(starts_at, -3600, :second))
    capacity = Keyword.get(opts, :capacity, 3)
    status = Keyword.get(opts, :status, :open)

    AppointmentBlock
    |> Ash.Changeset.for_create(:create, %{
      service_type_id: service.id,
      technician_id: tech.id,
      starts_at: starts_at,
      ends_at: ends_at,
      closes_at: closes_at,
      capacity: capacity,
      status: status
    })
    |> Ash.create!()
  end

  defp booking_params(customer, service, vehicle, address, block) do
    %{
      customer_id: customer.id,
      service_type_id: service.id,
      vehicle_id: vehicle.id,
      address_id: address.id,
      appointment_block_id: block.id
    }
  end

  describe "create_booking/1 with appointment_block_id" do
    test "creates an appointment linked to the block, scheduled_at = block.starts_at" do
      customer = create_customer()
      service = create_service()
      vehicle = create_vehicle(customer.id)
      address = create_address(customer.id)
      tech = create_technician()
      block = create_block(service, tech)

      assert {:ok, %{appointment: appt}} =
               Booking.create_booking(booking_params(customer, service, vehicle, address, block))

      assert appt.appointment_block_id == block.id
      assert DateTime.compare(appt.scheduled_at, block.starts_at) == :eq
      assert appt.duration_minutes == service.duration_minutes
    end

    test "increments the block's appointment_count" do
      customer = create_customer()
      service = create_service()
      vehicle = create_vehicle(customer.id)
      address = create_address(customer.id)
      tech = create_technician()
      block = create_block(service, tech)

      {:ok, _} = Booking.create_booking(booking_params(customer, service, vehicle, address, block))

      reloaded = Ash.load!(block, :appointment_count)
      assert reloaded.appointment_count == 1
    end

    test "after a block fills to capacity, subsequent bookings are rejected (auto-closed)" do
      service = create_service()
      tech = create_technician()
      block = create_block(service, tech, capacity: 1)

      # First booking fills the block — auto-close fires, block moves to :scheduled.
      c1 = create_customer()
      v1 = create_vehicle(c1.id)
      a1 = create_address(c1.id)
      {:ok, _} = Booking.create_booking(booking_params(c1, service, v1, a1, block))

      # Second booking sees the closed block.
      c2 = create_customer()
      v2 = create_vehicle(c2.id)
      a2 = create_address(c2.id)

      assert {:error, :block_not_open} =
               Booking.create_booking(booking_params(c2, service, v2, a2, block))
    end

    test "returns :block_closed when the block's closes_at has passed" do
      customer = create_customer()
      service = create_service()
      vehicle = create_vehicle(customer.id)
      address = create_address(customer.id)
      tech = create_technician()

      past_close =
        DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.truncate(:second)

      block = create_block(service, tech, closes_at: past_close)

      assert {:error, :block_closed} =
               Booking.create_booking(booking_params(customer, service, vehicle, address, block))
    end

    test "returns :block_service_mismatch when block's service differs from requested" do
      customer = create_customer()
      service = create_service()
      other_service = create_service()
      vehicle = create_vehicle(customer.id)
      address = create_address(customer.id)
      tech = create_technician()
      block = create_block(other_service, tech)

      params = booking_params(customer, service, vehicle, address, block)

      assert {:error, :block_service_mismatch} = Booking.create_booking(params)
    end

    test "returns :block_not_open when block status is :scheduled (optimizer has already run)" do
      customer = create_customer()
      service = create_service()
      vehicle = create_vehicle(customer.id)
      address = create_address(customer.id)
      tech = create_technician()
      block = create_block(service, tech, status: :scheduled)

      assert {:error, :block_not_open} =
               Booking.create_booking(booking_params(customer, service, vehicle, address, block))
    end
  end
end
