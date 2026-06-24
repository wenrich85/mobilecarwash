defmodule MobileCarWashWeb.DashboardLiveTest do
  use MobileCarWashWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MobileCarWash.Billing.{Subscription, SubscriptionPlan}
  alias MobileCarWash.Scheduling.{Appointment, RecurringSchedule}

  require Ash.Query

  # Builds a registered customer and signs them in. Returns {conn, customer}.
  defp register_and_sign_in(conn) do
    {:ok, customer} =
      MobileCarWash.Accounts.Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "dash-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Dash Test",
        phone: "+15125550000"
      })
      |> Ash.create()

    conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> post("/auth/customer/password/sign_in", %{
        "customer" => %{
          "email" => to_string(customer.email),
          "password" => "Password123!"
        }
      })
      |> recycle()

    {conn, customer}
  end

  defp create_plan do
    SubscriptionPlan
    |> Ash.Changeset.for_create(:create, %{
      name: "Standard Plan",
      slug: "dash_plan_#{System.unique_integer([:positive])}",
      price_cents: 12_500,
      basic_washes_per_month: 4,
      deep_cleans_per_month: 0,
      deep_clean_discount_percent: 30,
      description: "dashboard test plan"
    })
    |> Ash.create!()
  end

  defp create_active_subscription(customer, plan) do
    Subscription
    |> Ash.Changeset.for_create(:create, %{status: :active})
    |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
    |> Ash.Changeset.force_change_attribute(:plan_id, plan.id)
    |> Ash.create!()
  end

  test "unauthenticated user is redirected to sign-in" do
    conn = build_conn()
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/dashboard")
  end

  test "subscriber-less customer is redirected to /subscribe", %{conn: conn} do
    {conn, _customer} = register_and_sign_in(conn)
    assert {:error, {:redirect, %{to: "/subscribe"}}} = live(conn, ~p"/dashboard")
  end

  test "active subscriber sees the dashboard with plan name and usage", %{conn: conn} do
    {conn, customer} = register_and_sign_in(conn)
    plan = create_plan()
    create_active_subscription(customer, plan)

    {:ok, _view, html} = live(conn, ~p"/dashboard")

    assert html =~ "Your Dashboard"
    assert html =~ "Standard Plan"
    assert html =~ "Basic Washes"
  end

  # Creates an active subscription + a recurring schedule for the customer.
  # Returns the schedule.
  defp create_schedule(customer) do
    {:ok, service_type} =
      MobileCarWash.Scheduling.ServiceType
      |> Ash.Changeset.for_create(:create, %{
        name: "Basic Wash",
        slug: "dash_sched_#{System.unique_integer([:positive])}",
        base_price_cents: 5_000,
        duration_minutes: 45
      })
      |> Ash.create()

    {:ok, vehicle} =
      MobileCarWash.Fleet.Vehicle
      |> Ash.Changeset.for_create(:create, %{make: "Toyota", model: "Camry", year: 2021})
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

    {:ok, schedule} =
      RecurringSchedule
      |> Ash.Changeset.for_create(:create, %{
        frequency: :weekly,
        preferred_day: 3,
        preferred_time: ~T[10:00:00]
      })
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.Changeset.force_change_attribute(:vehicle_id, vehicle.id)
      |> Ash.Changeset.force_change_attribute(:address_id, address.id)
      |> Ash.Changeset.force_change_attribute(:service_type_id, service_type.id)
      |> Ash.create()

    schedule
  end

  test "renders a recurring schedule row", %{conn: conn} do
    {conn, customer} = register_and_sign_in(conn)
    create_active_subscription(customer, create_plan())
    create_schedule(customer)

    {:ok, _view, html} = live(conn, ~p"/dashboard")

    assert html =~ "Recurring Wash-Days"
    assert html =~ "Basic Wash"
    assert html =~ "Every week"
  end

  test "shows recurring empty state when no schedules exist", %{conn: conn} do
    {conn, customer} = register_and_sign_in(conn)
    create_active_subscription(customer, create_plan())

    {:ok, _view, html} = live(conn, ~p"/dashboard")
    assert html =~ "No recurring wash-days yet"
  end

  test "can edit recurring preferences", %{conn: conn} do
    {conn, customer} = register_and_sign_in(conn)
    create_active_subscription(customer, create_plan())
    schedule = create_schedule(customer)

    {:ok, view, _html} = live(conn, ~p"/dashboard")

    view |> element("button[phx-value-id='#{schedule.id}']", "Edit") |> render_click()

    html =
      view
      |> form("#edit-schedule-#{schedule.id}", %{
        "schedule" => %{
          "frequency" => "biweekly",
          "preferred_day" => "5",
          "preferred_time" => "14:30"
        }
      })
      |> render_submit()

    assert html =~ "Schedule updated"
    assert html =~ "Every 2 weeks"

    updated = Ash.get!(RecurringSchedule, schedule.id)
    assert updated.frequency == :biweekly
    assert updated.preferred_day == 5
    assert updated.preferred_time == ~T[14:30:00]
  end

  test "can pause and resume a schedule", %{conn: conn} do
    {conn, customer} = register_and_sign_in(conn)
    create_active_subscription(customer, create_plan())
    create_schedule(customer)

    {:ok, view, _html} = live(conn, ~p"/dashboard")

    html = view |> element("button", "Pause") |> render_click()
    assert html =~ "Schedule paused"

    html = view |> element("button", "Resume") |> render_click()
    assert html =~ "Schedule resumed"
  end

  # Books a future appointment for the customer. Returns the appointment.
  defp create_upcoming_appointment(customer) do
    {:ok, service_type} =
      MobileCarWash.Scheduling.ServiceType
      |> Ash.Changeset.for_create(:create, %{
        name: "Deluxe Wash",
        slug: "dash_appt_#{System.unique_integer([:positive])}",
        base_price_cents: 7_500,
        duration_minutes: 60
      })
      |> Ash.create()

    {:ok, vehicle} =
      MobileCarWash.Fleet.Vehicle
      |> Ash.Changeset.for_create(:create, %{make: "Honda", model: "Civic", year: 2022})
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create()

    {:ok, address} =
      MobileCarWash.Fleet.Address
      |> Ash.Changeset.for_create(:create, %{
        street: "200 Oak St",
        city: "San Antonio",
        state: "TX",
        zip: "78259"
      })
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create()

    future = DateTime.add(DateTime.utc_now(), 3 * 24 * 3600)

    {:ok, appointment} =
      Appointment
      |> Ash.Changeset.for_create(:book, %{
        scheduled_at: future,
        price_cents: 7_500,
        duration_minutes: 60,
        customer_id: customer.id,
        vehicle_id: vehicle.id,
        address_id: address.id,
        service_type_id: service_type.id
      })
      |> Ash.create()

    appointment
  end

  test "renders an upcoming wash", %{conn: conn} do
    {conn, customer} = register_and_sign_in(conn)
    create_active_subscription(customer, create_plan())
    create_upcoming_appointment(customer)

    {:ok, _view, html} = live(conn, ~p"/dashboard")

    assert html =~ "Upcoming Washes"
    assert html =~ "Deluxe Wash"
    assert html =~ "Honda Civic"
  end

  test "shows upcoming empty state when none are booked", %{conn: conn} do
    {conn, customer} = register_and_sign_in(conn)
    create_active_subscription(customer, create_plan())

    {:ok, _view, html} = live(conn, ~p"/dashboard")
    assert html =~ "No upcoming washes"
  end

  test "can attach add-ons to a recurring schedule", %{conn: conn} do
    {conn, customer} = register_and_sign_in(conn)
    create_active_subscription(customer, create_plan())
    schedule = create_schedule(customer)

    {:ok, addon} =
      MobileCarWash.Scheduling.AddOn
      |> Ash.Changeset.for_create(:create, %{
        name: "Wax Coat",
        slug: "wax-#{System.unique_integer([:positive])}",
        price_cents: 2_000
      })
      |> Ash.create()

    {:ok, view, _html} = live(conn, ~p"/dashboard")

    view |> element("button[phx-value-id='#{schedule.id}']", "Manage add-ons") |> render_click()

    html =
      view
      |> form("#manage-addons-#{schedule.id}", %{"add_on_ids" => [addon.id]})
      |> render_submit()

    assert html =~ "Add-ons updated"

    assert MobileCarWash.Scheduling.AppointmentServices.schedule_add_on_ids(schedule.id) == [
             addon.id
           ]
  end

  test "Panel B shows the add-on per-wash cost with cents (no truncation)", %{conn: conn} do
    {conn, customer} = register_and_sign_in(conn)
    create_active_subscription(customer, create_plan())
    schedule = create_schedule(customer)

    {:ok, addon} =
      MobileCarWash.Scheduling.AddOn
      |> Ash.Changeset.for_create(:create, %{
        name: "Clay Bar",
        slug: "clay-#{System.unique_integer([:positive])}",
        price_cents: 1_999
      })
      |> Ash.create()

    :ok =
      MobileCarWash.Scheduling.AppointmentServices.replace_schedule_add_ons(schedule.id, [
        addon.id
      ])

    {:ok, _view, html} = live(conn, ~p"/dashboard")

    # Non-round add-on price must keep its cents (was truncating to "$19").
    assert html =~ "$19.99 add-ons per wash"
  end

  test "Panel C pluralizes the upcoming-wash add-on count", %{conn: conn} do
    {conn, customer} = register_and_sign_in(conn)
    create_active_subscription(customer, create_plan())
    appt = create_upcoming_appointment(customer)

    {:ok, a1} =
      MobileCarWash.Scheduling.AddOn
      |> Ash.Changeset.for_create(:create, %{
        name: "Wax",
        slug: "wax-#{System.unique_integer([:positive])}",
        price_cents: 1_000
      })
      |> Ash.create()

    {:ok, a2} =
      MobileCarWash.Scheduling.AddOn
      |> Ash.Changeset.for_create(:create, %{
        name: "Shine",
        slug: "shine-#{System.unique_integer([:positive])}",
        price_cents: 1_000
      })
      |> Ash.create()

    {:ok, _} = MobileCarWash.Scheduling.AppointmentServices.add(appt, [a1.id, a2.id])

    {:ok, _view, html} = live(conn, ~p"/dashboard")

    assert html =~ "2 add-ons"
    refute html =~ "add-on(s)"
  end

  test "can add services to an editable upcoming appointment (card success)", %{conn: conn} do
    {conn, customer} = register_and_sign_in(conn)
    # give the signed-in customer a charge-able Stripe id
    customer
    |> Ash.Changeset.for_update(:update, %{stripe_customer_id: "cus_test_panelc"})
    |> Ash.update!(authorize?: false)

    create_active_subscription(customer, create_plan())
    appt = create_upcoming_appointment(customer)

    {:ok, addon} =
      MobileCarWash.Scheduling.AddOn
      |> Ash.Changeset.for_create(:create, %{
        name: "Tire Shine",
        slug: "ts-#{System.unique_integer([:positive])}",
        price_cents: 1_500
      })
      |> Ash.create()

    {:ok, view, _html} = live(conn, ~p"/dashboard")

    view |> element("button[phx-value-id='#{appt.id}']", "Add services") |> render_click()

    html =
      view
      |> form("#add-services-#{appt.id}", %{"add_on_ids" => [addon.id]})
      |> render_submit()

    assert html =~ "Services added"
    assert Ash.get!(MobileCarWash.Scheduling.Appointment, appt.id).price_cents == 7_500 + 1_500
  end

  test "non-editable appointment shows a too-late note and no picker", %{conn: conn} do
    {conn, customer} = register_and_sign_in(conn)
    create_active_subscription(customer, create_plan())
    appt = create_upcoming_appointment(customer)
    # move it inside the 12h cutoff
    appt
    |> Ash.Changeset.for_update(:update, %{
      scheduled_at: DateTime.add(DateTime.utc_now(), 6 * 3600)
    })
    |> Ash.update!()

    {:ok, _view, html} = live(conn, ~p"/dashboard")
    assert html =~ "Too late to modify"
    refute html =~ "add-services-#{appt.id}"
  end

  test "cannot edit another customer's schedule", %{conn: conn} do
    {conn, customer} = register_and_sign_in(conn)
    create_active_subscription(customer, create_plan())

    {:ok, other} =
      MobileCarWash.Accounts.Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "other-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Other",
        phone: "+15125550001"
      })
      |> Ash.create()

    other_schedule = create_schedule(other)

    {:ok, view, _html} = live(conn, ~p"/dashboard")

    # The other customer's schedule must not appear in this dashboard at all,
    # and a forged save event must not mutate it.
    render_hook(view, "save_preferences", %{
      "schedule_id" => other_schedule.id,
      "schedule" => %{
        "frequency" => "monthly",
        "preferred_day" => "1",
        "preferred_time" => "09:00"
      }
    })

    unchanged = Ash.get!(RecurringSchedule, other_schedule.id)
    assert unchanged.frequency == :weekly
  end
end
