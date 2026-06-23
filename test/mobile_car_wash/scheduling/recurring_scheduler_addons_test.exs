defmodule MobileCarWash.Scheduling.RecurringSchedulerAddonsTest do
  use MobileCarWash.DataCase, async: false

  import Swoosh.TestAssertions

  alias MobileCarWash.Scheduling.{
    AppointmentServices,
    AppointmentAddOn,
    AddOn,
    Appointment,
    RecurringAppointmentScheduler
  }

  require Ash.Query

  defp build(cus) do
    {:ok, customer} =
      MobileCarWash.Accounts.Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "rsch-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "RSch",
        phone: "+15125550000"
      })
      |> Ash.Changeset.force_change_attribute(:stripe_customer_id, cus)
      |> Ash.create()

    {:ok, service_type} =
      MobileCarWash.Scheduling.ServiceType
      |> Ash.Changeset.for_create(:create, %{
        name: "Basic",
        slug: "rsch-#{System.unique_integer([:positive])}",
        base_price_cents: 5_000,
        duration_minutes: 45
      })
      |> Ash.create()

    {:ok, vehicle} =
      MobileCarWash.Fleet.Vehicle
      |> Ash.Changeset.for_create(:create, %{make: "Toyota", model: "Camry", year: 2021})
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.Changeset.force_change_attribute(:size, :car)
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
      MobileCarWash.Scheduling.RecurringSchedule
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

    {:ok, addon} =
      AddOn
      |> Ash.Changeset.for_create(:create, %{
        name: "Wax",
        slug: "wax-#{System.unique_integer([:positive])}",
        price_cents: 2_000
      })
      |> Ash.create()

    {:ok, _technician} =
      MobileCarWash.Operations.Technician
      |> Ash.Changeset.for_create(:create, %{name: "RSch Tech"})
      |> Ash.create()

    :ok = AppointmentServices.replace_schedule_add_ons(schedule.id, [addon.id])
    %{schedule: schedule}
  end

  test "charge success: occurrence gets the schedule's add-ons attached and price bumped" do
    %{schedule: schedule} = build("cus_test_sch")
    date = next_non_sunday(Date.add(Date.utc_today(), 1))

    assert {:ok, appt} = RecurringAppointmentScheduler.create_appointment(schedule, date)

    assert [%{price_cents: 2_000}] =
             AppointmentAddOn |> Ash.Query.filter(appointment_id == ^appt.id) |> Ash.read!()

    assert Ash.get!(Appointment, appt.id).price_cents == 5_000 + 2_000
  end

  test "charge decline: base wash kept, no add-ons, decline email enqueued" do
    %{schedule: schedule} = build("cus_decline_sch")
    date = next_non_sunday(Date.add(Date.utc_today(), 1))

    flush_emails()

    assert {:ok, appt} = RecurringAppointmentScheduler.create_appointment(schedule, date)

    assert [] = AppointmentAddOn |> Ash.Query.filter(appointment_id == ^appt.id) |> Ash.read!()
    assert Ash.get!(Appointment, appt.id).price_cents == 5_000
    assert_email_sent(subject: "Action needed: card declined for add-ons")
  end

  defp next_non_sunday(date) do
    if Date.day_of_week(date) == 7, do: Date.add(date, 1), else: date
  end

  defp flush_emails do
    receive do
      {:email, _} -> flush_emails()
    after
      0 -> :ok
    end
  end
end
