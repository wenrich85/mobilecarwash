defmodule MobileCarWash.Scheduling.RecurringSchedulePreferencesTest do
  use MobileCarWash.DataCase, async: false

  alias MobileCarWash.Scheduling.RecurringSchedule

  setup do
    {:ok, customer} =
      MobileCarWash.Accounts.Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "recur-pref-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Recur Pref",
        phone: "+15125550000"
      })
      |> Ash.create()

    {:ok, service_type} =
      MobileCarWash.Scheduling.ServiceType
      |> Ash.Changeset.for_create(:create, %{
        name: "Basic Wash",
        slug: "recur_pref_#{System.unique_integer([:positive])}",
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
        street: "100 Main St",
        city: "San Antonio",
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

    %{schedule: schedule}
  end

  test "update_preferences changes frequency, day, and time", %{schedule: schedule} do
    {:ok, updated} =
      schedule
      |> Ash.Changeset.for_update(:update_preferences, %{
        frequency: :biweekly,
        preferred_day: 5,
        preferred_time: ~T[14:30:00]
      })
      |> Ash.update()

    assert updated.frequency == :biweekly
    assert updated.preferred_day == 5
    assert updated.preferred_time == ~T[14:30:00]
  end

  test "update_preferences leaves other attributes untouched", %{schedule: schedule} do
    {:ok, updated} =
      schedule
      |> Ash.Changeset.for_update(:update_preferences, %{
        frequency: :monthly,
        preferred_day: 1,
        preferred_time: ~T[09:00:00]
      })
      |> Ash.update()

    assert updated.active == true
    assert updated.customer_id == schedule.customer_id
    assert updated.vehicle_id == schedule.vehicle_id
  end
end
