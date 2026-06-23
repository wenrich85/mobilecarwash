defmodule MobileCarWash.Scheduling.RecurringScheduleAddOnTest do
  use MobileCarWash.DataCase, async: false

  alias MobileCarWash.Scheduling.{AppointmentServices, AddOn, RecurringSchedule}

  defp schedule_fixture do
    {:ok, customer} =
      MobileCarWash.Accounts.Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "rsa-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "RSA",
        phone: "+15125550000"
      })
      |> Ash.create()

    {:ok, service_type} =
      MobileCarWash.Scheduling.ServiceType
      |> Ash.Changeset.for_create(:create, %{
        name: "Basic",
        slug: "rsa-#{System.unique_integer([:positive])}",
        base_price_cents: 5_000,
        duration_minutes: 45
      })
      |> Ash.create()

    {:ok, vehicle} =
      MobileCarWash.Fleet.Vehicle
      |> Ash.Changeset.for_create(:create, %{make: "Toyota", model: "Camry", year: 2021})
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create()

    {:ok, address} =
      MobileCarWash.Fleet.Address
      |> Ash.Changeset.for_create(:create, %{
        street: "1 Main",
        city: "SA",
        state: "TX",
        zip: "78259"
      })
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create()

    {:ok, schedule} =
      RecurringSchedule
      |> Ash.Changeset.for_create(:create, %{
        frequency: :weekly,
        preferred_day: 3,
        preferred_time: ~T[10:00:00]
      })
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.Changeset.force_change_attribute(:vehicle_id, vehicle.id)
      |> Ash.Changeset.force_change_attribute(:address_id, address.id)
      |> Ash.Changeset.force_change_attribute(:service_type_id, service_type.id)
      |> Ash.create()

    schedule
  end

  defp addon do
    {:ok, a} =
      AddOn
      |> Ash.Changeset.for_create(:create, %{
        name: "Wax",
        slug: "wax-#{System.unique_integer([:positive])}",
        price_cents: 2_000
      })
      |> Ash.create()

    a
  end

  test "replace_schedule_add_ons sets, then replaces, the schedule's add-on set" do
    schedule = schedule_fixture()
    a1 = addon()
    a2 = addon()

    :ok = AppointmentServices.replace_schedule_add_ons(schedule.id, [a1.id, a2.id])

    assert Enum.sort(AppointmentServices.schedule_add_on_ids(schedule.id)) ==
             Enum.sort([a1.id, a2.id])

    :ok = AppointmentServices.replace_schedule_add_ons(schedule.id, [a1.id])
    assert AppointmentServices.schedule_add_on_ids(schedule.id) == [a1.id]

    :ok = AppointmentServices.replace_schedule_add_ons(schedule.id, [])
    assert AppointmentServices.schedule_add_on_ids(schedule.id) == []
  end
end
