defmodule MobileCarWash.Scheduling.RecurringAppointmentSchedulerTest do
  use MobileCarWash.DataCase, async: false
  use Oban.Testing, repo: MobileCarWash.Repo

  alias MobileCarWash.Scheduling.{RecurringSchedule, RecurringAppointmentScheduler, Appointment}
  alias MobileCarWash.Notifications.TwilioClientMock

  require Ash.Query

  setup do
    TwilioClientMock.init()

    {:ok, customer} =
      MobileCarWash.Accounts.Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "sched-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Scheduler Test",
        phone: "+15125550000",
        sms_opt_in: true
      })
      |> Ash.create()

    {:ok, service_type} =
      MobileCarWash.Scheduling.ServiceType
      |> Ash.Changeset.for_create(:create, %{
        name: "Basic Wash",
        slug: "sched_bw_#{System.unique_integer([:positive])}",
        base_price_cents: 5_000,
        duration_minutes: 45
      })
      |> Ash.create()

    {:ok, vehicle} =
      MobileCarWash.Fleet.Vehicle
      |> Ash.Changeset.for_create(:create, %{make: "Toyota", model: "Camry"})
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create()

    {:ok, address} =
      MobileCarWash.Fleet.Address
      |> Ash.Changeset.for_create(:create, %{street: "100 Main St", city: "San Antonio", state: "TX", zip: "78259"})
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create()

    %{customer: customer, service_type: service_type, vehicle: vehicle, address: address}
  end

  defp create_schedule(ctx, attrs \\ %{}) do
    defaults = %{frequency: :weekly, preferred_day: next_weekday(), preferred_time: ~T[10:00:00]}
    attrs = Map.merge(defaults, attrs)

    {:ok, schedule} =
      RecurringSchedule
      |> Ash.Changeset.for_create(:create, attrs)
      |> Ash.Changeset.force_change_attribute(:customer_id, ctx.customer.id)
      |> Ash.Changeset.force_change_attribute(:vehicle_id, ctx.vehicle.id)
      |> Ash.Changeset.force_change_attribute(:address_id, ctx.address.id)
      |> Ash.Changeset.force_change_attribute(:service_type_id, ctx.service_type.id)
      |> Ash.create()

    schedule
  end

  # Returns the day-of-week number (1=Mon..6=Sat) for a weekday within the next 7 days
  defp next_weekday do
    today = Date.utc_today()

    1..7
    |> Enum.map(&Date.add(today, &1))
    |> Enum.find(fn d -> Date.day_of_week(d) in 1..6 end)
    |> Date.day_of_week()
  end

  test "creates appointment for active weekly schedule", ctx do
    schedule = create_schedule(ctx)

    assert :ok = perform_job(RecurringAppointmentScheduler, %{})

    appointments =
      Appointment
      |> Ash.Query.filter(recurring_schedule_id == ^schedule.id)
      |> Ash.read!()

    assert length(appointments) == 1
    appt = hd(appointments)
    assert appt.price_cents == 5_000
    assert appt.duration_minutes == 45
    assert appt.customer_id == ctx.customer.id
  end

  test "skips inactive schedules", ctx do
    schedule = create_schedule(ctx)

    schedule
    |> Ash.Changeset.for_update(:deactivate, %{})
    |> Ash.update!()

    assert :ok = perform_job(RecurringAppointmentScheduler, %{})

    appointments =
      Appointment
      |> Ash.Query.filter(recurring_schedule_id == ^schedule.id)
      |> Ash.read!()

    assert appointments == []
  end

  test "does not create duplicate appointments", ctx do
    schedule = create_schedule(ctx)

    # Run twice
    assert :ok = perform_job(RecurringAppointmentScheduler, %{})
    assert :ok = perform_job(RecurringAppointmentScheduler, %{})

    appointments =
      Appointment
      |> Ash.Query.filter(recurring_schedule_id == ^schedule.id)
      |> Ash.read!()

    assert length(appointments) == 1
  end

  test "updates last_scheduled_date after creating", ctx do
    schedule = create_schedule(ctx)

    assert :ok = perform_job(RecurringAppointmentScheduler, %{})

    updated = Ash.get!(RecurringSchedule, schedule.id)
    assert updated.last_scheduled_date != nil
  end
end
