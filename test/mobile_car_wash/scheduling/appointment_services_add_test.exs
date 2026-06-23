defmodule MobileCarWash.Scheduling.AppointmentServicesAddTest do
  use MobileCarWash.DataCase, async: false

  alias MobileCarWash.Scheduling.{AppointmentServices, AppointmentAddOn, AddOn, Appointment}

  require Ash.Query

  defp fixtures(vehicle_size) do
    {:ok, customer} =
      MobileCarWash.Accounts.Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "svc-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Svc Test",
        phone: "+15125550000"
      })
      |> Ash.create()

    {:ok, service_type} =
      MobileCarWash.Scheduling.ServiceType
      |> Ash.Changeset.for_create(:create, %{
        name: "Basic Wash",
        slug: "svc-#{System.unique_integer([:positive])}",
        base_price_cents: 5_000,
        duration_minutes: 45
      })
      |> Ash.create()

    {:ok, vehicle} =
      MobileCarWash.Fleet.Vehicle
      |> Ash.Changeset.for_create(:create, %{make: "Toyota", model: "Camry", year: 2021})
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.Changeset.force_change_attribute(:size, vehicle_size)
      |> Ash.create()

    {:ok, address} =
      MobileCarWash.Fleet.Address
      |> Ash.Changeset.for_create(:create, %{
        street: "100 Main St",
        city: "San Antonio",
        state: "TX",
        zip: "78259"
      })
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create()

    {:ok, appointment} =
      Appointment
      |> Ash.Changeset.for_create(:book, %{
        scheduled_at: DateTime.add(DateTime.utc_now(), 3 * 24 * 3600),
        price_cents: 5_000,
        duration_minutes: 45,
        customer_id: customer.id,
        vehicle_id: vehicle.id,
        address_id: address.id,
        service_type_id: service_type.id
      })
      |> Ash.create()

    {:ok, addon} =
      AddOn
      |> Ash.Changeset.for_create(:create, %{
        name: "Wax",
        slug: "wax-#{System.unique_integer([:positive])}",
        price_cents: 2_000
      })
      |> Ash.create()

    %{appointment: appointment, addon: addon}
  end

  test "attaches a size-scaled add-on row and bumps the appointment price (suv_van 1.2x)" do
    %{appointment: appt, addon: addon} = fixtures(:suv_van)

    {:ok, updated} = AppointmentServices.add(appt, [addon.id])

    # 2000 * 1.2 = 2400
    assert updated.price_cents == 5_000 + 2_400

    rows =
      AppointmentAddOn
      |> Ash.Query.filter(appointment_id == ^appt.id)
      |> Ash.read!()

    assert [%{price_cents: 2_400}] = rows
  end

  test "is a no-op when add_on_ids is empty" do
    %{appointment: appt} = fixtures(:car)
    {:ok, updated} = AppointmentServices.add(appt, [])
    assert updated.price_cents == 5_000
  end
end
