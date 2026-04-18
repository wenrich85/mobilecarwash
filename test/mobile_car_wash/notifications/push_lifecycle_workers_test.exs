defmodule MobileCarWash.Notifications.PushLifecycleWorkersTest do
  @moduledoc """
  Covers the four remaining per-event push workers. Fan-out, token
  deactivation, and transient-failure handling are exercised in
  `PushBookingConfirmationWorkerTest` (all four workers call the same
  `Push.send_to_customer/2` helper, so we don't re-test those invariants
  here) — this file asserts the per-event payload contents only.
  """
  use MobileCarWash.DataCase, async: false
  use Oban.Testing, repo: MobileCarWash.Repo

  alias MobileCarWash.Notifications.{
    ApnsClientMock,
    DeviceToken,
    PushAppointmentReminderWorker,
    PushBlockScheduledWorker,
    PushTechOnTheWayWorker,
    PushWashCompletedWorker
  }

  setup do
    ApnsClientMock.init()

    {:ok, customer} =
      MobileCarWash.Accounts.Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "lifecycle-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Lifecycle Test",
        phone: "+15125551000"
      })
      |> Ash.create()

    {:ok, service_type} =
      MobileCarWash.Scheduling.ServiceType
      |> Ash.Changeset.for_create(:create, %{
        name: "Deep Detail",
        slug: "lifecycle_dd_#{System.unique_integer([:positive])}",
        base_price_cents: 20_000,
        duration_minutes: 120
      })
      |> Ash.create()

    {:ok, vehicle} =
      MobileCarWash.Fleet.Vehicle
      |> Ash.Changeset.for_create(:create, %{make: "Honda", model: "Civic"})
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create()

    {:ok, address} =
      MobileCarWash.Fleet.Address
      |> Ash.Changeset.for_create(:create, %{
        street: "42 Lifecycle Ave",
        city: "San Antonio",
        state: "TX",
        zip: "78259"
      })
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create()

    {:ok, scheduled_at} = DateTime.new(~D[2026-05-15], ~T[09:00:00])

    {:ok, appointment} =
      MobileCarWash.Scheduling.Appointment
      |> Ash.Changeset.for_create(:book, %{
        customer_id: customer.id,
        vehicle_id: vehicle.id,
        address_id: address.id,
        service_type_id: service_type.id,
        scheduled_at: scheduled_at,
        price_cents: 20_000,
        duration_minutes: 120
      })
      |> Ash.create()

    {:ok, _device_token} =
      DeviceToken
      |> Ash.Changeset.for_create(
        :register,
        %{token: "ios-lifecycle-token", customer_id: customer.id},
        actor: customer
      )
      |> Ash.create(actor: customer)

    %{appointment: appointment, customer: customer}
  end

  describe "PushAppointmentReminderWorker" do
    test "sends a reminder payload", %{appointment: appointment} do
      :ok =
        perform_job(PushAppointmentReminderWorker, %{"appointment_id" => appointment.id})

      [{_, payload, _}] = ApnsClientMock.pushes_to("ios-lifecycle-token")
      assert payload.aps.alert.title == "Appointment tomorrow"
      assert payload.aps.alert.body =~ "Deep Detail"
      assert payload.data.kind == "appointment_reminder"
      assert payload.data.appointment_id == appointment.id
    end
  end

  describe "PushBlockScheduledWorker" do
    test "sends an arrival-window payload", %{appointment: appointment} do
      :ok =
        perform_job(PushBlockScheduledWorker, %{"appointment_id" => appointment.id})

      [{_, payload, _}] = ApnsClientMock.pushes_to("ios-lifecycle-token")
      assert payload.aps.alert.title == "Arrival time confirmed"
      assert payload.data.kind == "block_scheduled"
    end
  end

  describe "PushTechOnTheWayWorker" do
    test "sends a tech-en-route payload when a technician is assigned",
         %{appointment: appointment} do
      {:ok, technician} =
        MobileCarWash.Operations.Technician
        |> Ash.Changeset.for_create(:create, %{
          name: "Miguel",
          phone: "512-555-0002",
          active: true
        })
        |> Ash.create()

      appointment
      |> Ash.Changeset.for_update(:update, %{})
      |> Ash.Changeset.force_change_attribute(:technician_id, technician.id)
      |> Ash.update!(authorize?: false)

      :ok = perform_job(PushTechOnTheWayWorker, %{"appointment_id" => appointment.id})

      [{_, payload, _}] = ApnsClientMock.pushes_to("ios-lifecycle-token")
      assert payload.aps.alert.title == "Tech is on the way"
      assert payload.aps.alert.body =~ "Miguel"
      assert payload.data.technician_id == technician.id
      assert payload.data.deep_link =~ "/tracking"
    end

    test "no-ops when no technician is assigned", %{appointment: appointment} do
      :ok = perform_job(PushTechOnTheWayWorker, %{"appointment_id" => appointment.id})
      assert ApnsClientMock.pushes() == []
    end
  end

  describe "PushWashCompletedWorker" do
    test "sends a completion payload with badge 0", %{appointment: appointment} do
      :ok = perform_job(PushWashCompletedWorker, %{"appointment_id" => appointment.id})

      [{_, payload, _}] = ApnsClientMock.pushes_to("ios-lifecycle-token")
      assert payload.aps.alert.title == "Your wash is complete!"
      assert payload.aps.badge == 0
      assert payload.data.kind == "wash_completed"
    end
  end
end
