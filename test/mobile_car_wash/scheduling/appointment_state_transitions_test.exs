defmodule MobileCarWash.Scheduling.AppointmentStateTransitionsTest do
  @moduledoc """
  Covers the two new intermediate appointment statuses — :en_route and
  :on_site — plus their corresponding :depart / :arrive actions, the
  notifications they fire, and the PubSub broadcasts admin/customer
  dashboards subscribe to.

  :depart inherits the "tech on the way" notification that used to live
  on :start — it now fires when the tech actually leaves, not when the
  wash begins. :arrive fires a new "tech has arrived" notification.
  """
  use MobileCarWash.DataCase, async: false
  use Oban.Testing, repo: MobileCarWash.Repo

  require Ash.Query

  alias MobileCarWash.Notifications.{ApnsClientMock, DeviceToken, TwilioClientMock}
  alias MobileCarWash.Scheduling.{Appointment, AppointmentTracker, ServiceType}

  setup do
    ApnsClientMock.init()
    TwilioClientMock.init()

    {:ok, customer} =
      MobileCarWash.Accounts.Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "transitions-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Transition Test",
        phone: "+15125554001",
        sms_opt_in: true
      })
      |> Ash.create()

    {:ok, service_type} =
      ServiceType
      |> Ash.Changeset.for_create(:create, %{
        name: "Basic Wash",
        slug: "trans-#{System.unique_integer([:positive])}",
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
        street: "10 Transition Ln",
        city: "San Antonio",
        state: "TX",
        zip: "78259"
      })
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create()

    {:ok, technician} =
      MobileCarWash.Operations.Technician
      |> Ash.Changeset.for_create(:create, %{
        name: "Miguel Transition",
        phone: "+15125559999",
        active: true
      })
      |> Ash.create()

    {:ok, appointment} =
      Appointment
      |> Ash.Changeset.for_create(:book, %{
        customer_id: customer.id,
        vehicle_id: vehicle.id,
        address_id: address.id,
        service_type_id: service_type.id,
        scheduled_at: DateTime.add(DateTime.utc_now(), 2 * 86_400, :second),
        price_cents: 5_000,
        duration_minutes: 45
      })
      |> Ash.create()

    # Assign the tech (required for on-the-way / arrived notifications)
    {:ok, appointment} =
      appointment
      |> Ash.Changeset.for_update(:update, %{})
      |> Ash.Changeset.force_change_attribute(:technician_id, technician.id)
      |> Ash.update(authorize?: false)

    {:ok, _token} =
      DeviceToken
      |> Ash.Changeset.for_create(
        :register,
        %{token: "ios-transition-token", customer_id: customer.id},
        actor: customer
      )
      |> Ash.create(actor: customer)

    # Put appointment into :confirmed so the state-machine tests start
    # from the canonical pre-depart position.
    {:ok, appointment} =
      appointment
      |> Ash.Changeset.for_update(:payment_confirm, %{})
      |> Ash.update(authorize?: false)

    # Drain the verification email enqueued by the register after_action
    # so assert_received below lands on the transition email the test
    # is actually asserting on.
    flush_mailbox()

    %{appointment: appointment, customer: customer}
  end

  describe ":depart action" do
    test "transitions :confirmed -> :en_route", %{appointment: appointment} do
      {:ok, updated} =
        appointment
        |> Ash.Changeset.for_update(:depart, %{})
        |> Ash.update(authorize?: false)

      assert updated.status == :en_route
    end

    test "fires the tech-on-the-way notifications (email + SMS + push)",
         %{appointment: appointment} do
      appointment
      |> Ash.Changeset.for_update(:depart, %{})
      |> Ash.update!(authorize?: false)

      # Email
      assert_received {:email, email}
      assert email.subject =~ "on the way" or email.subject =~ "On The Way"

      # SMS
      assert length(TwilioClientMock.messages()) == 1

      # Push
      assert length(ApnsClientMock.pushes_to("ios-transition-token")) == 1
    end

    test "broadcasts via AppointmentTracker", %{appointment: appointment} do
      AppointmentTracker.subscribe(appointment.id)

      appointment
      |> Ash.Changeset.for_update(:depart, %{})
      |> Ash.update!(authorize?: false)

      assert_receive {:appointment_update, %{event: :departed, status: :en_route}}, 500
    end
  end

  describe ":arrive action" do
    test "transitions :en_route -> :on_site", %{appointment: appointment} do
      {:ok, en_route} =
        appointment
        |> Ash.Changeset.for_update(:depart, %{})
        |> Ash.update(authorize?: false)

      # Clear mocks so the arrive-specific assertions aren't polluted
      ApnsClientMock.init()
      TwilioClientMock.init()

      {:ok, on_site} =
        en_route
        |> Ash.Changeset.for_update(:arrive, %{})
        |> Ash.update(authorize?: false)

      assert on_site.status == :on_site
    end

    test "fires the new tech-arrived notifications (email + SMS + push)",
         %{appointment: appointment} do
      appointment
      |> Ash.Changeset.for_update(:depart, %{})
      |> Ash.update!(authorize?: false)

      # Drain the depart-side side effects
      ApnsClientMock.init()
      TwilioClientMock.init()
      flush_mailbox()

      Ash.get!(Appointment, appointment.id, authorize?: false)
      |> Ash.Changeset.for_update(:arrive, %{})
      |> Ash.update!(authorize?: false)

      assert_received {:email, email}
      assert email.subject =~ "arrived" or email.subject =~ "Arrived"

      assert length(TwilioClientMock.messages()) == 1
      [{_to, body}] = TwilioClientMock.messages()
      assert body =~ "arrived"

      assert length(ApnsClientMock.pushes_to("ios-transition-token")) == 1
      [{_, payload, _}] = ApnsClientMock.pushes_to("ios-transition-token")
      assert payload.data.kind == "tech_arrived"
    end

    test "broadcasts via AppointmentTracker", %{appointment: appointment} do
      AppointmentTracker.subscribe(appointment.id)

      {:ok, en_route} =
        appointment
        |> Ash.Changeset.for_update(:depart, %{})
        |> Ash.update(authorize?: false)

      en_route
      |> Ash.Changeset.for_update(:arrive, %{})
      |> Ash.update!(authorize?: false)

      assert_receive {:appointment_update, %{event: :arrived, status: :on_site}}, 500
    end
  end

  describe ":start action (behavior change)" do
    test "no longer fires the tech-on-the-way notifications",
         %{appointment: appointment} do
      appointment
      |> Ash.Changeset.for_update(:start, %{})
      |> Ash.update!(authorize?: false)

      # None of the on-the-way channels should fire from :start any more
      refute_received {:email, %{subject: "Tech is on the way" <> _}}
      assert ApnsClientMock.pushes_to("ios-transition-token")
             |> Enum.any?(fn {_, p, _} -> p.data.kind == "tech_on_the_way" end) == false

      assert TwilioClientMock.messages() == []
    end

    test "still transitions to :in_progress and broadcasts :started",
         %{appointment: appointment} do
      AppointmentTracker.subscribe(appointment.id)

      {:ok, updated} =
        appointment
        |> Ash.Changeset.for_update(:start, %{})
        |> Ash.update(authorize?: false)

      assert updated.status == :in_progress
      assert_receive {:appointment_update, %{event: :started, status: :in_progress}}, 500
    end
  end

  defp flush_mailbox do
    receive do
      {:email, _} -> flush_mailbox()
    after
      0 -> :ok
    end
  end
end
