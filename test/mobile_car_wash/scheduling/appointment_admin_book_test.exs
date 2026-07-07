defmodule MobileCarWash.Scheduling.AppointmentAdminBookTest do
  use MobileCarWash.DataCase, async: true

  alias MobileCarWash.Scheduling.{Appointment, ServiceType}
  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Fleet.{Vehicle, Address}

  defp fixtures do
    cust =
      Customer
      |> Ash.Changeset.for_create(:create_guest, %{
        name: "Admin Booked",
        email: "adminbook-#{System.unique_integer([:positive])}@test.com",
        phone: "+15125550122"
      })
      |> Ash.create!(authorize?: false)

    service =
      ServiceType
      |> Ash.Changeset.for_create(:create, %{
        name: "Basic Wash",
        slug: "basic_#{System.unique_integer([:positive])}",
        base_price_cents: 5000,
        duration_minutes: 45
      })
      |> Ash.create!(authorize?: false)

    vehicle =
      Vehicle
      |> Ash.Changeset.for_create(:create, %{make: "Toyota", model: "Camry", size: :car})
      |> Ash.Changeset.force_change_attribute(:customer_id, cust.id)
      |> Ash.create!(authorize?: false)

    address =
      Address
      |> Ash.Changeset.for_create(:create, %{
        street: "123 Main St",
        city: "Austin",
        state: "TX",
        zip: "78701"
      })
      |> Ash.Changeset.force_change_attribute(:customer_id, cust.id)
      |> Ash.create!(authorize?: false)

    %{cust: cust, service: service, vehicle: vehicle, address: address}
  end

  test "admin_book creates a confirmed, standalone appointment in the past without error" do
    %{cust: cust, service: service, vehicle: vehicle, address: address} = fixtures()
    # Deliberately in the past — admin override must NOT reject it.
    past = DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.truncate(:second)

    {:ok, appt} =
      Appointment
      |> Ash.Changeset.for_create(:admin_book, %{
        scheduled_at: past,
        customer_id: cust.id,
        vehicle_id: vehicle.id,
        address_id: address.id,
        service_type_id: service.id,
        price_cents: 5000,
        duration_minutes: 45
      })
      |> Ash.create(authorize?: false)

    assert appt.status == :confirmed
    assert appt.appointment_block_id == nil
    assert appt.price_cents == 5000
    assert appt.duration_minutes == 45
  end
end
