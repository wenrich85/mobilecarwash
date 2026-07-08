defmodule MobileCarWash.Scheduling.AdminCreateBookingTest do
  use MobileCarWash.DataCase, async: false
  use Oban.Testing, repo: MobileCarWash.Repo

  alias MobileCarWash.Scheduling.{Booking, ServiceType, Appointment}
  alias MobileCarWash.Billing.Payment
  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Fleet.{Vehicle, Address}
  alias MobileCarWash.CashFlow.Account, as: CashFlowAccount

  require Ash.Query

  # CashFlowEngine.record_deposit/2 requires the expense account to exist.
  # Seed the five cash-flow accounts exactly as cash_flow_live_test does.
  setup do
    for attrs <- [
          %{account_type: :expense, name: "Expense Account", color: :blue},
          %{account_type: :tax, name: "Tax Account", color: :red},
          %{account_type: :business_savings, name: "Business Savings", color: :blue},
          %{account_type: :investment, name: "Investment Account", color: :blue},
          %{account_type: :personal_salary, name: "Personal Salary", color: :green}
        ] do
      existing =
        CashFlowAccount
        |> Ash.Query.filter(account_type == ^attrs.account_type)
        |> Ash.read!()

      if existing == [] do
        CashFlowAccount
        |> Ash.Changeset.for_create(:create, attrs)
        |> Ash.create!()
      end
    end

    :ok
  end

  defp service do
    ServiceType
    |> Ash.Changeset.for_create(:create, %{
      name: "Basic Wash",
      slug: "basic_#{System.unique_integer([:positive])}",
      base_price_cents: 5000,
      duration_minutes: 45
    })
    |> Ash.create!(authorize?: false)
  end

  defp existing_customer_with_vehicle_and_address do
    cust =
      Customer
      |> Ash.Changeset.for_create(:create_guest, %{
        name: "Existing Client",
        email: "existing-#{System.unique_integer([:positive])}@test.com",
        phone: "+15125550144"
      })
      |> Ash.create!(authorize?: false)

    vehicle =
      Vehicle
      |> Ash.Changeset.for_create(:create, %{make: "Ford", model: "F150", size: :pickup})
      |> Ash.Changeset.force_change_attribute(:customer_id, cust.id)
      |> Ash.create!(authorize?: false)

    address =
      Address
      |> Ash.Changeset.for_create(:create, %{
        street: "9 Oak",
        city: "Austin",
        state: "TX",
        zip: "78701"
      })
      |> Ash.Changeset.force_change_attribute(:customer_id, cust.id)
      |> Ash.create!(authorize?: false)

    %{cust: cust, vehicle: vehicle, address: address}
  end

  defp base_params(svc) do
    %{
      service_type_id: svc.id,
      scheduled_at:
        DateTime.utc_now() |> DateTime.add(3 * 86_400, :second) |> DateTime.truncate(:second),
      notify_client?: false,
      waive_payment?: false
    }
  end

  test "comped booking records full value, zero collected, comped flag" do
    svc = service()
    %{cust: cust, vehicle: v, address: a} = existing_customer_with_vehicle_and_address()

    params =
      base_params(svc)
      |> Map.merge(%{
        customer_id: cust.id,
        vehicle_id: v.id,
        address_id: a.id,
        waive_payment?: true,
        comp_reason: "Owner's neighbor"
      })

    {:ok, %{appointment: appt, payment: payment}} = Booking.admin_create_booking(params)

    # F150 is a pickup → 1.5x of 5000 = 7500 full value
    assert appt.status == :confirmed
    assert appt.appointment_block_id == nil
    assert payment.amount_cents == 7500
    assert payment.collected_cents == 0
    assert payment.comped == true
    assert payment.comp_reason == "Owner's neighbor"
    assert payment.status == :succeeded
    assert payment.appointment_id == appt.id
  end

  test "non-waived booking records the full collected amount" do
    svc = service()
    %{cust: cust, vehicle: v, address: a} = existing_customer_with_vehicle_and_address()

    params =
      base_params(svc)
      |> Map.merge(%{
        customer_id: cust.id,
        vehicle_id: v.id,
        address_id: a.id,
        waive_payment?: false
      })

    {:ok, %{payment: payment}} = Booking.admin_create_booking(params)

    assert payment.comped == false
    assert payment.collected_cents == 7500
  end

  test "creates a new client, vehicle, and address inline" do
    svc = service()
    email = "brandnew-#{System.unique_integer([:positive])}@test.com"

    params =
      base_params(svc)
      |> Map.merge(%{
        new_customer: %{name: "Walk Up", email: email, phone: "+15125550155"},
        new_vehicle: %{make: "Kia", model: "Soul", size: :car},
        new_address: %{street: "5 Elm", city: "Austin", state: "TX", zip: "78701"},
        waive_payment?: true,
        comp_reason: "Promo"
      })

    {:ok, %{appointment: appt}} = Booking.admin_create_booking(params)

    created = Ash.get!(Customer, appt.customer_id, authorize?: false)
    assert to_string(created.email) == email
    assert created.role == :guest
  end

  test "reuses an existing customer when the new_customer email matches" do
    svc = service()
    %{cust: cust} = existing_customer_with_vehicle_and_address()

    params =
      base_params(svc)
      |> Map.merge(%{
        new_customer: %{name: "Dupe", email: to_string(cust.email), phone: "+15125550166"},
        new_vehicle: %{make: "Kia", model: "Soul", size: :car},
        new_address: %{street: "5 Elm", city: "Austin", state: "TX", zip: "78701"},
        waive_payment?: true,
        comp_reason: "Promo"
      })

    {:ok, %{appointment: appt}} = Booking.admin_create_booking(params)
    assert appt.customer_id == cust.id
  end

  test "notify_client? true enqueues confirmation workers; false enqueues none" do
    svc = service()
    %{cust: cust, vehicle: v, address: a} = existing_customer_with_vehicle_and_address()

    silent =
      base_params(svc)
      |> Map.merge(%{
        customer_id: cust.id,
        vehicle_id: v.id,
        address_id: a.id,
        waive_payment?: true,
        comp_reason: "x"
      })

    # Oban is configured with testing: :inline (jobs execute immediately).
    # Switch to :manual so assert_enqueued/refute_enqueued can inspect the queue.
    Oban.Testing.with_testing_mode(:manual, fn ->
      {:ok, _} = Booking.admin_create_booking(silent)
      refute_enqueued(worker: MobileCarWash.Notifications.BookingConfirmationWorker)

      loud = Map.put(silent, :notify_client?, true)
      {:ok, _} = Booking.admin_create_booking(loud)
      assert_enqueued(worker: MobileCarWash.Notifications.BookingConfirmationWorker)
    end)
  end

  test "future-dated admin booking enqueues 24h reminders" do
    svc = service()
    %{cust: cust, vehicle: v, address: a} = existing_customer_with_vehicle_and_address()

    future =
      base_params(svc)
      |> Map.merge(%{
        customer_id: cust.id,
        vehicle_id: v.id,
        address_id: a.id,
        waive_payment?: true,
        comp_reason: "x",
        notify_client?: true
      })

    Oban.Testing.with_testing_mode(:manual, fn ->
      {:ok, _} = Booking.admin_create_booking(future)

      assert_enqueued(worker: MobileCarWash.Notifications.AppointmentReminderWorker)
      assert_enqueued(worker: MobileCarWash.Notifications.SMSAppointmentReminderWorker)
      assert_enqueued(worker: MobileCarWash.Notifications.PushAppointmentReminderWorker)
    end)
  end

  test "past-dated admin booking confirms but skips reminders whose time is already past" do
    svc = service()
    %{cust: cust, vehicle: v, address: a} = existing_customer_with_vehicle_and_address()

    past =
      base_params(svc)
      |> Map.merge(%{
        customer_id: cust.id,
        vehicle_id: v.id,
        address_id: a.id,
        waive_payment?: true,
        comp_reason: "x",
        notify_client?: true,
        scheduled_at:
          DateTime.utc_now() |> DateTime.add(-3 * 86_400, :second) |> DateTime.truncate(:second)
      })

    Oban.Testing.with_testing_mode(:manual, fn ->
      {:ok, _} = Booking.admin_create_booking(past)

      # Confirmations still fire.
      assert_enqueued(worker: MobileCarWash.Notifications.BookingConfirmationWorker)

      # Reminders (scheduled_at - 24h) are already in the past → not enqueued.
      refute_enqueued(worker: MobileCarWash.Notifications.AppointmentReminderWorker)
      refute_enqueued(worker: MobileCarWash.Notifications.SMSAppointmentReminderWorker)
      refute_enqueued(worker: MobileCarWash.Notifications.PushAppointmentReminderWorker)
    end)
  end
end
