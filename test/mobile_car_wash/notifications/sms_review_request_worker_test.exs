defmodule MobileCarWash.Notifications.SMSReviewRequestWorkerTest do
  use MobileCarWash.DataCase, async: false
  use Oban.Testing, repo: MobileCarWash.Repo

  alias MobileCarWash.Notifications.SMSReviewRequestWorker
  alias MobileCarWash.Notifications.TwilioClientMock

  setup do
    TwilioClientMock.init()

    {:ok, customer} =
      MobileCarWash.Accounts.Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "sms-review-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Review Test",
        phone: "+15125551111",
        sms_opt_in: true
      })
      |> Ash.create()

    {:ok, service_type} =
      MobileCarWash.Scheduling.ServiceType
      |> Ash.Changeset.for_create(:create, %{
        name: "Basic Wash",
        slug: "sms_rev_#{System.unique_integer([:positive])}",
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
        street: "123 Test St",
        city: "San Antonio",
        state: "TX",
        zip: "78259"
      })
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create()

    {:ok, scheduled_at} = DateTime.new(~D[2026-05-15], ~T[10:00:00])

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
      |> Ash.create()

    %{appointment: appointment, customer: customer}
  end

  test "sends review request SMS with Google review link", %{appointment: appointment} do
    assert :ok = perform_job(SMSReviewRequestWorker, %{"appointment_id" => appointment.id})
    msgs = TwilioClientMock.messages_to("+15125551111")
    assert length(msgs) == 1
    {_to, body} = hd(msgs)
    assert body =~ "review"
  end

  test "skips when sms_opt_in is false", %{appointment: appointment, customer: customer} do
    customer
    |> Ash.Changeset.for_update(:update, %{sms_opt_in: false})
    |> Ash.update!(authorize?: false)

    assert :ok = perform_job(SMSReviewRequestWorker, %{"appointment_id" => appointment.id})
    assert TwilioClientMock.messages_to("+15125551111") == []
  end
end
