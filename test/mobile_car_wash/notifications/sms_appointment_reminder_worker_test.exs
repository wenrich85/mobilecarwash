defmodule MobileCarWash.Notifications.SMSAppointmentReminderWorkerTest do
  use MobileCarWash.DataCase, async: false
  use Oban.Testing, repo: MobileCarWash.Repo

  alias MobileCarWash.Notifications.SMSAppointmentReminderWorker
  alias MobileCarWash.Notifications.TwilioClientMock

  setup do
    TwilioClientMock.init()

    {:ok, customer} =
      MobileCarWash.Accounts.Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "sms-remind-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Reminder Test",
        phone: "+15125559999",
        sms_opt_in: true
      })
      |> Ash.create()

    {:ok, service_type} =
      MobileCarWash.Scheduling.ServiceType
      |> Ash.Changeset.for_create(:create, %{
        name: "Deep Clean",
        slug: "sms_dc_#{System.unique_integer([:positive])}",
        base_price_cents: 20_000,
        duration_minutes: 120
      })
      |> Ash.create()

    {:ok, vehicle} =
      MobileCarWash.Fleet.Vehicle
      |> Ash.Changeset.for_create(:create, %{make: "Honda", model: "CR-V"})
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create()

    {:ok, address} =
      MobileCarWash.Fleet.Address
      |> Ash.Changeset.for_create(:create, %{
        street: "456 Oak Dr",
        city: "Converse",
        state: "TX",
        zip: "78109"
      })
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create()

    {:ok, scheduled_at} = DateTime.new(~D[2026-05-16], ~T[14:00:00])

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

    %{appointment: appointment, customer: customer}
  end

  test "sends reminder SMS when customer opted in", %{appointment: appointment} do
    assert :ok = perform_job(SMSAppointmentReminderWorker, %{"appointment_id" => appointment.id})
    msgs = TwilioClientMock.messages_to("+15125559999")
    assert length(msgs) == 1
    {_to, body} = hd(msgs)
    assert body =~ "tomorrow"
    assert body =~ "Deep Clean"
  end

  test "skips when sms_opt_in is false", %{appointment: appointment, customer: customer} do
    customer
    |> Ash.Changeset.for_update(:update, %{sms_opt_in: false})
    |> Ash.update!(authorize?: false)

    assert :ok = perform_job(SMSAppointmentReminderWorker, %{"appointment_id" => appointment.id})
    assert TwilioClientMock.messages_to("+15125559999") == []
  end
end
