defmodule MobileCarWash.Notifications.PushBookingConfirmationWorkerTest do
  use MobileCarWash.DataCase, async: false
  use Oban.Testing, repo: MobileCarWash.Repo

  require Ash.Query

  alias MobileCarWash.Notifications.{ApnsClientMock, DeviceToken, PushBookingConfirmationWorker}

  setup do
    ApnsClientMock.init()

    {:ok, customer} =
      MobileCarWash.Accounts.Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "push-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Push Test",
        phone: "+15125551234"
      })
      |> Ash.create()

    {:ok, service_type} =
      MobileCarWash.Scheduling.ServiceType
      |> Ash.Changeset.for_create(:create, %{
        name: "Basic Wash",
        slug: "push_bw_#{System.unique_integer([:positive])}",
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

  defp register_token(customer, token) do
    DeviceToken
    |> Ash.Changeset.for_create(
      :register,
      %{token: token, customer_id: customer.id},
      actor: customer
    )
    |> Ash.create(actor: customer)
  end

  test "sends push to each active device token for the customer",
       %{appointment: appointment, customer: customer} do
    {:ok, _t1} = register_token(customer, "ios-token-1")
    {:ok, _t2} = register_token(customer, "ios-token-2")

    assert :ok =
             perform_job(PushBookingConfirmationWorker, %{"appointment_id" => appointment.id})

    assert length(ApnsClientMock.pushes_to("ios-token-1")) == 1
    assert length(ApnsClientMock.pushes_to("ios-token-2")) == 1

    {_token, payload, _opts} = hd(ApnsClientMock.pushes_to("ios-token-1"))
    assert payload.aps.alert.title == "Booking confirmed"
    assert payload.aps.alert.body =~ "Basic Wash"
    assert payload.data.appointment_id == appointment.id
    assert payload.data.kind == "booking_confirmed"
  end

  test "skips inactive tokens", %{appointment: appointment, customer: customer} do
    {:ok, active} = register_token(customer, "ios-active")
    {:ok, inactive} = register_token(customer, "ios-inactive")

    {:ok, _} =
      inactive
      |> Ash.Changeset.for_update(:deactivate, %{})
      |> Ash.update(authorize?: false)

    _ = active

    :ok = perform_job(PushBookingConfirmationWorker, %{"appointment_id" => appointment.id})

    assert length(ApnsClientMock.pushes_to("ios-active")) == 1
    assert ApnsClientMock.pushes_to("ios-inactive") == []
  end

  test "no-ops when the customer has no registered tokens",
       %{appointment: appointment} do
    :ok = perform_job(PushBookingConfirmationWorker, %{"appointment_id" => appointment.id})
    assert ApnsClientMock.pushes() == []
  end

  test "skips send when customer.push_opt_in is false",
       %{appointment: appointment, customer: customer} do
    {:ok, _token} = register_token(customer, "ios-opt-out")

    customer
    |> Ash.Changeset.for_update(:update, %{push_opt_in: false})
    |> Ash.update!(authorize?: false)

    :ok = perform_job(PushBookingConfirmationWorker, %{"appointment_id" => appointment.id})
    assert ApnsClientMock.pushes() == []
  end

  test "marks a token inactive when APNs reports :unregistered",
       %{appointment: appointment, customer: customer} do
    {:ok, token} = register_token(customer, "ios-dead")
    ApnsClientMock.stub("ios-dead", {:error, :unregistered})

    :ok = perform_job(PushBookingConfirmationWorker, %{"appointment_id" => appointment.id})

    {:ok, reloaded} = Ash.get(DeviceToken, token.id, authorize?: false)
    assert reloaded.active == false
    assert reloaded.failure_reason == "unregistered"
    assert reloaded.failed_at
  end

  test "marks a token inactive when APNs reports :bad_device_token",
       %{appointment: appointment, customer: customer} do
    {:ok, token} = register_token(customer, "ios-bad")
    ApnsClientMock.stub("ios-bad", {:error, :bad_device_token})

    :ok = perform_job(PushBookingConfirmationWorker, %{"appointment_id" => appointment.id})

    {:ok, reloaded} = Ash.get(DeviceToken, token.id, authorize?: false)
    assert reloaded.active == false
    assert reloaded.failure_reason == "bad_device_token"
  end

  test "leaves a token active on transient errors (retryable)",
       %{appointment: appointment, customer: customer} do
    {:ok, token} = register_token(customer, "ios-overloaded")
    ApnsClientMock.stub("ios-overloaded", {:error, :too_many_requests})

    :ok = perform_job(PushBookingConfirmationWorker, %{"appointment_id" => appointment.id})

    {:ok, reloaded} = Ash.get(DeviceToken, token.id, authorize?: false)
    assert reloaded.active == true
  end
end
