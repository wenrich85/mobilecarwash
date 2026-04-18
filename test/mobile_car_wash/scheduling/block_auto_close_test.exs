defmodule MobileCarWash.Scheduling.BlockAutoCloseTest do
  @moduledoc """
  When a booking fills the last spot in a block, we close + optimize the
  block immediately instead of waiting for midnight. Customers get their
  confirmed times right away.
  """
  use MobileCarWash.DataCase, async: false
  use Oban.Testing, repo: MobileCarWash.Repo

  alias MobileCarWash.Scheduling.{AppointmentBlock, Booking, ServiceType}
  alias MobileCarWash.Operations.Technician

  defp create_customer(suffix) do
    MobileCarWash.Accounts.Customer
    |> Ash.Changeset.for_create(:create_guest, %{
      email: "autoclose-#{suffix}-#{:rand.uniform(100_000)}@example.com",
      name: "Autoclose #{suffix}",
      phone: "+1512555020#{:rand.uniform(9)}"
    })
    |> Ash.create!()
  end

  defp create_service do
    ServiceType
    |> Ash.Changeset.for_create(:create, %{
      name: "Basic Wash",
      slug: "basic_wash_auto_#{:rand.uniform(100_000)}",
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
      street: "#{:rand.uniform(9999)} Main St",
      city: "San Antonio",
      state: "TX",
      zip: "78261",
      latitude: 29.65,
      longitude: -98.42
    })
    |> Ash.Changeset.force_change_attribute(:customer_id, customer_id)
    |> Ash.create!()
  end

  defp create_technician do
    Technician
    |> Ash.Changeset.for_create(:create, %{name: "Auto Tech"})
    |> Ash.create!()
  end

  defp create_block(service, tech, capacity) do
    starts_at =
      DateTime.utc_now()
      |> DateTime.add(2 * 86_400, :second)
      |> DateTime.truncate(:second)

    AppointmentBlock
    |> Ash.Changeset.for_create(:create, %{
      service_type_id: service.id,
      technician_id: tech.id,
      starts_at: starts_at,
      ends_at: DateTime.add(starts_at, 3 * 3600, :second),
      closes_at: DateTime.add(starts_at, -3600, :second),
      capacity: capacity,
      status: :open
    })
    |> Ash.create!()
  end

  defp book(customer, service, block) do
    vehicle = create_vehicle(customer.id)
    address = create_address(customer.id)

    Booking.create_booking(%{
      customer_id: customer.id,
      service_type_id: service.id,
      vehicle_id: vehicle.id,
      address_id: address.id,
      appointment_block_id: block.id
    })
  end

  test "when the booking fills the block to capacity, block is auto-closed + optimized" do
    service = create_service()
    tech = create_technician()
    block = create_block(service, tech, 1)

    customer = create_customer("only")
    {:ok, %{appointment: appt}} = book(customer, service, block)

    reloaded = Ash.get!(AppointmentBlock, block.id)
    assert reloaded.status == :scheduled

    # Optimizer has assigned a concrete arrival time + route position.
    reloaded_appt = Ash.get!(MobileCarWash.Scheduling.Appointment, appt.id)
    assert reloaded_appt.route_position == 1
    assert reloaded_appt.scheduled_at != nil
  end

  test "booking that does NOT fill the block leaves it :open" do
    service = create_service()
    tech = create_technician()
    block = create_block(service, tech, 3)

    customer = create_customer("partial")
    {:ok, %{appointment: _}} = book(customer, service, block)

    reloaded = Ash.get!(AppointmentBlock, block.id)
    assert reloaded.status == :open
  end
end
