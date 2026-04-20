defmodule MobileCarWash.Scheduling.RecurringScheduleTest do
  use MobileCarWash.DataCase, async: true

  alias MobileCarWash.Scheduling.RecurringSchedule

  setup do
    {:ok, customer} =
      MobileCarWash.Accounts.Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "recur-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Recurring Test"
      })
      |> Ash.create()

    {:ok, service_type} =
      MobileCarWash.Scheduling.ServiceType
      |> Ash.Changeset.for_create(:create, %{
        name: "Basic Wash",
        slug: "recur_bw_#{System.unique_integer([:positive])}",
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
      |> Ash.Changeset.for_create(:create, %{
        street: "100 Main St",
        city: "San Antonio",
        state: "TX",
        zip: "78259"
      })
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create()

    %{customer: customer, service_type: service_type, vehicle: vehicle, address: address}
  end

  describe "create" do
    test "creates a valid weekly schedule", ctx do
      {:ok, schedule} =
        RecurringSchedule
        |> Ash.Changeset.for_create(:create, %{
          frequency: :weekly,
          preferred_day: 3,
          preferred_time: ~T[10:00:00]
        })
        |> Ash.Changeset.force_change_attribute(:customer_id, ctx.customer.id)
        |> Ash.Changeset.force_change_attribute(:vehicle_id, ctx.vehicle.id)
        |> Ash.Changeset.force_change_attribute(:address_id, ctx.address.id)
        |> Ash.Changeset.force_change_attribute(:service_type_id, ctx.service_type.id)
        |> Ash.create()

      assert schedule.frequency == :weekly
      assert schedule.preferred_day == 3
      assert schedule.preferred_time == ~T[10:00:00]
      assert schedule.active == true
    end

    test "validates frequency is one of weekly/biweekly/monthly", ctx do
      result =
        RecurringSchedule
        |> Ash.Changeset.for_create(:create, %{
          frequency: :daily,
          preferred_day: 1,
          preferred_time: ~T[09:00:00]
        })
        |> Ash.Changeset.force_change_attribute(:customer_id, ctx.customer.id)
        |> Ash.Changeset.force_change_attribute(:vehicle_id, ctx.vehicle.id)
        |> Ash.Changeset.force_change_attribute(:address_id, ctx.address.id)
        |> Ash.Changeset.force_change_attribute(:service_type_id, ctx.service_type.id)
        |> Ash.create()

      assert {:error, _} = result
    end

    test "creates biweekly and monthly schedules", ctx do
      for freq <- [:biweekly, :monthly] do
        {:ok, schedule} =
          RecurringSchedule
          |> Ash.Changeset.for_create(:create, %{
            frequency: freq,
            preferred_day: 2,
            preferred_time: ~T[14:00:00]
          })
          |> Ash.Changeset.force_change_attribute(:customer_id, ctx.customer.id)
          |> Ash.Changeset.force_change_attribute(:vehicle_id, ctx.vehicle.id)
          |> Ash.Changeset.force_change_attribute(:address_id, ctx.address.id)
          |> Ash.Changeset.force_change_attribute(:service_type_id, ctx.service_type.id)
          |> Ash.create()

        assert schedule.frequency == freq
      end
    end
  end

  describe "deactivate/activate" do
    test "can deactivate and reactivate a schedule", ctx do
      {:ok, schedule} =
        RecurringSchedule
        |> Ash.Changeset.for_create(:create, %{
          frequency: :weekly,
          preferred_day: 4,
          preferred_time: ~T[10:00:00]
        })
        |> Ash.Changeset.force_change_attribute(:customer_id, ctx.customer.id)
        |> Ash.Changeset.force_change_attribute(:vehicle_id, ctx.vehicle.id)
        |> Ash.Changeset.force_change_attribute(:address_id, ctx.address.id)
        |> Ash.Changeset.force_change_attribute(:service_type_id, ctx.service_type.id)
        |> Ash.create()

      assert schedule.active == true

      {:ok, deactivated} =
        schedule
        |> Ash.Changeset.for_update(:deactivate, %{})
        |> Ash.update()

      assert deactivated.active == false

      {:ok, reactivated} =
        deactivated
        |> Ash.Changeset.for_update(:activate, %{})
        |> Ash.update()

      assert reactivated.active == true
    end
  end

  describe "for_customer read" do
    test "returns only schedules for the given customer", ctx do
      {:ok, _schedule} =
        RecurringSchedule
        |> Ash.Changeset.for_create(:create, %{
          frequency: :weekly,
          preferred_day: 5,
          preferred_time: ~T[08:00:00]
        })
        |> Ash.Changeset.force_change_attribute(:customer_id, ctx.customer.id)
        |> Ash.Changeset.force_change_attribute(:vehicle_id, ctx.vehicle.id)
        |> Ash.Changeset.force_change_attribute(:address_id, ctx.address.id)
        |> Ash.Changeset.force_change_attribute(:service_type_id, ctx.service_type.id)
        |> Ash.create()

      schedules =
        RecurringSchedule
        |> Ash.Query.for_read(:for_customer, %{customer_id: ctx.customer.id})
        |> Ash.read!()

      assert length(schedules) == 1

      # Different customer should return empty
      empty =
        RecurringSchedule
        |> Ash.Query.for_read(:for_customer, %{customer_id: Ash.UUID.generate()})
        |> Ash.read!()

      assert empty == []
    end
  end
end
