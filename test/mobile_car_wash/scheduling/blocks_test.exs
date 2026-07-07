defmodule MobileCarWash.Scheduling.BlocksTest do
  use MobileCarWash.DataCase, async: true

  alias MobileCarWash.Scheduling.{Blocks, AppointmentBlock, Appointment, ServiceType}
  alias MobileCarWash.Operations.Technician
  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Fleet.{Vehicle, Address}

  defp service do
    ServiceType
    |> Ash.Changeset.for_create(:create, %{
      name: "Basic Wash",
      slug: "basic_#{System.unique_integer([:positive])}",
      base_price_cents: 5000,
      duration_minutes: 45
    })
    |> Ash.create!(authorize?: false)
  end

  defp tech do
    Technician
    |> Ash.Changeset.for_create(:create, %{name: "Tech #{System.unique_integer([:positive])}"})
    |> Ash.create!(authorize?: false)
  end

  defp block(service, tech) do
    starts_at =
      DateTime.utc_now() |> DateTime.add(2 * 86_400, :second) |> DateTime.truncate(:second)

    AppointmentBlock
    |> Ash.Changeset.for_create(:create, %{
      service_type_id: service.id,
      technician_id: tech.id,
      starts_at: starts_at,
      ends_at: DateTime.add(starts_at, 3 * 3600, :second),
      closes_at: DateTime.add(starts_at, -3600, :second),
      capacity: 3,
      status: :open
    })
    |> Ash.create!(authorize?: false)
  end

  test "delete_block removes an empty block" do
    b = block(service(), tech())
    assert :ok = Blocks.delete_block(b.id)
    assert {:error, _} = Ash.get(AppointmentBlock, b.id)
  end

  test "delete_block refuses a block that has appointments" do
    svc = service()
    t = tech()
    b = block(svc, t)

    cust =
      Customer
      |> Ash.Changeset.for_create(:create_guest, %{
        name: "In Block",
        email: "inblock-#{System.unique_integer([:positive])}@test.com",
        phone: "+15125550133"
      })
      |> Ash.create!(authorize?: false)

    vehicle =
      Vehicle
      |> Ash.Changeset.for_create(:create, %{make: "Honda", model: "Civic", size: :car})
      |> Ash.Changeset.force_change_attribute(:customer_id, cust.id)
      |> Ash.create!(authorize?: false)

    address =
      Address
      |> Ash.Changeset.for_create(:create, %{
        street: "1 A St",
        city: "Austin",
        state: "TX",
        zip: "78701"
      })
      |> Ash.Changeset.force_change_attribute(:customer_id, cust.id)
      |> Ash.create!(authorize?: false)

    Appointment
    |> Ash.Changeset.for_create(:admin_book, %{
      scheduled_at: b.starts_at,
      customer_id: cust.id,
      vehicle_id: vehicle.id,
      address_id: address.id,
      service_type_id: svc.id,
      price_cents: 5000,
      duration_minutes: 45
    })
    |> Ash.Changeset.force_change_attribute(:appointment_block_id, b.id)
    |> Ash.create!(authorize?: false)

    assert {:error, :block_has_appointments} = Blocks.delete_block(b.id)
    assert {:ok, _} = Ash.get(AppointmentBlock, b.id)
  end

  test "delete_block returns not_found for a missing id" do
    assert {:error, :block_not_found} = Blocks.delete_block(Ash.UUID.generate())
  end
end
