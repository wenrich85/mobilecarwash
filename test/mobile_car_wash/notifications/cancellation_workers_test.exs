defmodule MobileCarWash.Notifications.CancellationWorkersTest do
  @moduledoc """
  Covers the three cancellation notification workers (email, SMS, push) and
  verifies that the Appointment `:cancel` after-action hook enqueues all
  three on the `:notifications` queue.
  """
  use MobileCarWash.DataCase, async: false
  use Oban.Testing, repo: MobileCarWash.Repo

  require Ash.Query

  alias MobileCarWash.Notifications.{
    ApnsClientMock,
    BookingCancelledWorker,
    DeviceToken,
    PushBookingCancelledWorker,
    SMSBookingCancelledWorker,
    TwilioClientMock
  }

  alias MobileCarWash.Scheduling.Appointment

  setup do
    ApnsClientMock.init()
    TwilioClientMock.init()

    {:ok, customer} =
      MobileCarWash.Accounts.Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "cancel-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Cancel Test",
        phone: "+15125559000",
        sms_opt_in: true
      })
      |> Ash.create()

    # The :register_with_password after_action enqueues a verification
    # email. Drain it so assert_received below lands on the cancellation
    # email this test actually cares about.
    flush_mailbox()

    {:ok, service_type} =
      MobileCarWash.Scheduling.ServiceType
      |> Ash.Changeset.for_create(:create, %{
        name: "Basic Wash",
        slug: "cancel_bw_#{System.unique_integer([:positive])}",
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
        street: "99 Cancel St",
        city: "San Antonio",
        state: "TX",
        zip: "78259"
      })
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create()

    {:ok, scheduled_at} = DateTime.new(~D[2026-05-20], ~T[14:00:00])

    {:ok, appointment} =
      Appointment
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

    {:ok, _token} =
      DeviceToken
      |> Ash.Changeset.for_create(
        :register,
        %{token: "ios-cancel-token", customer_id: customer.id},
        actor: customer
      )
      |> Ash.create(actor: customer)

    %{appointment: appointment, customer: customer}
  end

  describe "Appointment :cancel after_action" do
    # Oban's test config is :inline, so the three workers run synchronously
    # when :cancel fires — assert on the observable side effects rather than
    # on job presence in the queue.
    test "fires email, SMS, and push cancellation notifications",
         %{appointment: appointment} do
      appointment
      |> Ash.Changeset.for_update(:cancel, %{cancellation_reason: "schedule conflict"})
      |> Ash.update!(authorize?: false)

      # Email
      assert_received {:email, email}
      assert email.subject =~ "Cancelled"

      # SMS
      assert length(TwilioClientMock.messages()) == 1

      # Push
      assert length(ApnsClientMock.pushes_to("ios-cancel-token")) == 1
    end
  end

  describe "PushBookingCancelledWorker" do
    test "sends a cancellation push to active tokens", %{appointment: appointment} do
      :ok =
        perform_job(PushBookingCancelledWorker, %{"appointment_id" => appointment.id})

      [{_, payload, _}] = ApnsClientMock.pushes_to("ios-cancel-token")
      assert payload.aps.alert.title == "Booking cancelled"
      assert payload.aps.alert.body =~ "Basic Wash"
      assert payload.aps.badge == 0
      assert payload.data.kind == "booking_cancelled"
      assert payload.data.appointment_id == appointment.id
    end
  end

  describe "SMSBookingCancelledWorker" do
    test "sends a cancellation SMS", %{appointment: appointment} do
      :ok = perform_job(SMSBookingCancelledWorker, %{"appointment_id" => appointment.id})

      msgs = TwilioClientMock.messages_to("+15125559000")
      assert length(msgs) == 1
      {_to, body} = hd(msgs)
      assert body =~ "cancelled"
      assert body =~ "Basic Wash"
    end

    test "skips when customer has sms_opt_in: false",
         %{appointment: appointment, customer: customer} do
      customer
      |> Ash.Changeset.for_update(:update, %{sms_opt_in: false})
      |> Ash.update!(authorize?: false)

      :ok = perform_job(SMSBookingCancelledWorker, %{"appointment_id" => appointment.id})
      assert TwilioClientMock.messages() == []
    end
  end

  describe "BookingCancelledWorker (email)" do
    test "delivers an email to the customer", %{appointment: appointment, customer: customer} do
      :ok = perform_job(BookingCancelledWorker, %{"appointment_id" => appointment.id})

      assert_received {:email, email}
      assert [{_, address}] = email.to
      assert address == to_string(customer.email)
      assert email.subject =~ "cancelled" or email.subject =~ "Cancelled"
    end
  end

  # The :register_with_password after_action enqueues a verification email
  # before the test's own action runs. Without draining, assert_received
  # lands on the verification email first.
  defp flush_mailbox do
    receive do
      {:email, _} -> flush_mailbox()
    after
      0 -> :ok
    end
  end
end
