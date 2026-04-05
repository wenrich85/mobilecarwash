defmodule MobileCarWash.Notifications.SMSTechOnTheWayWorkerTest do
  use MobileCarWash.DataCase, async: false
  use Oban.Testing, repo: MobileCarWash.Repo

  alias MobileCarWash.Notifications.SMSTechOnTheWayWorker
  alias MobileCarWash.Notifications.TwilioClientMock

  setup do
    TwilioClientMock.init()

    {:ok, customer} =
      MobileCarWash.Accounts.Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "sms-otw-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "OTW Test",
        phone: "+15125554444",
        sms_opt_in: true
      })
      |> Ash.create()

    {:ok, technician} =
      MobileCarWash.Operations.Technician
      |> Ash.Changeset.for_create(:create, %{name: "Marcus Rivera", phone: "512-555-0101", active: true})
      |> Ash.create()

    {:ok, service_type} =
      MobileCarWash.Scheduling.ServiceType
      |> Ash.Changeset.for_create(:create, %{
        name: "Basic Wash",
        slug: "sms_otw_#{System.unique_integer([:positive])}",
        base_price_cents: 5_000,
        duration_minutes: 45
      })
      |> Ash.create()

    {:ok, vehicle} =
      MobileCarWash.Fleet.Vehicle
      |> Ash.Changeset.for_create(:create, %{make: "Ford", model: "F-150"})
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create()

    {:ok, address} =
      MobileCarWash.Fleet.Address
      |> Ash.Changeset.for_create(:create, %{street: "789 Elm St", city: "Live Oak", state: "TX", zip: "78233"})
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
        price_cents: 5_000,
        duration_minutes: 45
      })
      |> Ash.Changeset.force_change_attribute(:technician_id, technician.id)
      |> Ash.create()

    %{appointment: appointment, customer: customer}
  end

  test "sends tech on the way SMS", %{appointment: appointment} do
    assert :ok = perform_job(SMSTechOnTheWayWorker, %{"appointment_id" => appointment.id})
    msgs = TwilioClientMock.messages_to("+15125554444")
    assert length(msgs) == 1
    {_to, body} = hd(msgs)
    assert body =~ "Marcus Rivera"
    assert body =~ "on the way"
  end

  test "skips when sms_opt_in is false", %{appointment: appointment, customer: customer} do
    customer
    |> Ash.Changeset.for_update(:update, %{sms_opt_in: false})
    |> Ash.update!(authorize?: false)

    assert :ok = perform_job(SMSTechOnTheWayWorker, %{"appointment_id" => appointment.id})
    assert TwilioClientMock.messages_to("+15125554444") == []
  end
end
