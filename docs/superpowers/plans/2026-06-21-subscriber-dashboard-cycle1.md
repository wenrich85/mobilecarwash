# Subscriber Dashboard — Cycle 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a subscriber-gated `/dashboard` that shows subscription status (Panel A), lets subscribers edit/activate/deactivate/delete their recurring wash-days (Panel B), and lists upcoming washes read-only (Panel C).

**Architecture:** A new `MobileCarWashWeb.DashboardLive` mounted in the existing `:authenticated` live_session. `mount/3` enforces a **subscription gate** (no active subscription → redirect to `/subscribe`), then composes three panels from existing domain reads. The only new backend unit in this cycle is a `RecurringSchedule.:update_preferences` update action; everything else reuses existing actions (`Subscription.:active_for_customer`, `RecurringSchedule.:for_customer`/`:activate`/`:deactivate`/`destroy`, `Appointment.:upcoming`).

**Tech Stack:** Elixir, Phoenix LiveView (HEEx + daisyUI/Tailwind classes), Ash framework + AshPostgres, Oban (unused this cycle). Tests: ExUnit + `Phoenix.LiveViewTest` via `MobileCarWashWeb.ConnCase`.

## Global Constraints

- **Branch:** all work on `feature/subscriber-dashboard` (already created from `main`). Do NOT implement on `main`.
- **Convention files** `config/dev.exs`, `AGENTS.md`, `docs/customer-flows.html` are long-standing uncommitted working-tree edits — never `git add` them. They are already restored in the working tree; leave them alone.
- **Gate:** `mix precommit` (compile `--warnings-as-errors`, `deps.unlock --unused`, format, full test suite) must pass before the cycle is done. Baseline is ~1297 tests / 0 failures.
- **Subscriber-gate redirect target is `/subscribe`** (public `SubscriptionLive` plan picker) — this CORRECTS the spec, which said `/account/subscription`. Use `~p"/subscribe"` everywhere the gate fires. This matches `SubscriptionManageLive`'s own "View Plans → /subscribe" affordance.
- **This is Cycle 1 of 2.** Add-ons (recurring + one-off), off-session charging, the Stripe webhook extension, and scheduler integration are **Cycle 2** and are explicitly OUT of scope here. Panel B has NO "manage add-ons" control and Panel C has NO "add services" control in this cycle.
- **Ownership:** every per-row action must verify `record.customer_id == current_customer.id` before mutating, and bail to a generic error flash on mismatch. Never trust the client-supplied id.
- **Ash idioms (match existing code):** create/read via `Ash.Changeset.for_create/for_update` + `Ash.create/update`, `Ash.Query.for_read/3`, `Ash.get/2`, `Ash.read!/1`, `force_change_attribute/3` for relationship FKs. Times parsed with `Time.from_iso8601("HH:MM:00")`.

---

## File Structure

- **Create** `lib/mobile_car_wash_web/live/dashboard_live.ex` — the entire dashboard LiveView (mount + gate + 3 panels + event handlers + private data loaders + format helpers). One file, one responsibility (the dashboard screen), mirroring the existing `recurring_schedule_manage_live.ex` / `subscription_manage_live.ex` structure.
- **Modify** `lib/mobile_car_wash/scheduling/recurring_schedule.ex` — add the `:update_preferences` update action.
- **Modify** `lib/mobile_car_wash_web/router.ex` — add `live "/dashboard", DashboardLive` inside the `:authenticated` live_session.
- **Create** `test/mobile_car_wash/scheduling/recurring_schedule_preferences_test.exs` — unit tests for the new action.
- **Create** `test/mobile_car_wash_web/live/dashboard_live_test.exs` — LiveView tests for gate + all three panels.

---

## Task 1: `RecurringSchedule.:update_preferences` action

**Files:**
- Modify: `lib/mobile_car_wash/scheduling/recurring_schedule.ex` (actions block, after `:mark_scheduled` ~line 71)
- Test: `test/mobile_car_wash/scheduling/recurring_schedule_preferences_test.exs` (create)

**Interfaces:**
- Produces: an Ash update action `:update_preferences` on `MobileCarWash.Scheduling.RecurringSchedule` accepting `frequency` (`:weekly|:biweekly|:monthly`), `preferred_day` (integer 1–7), `preferred_time` (`Time`). Called as `schedule |> Ash.Changeset.for_update(:update_preferences, %{frequency: ..., preferred_day: ..., preferred_time: ...}) |> Ash.update()`. No payment, no ownership logic inside the action (ownership is enforced at the call site in Task 3).

- [ ] **Step 1: Write the failing test**

Create `test/mobile_car_wash/scheduling/recurring_schedule_preferences_test.exs`:

```elixir
defmodule MobileCarWash.Scheduling.RecurringSchedulePreferencesTest do
  use MobileCarWash.DataCase, async: false

  alias MobileCarWash.Scheduling.RecurringSchedule

  setup do
    {:ok, customer} =
      MobileCarWash.Accounts.Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "recur-pref-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Recur Pref",
        phone: "+15125550000"
      })
      |> Ash.create()

    {:ok, service_type} =
      MobileCarWash.Scheduling.ServiceType
      |> Ash.Changeset.for_create(:create, %{
        name: "Basic Wash",
        slug: "recur_pref_#{System.unique_integer([:positive])}",
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

    %{schedule: schedule}
  end

  test "update_preferences changes frequency, day, and time", %{schedule: schedule} do
    {:ok, updated} =
      schedule
      |> Ash.Changeset.for_update(:update_preferences, %{
        frequency: :biweekly,
        preferred_day: 5,
        preferred_time: ~T[14:30:00]
      })
      |> Ash.update()

    assert updated.frequency == :biweekly
    assert updated.preferred_day == 5
    assert updated.preferred_time == ~T[14:30:00]
  end

  test "update_preferences leaves other attributes untouched", %{schedule: schedule} do
    {:ok, updated} =
      schedule
      |> Ash.Changeset.for_update(:update_preferences, %{
        frequency: :monthly,
        preferred_day: 1,
        preferred_time: ~T[09:00:00]
      })
      |> Ash.update()

    assert updated.active == true
    assert updated.customer_id == schedule.customer_id
    assert updated.vehicle_id == schedule.vehicle_id
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/mobile_car_wash/scheduling/recurring_schedule_preferences_test.exs`
Expected: FAIL — `No such action :update_preferences for ...RecurringSchedule` (action not defined yet).

- [ ] **Step 3: Add the action**

In `lib/mobile_car_wash/scheduling/recurring_schedule.ex`, inside the `actions do` block, immediately after the `:mark_scheduled` action (before `read :active_schedules`):

```elixir
    update :update_preferences do
      accept([:frequency, :preferred_day, :preferred_time])
    end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/mobile_car_wash/scheduling/recurring_schedule_preferences_test.exs`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/mobile_car_wash/scheduling/recurring_schedule.ex test/mobile_car_wash/scheduling/recurring_schedule_preferences_test.exs
git commit -m "feat(scheduling): add RecurringSchedule :update_preferences action"
```

---

## Task 2: DashboardLive route + subscription gate + Panel A (subscription summary)

**Files:**
- Create: `lib/mobile_car_wash_web/live/dashboard_live.ex`
- Modify: `lib/mobile_car_wash_web/router.ex` (the `:authenticated` live_session block, ~lines 195–205)
- Test: `test/mobile_car_wash_web/live/dashboard_live_test.exs` (create)

**Interfaces:**
- Produces: `MobileCarWashWeb.DashboardLive` live_view at route `/dashboard`. After this task, `mount/3` assigns `:subscription`, `:plan`, `:usage`, `:page_title` and renders Panel A. Later tasks add `:schedules` (Task 3) and `:upcoming` (Task 4) assigns plus their panels.
- Consumes: `Subscription.:active_for_customer` read (returns subscriptions with status in `[:active, :paused, :past_due]`), `SubscriptionPlan` by id, `SubscriptionUsage` filtered to the current period.

- [ ] **Step 1: Write the failing tests**

Create `test/mobile_car_wash_web/live/dashboard_live_test.exs`:

```elixir
defmodule MobileCarWashWeb.DashboardLiveTest do
  use MobileCarWashWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MobileCarWash.Billing.{Subscription, SubscriptionPlan}

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
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/mobile_car_wash_web/live/dashboard_live_test.exs`
Expected: FAIL — route `/dashboard` not found / `DashboardLive` undefined (the unauthenticated test may pass incidentally; the other two fail).

- [ ] **Step 3: Create the LiveView with gate + Panel A**

Create `lib/mobile_car_wash_web/live/dashboard_live.ex`:

```elixir
defmodule MobileCarWashWeb.DashboardLive do
  @moduledoc """
  Subscriber home. Gated to active subscribers; non-subscribers are sent
  to the plan picker. Composes subscription status, recurring wash-days,
  and upcoming washes from existing domain reads.
  """
  use MobileCarWashWeb, :live_view

  alias MobileCarWash.Billing.{Subscription, SubscriptionPlan, SubscriptionUsage}

  require Ash.Query

  @impl true
  def mount(_params, _session, socket) do
    customer = socket.assigns.current_customer

    case load_subscription(customer.id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "A subscription is required to access your dashboard.")
         |> redirect(to: ~p"/subscribe")}

      {subscription, plan, usage} ->
        {:ok,
         assign(socket,
           page_title: "Your Dashboard",
           subscription: subscription,
           plan: plan,
           usage: usage
         )}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto py-8 px-4 space-y-6">
      <h1 class="text-2xl font-bold">Your Dashboard</h1>

      <!-- Panel A: Subscription summary -->
      <div class="card bg-base-100 shadow">
        <div class="card-body">
          <div class="flex justify-between items-start">
            <div>
              <h2 class="card-title">{@plan.name}</h2>
              <p class="text-2xl font-bold text-primary mt-1">${div(@plan.price_cents, 100)}/mo</p>
            </div>
            <span class={["badge badge-lg", status_badge(@subscription.status)]}>
              {format_status(@subscription.status)}
            </span>
          </div>

          <div :if={@subscription.current_period_end} class="mt-2 text-sm text-base-content/80">
            Current period ends {Calendar.strftime(@subscription.current_period_end, "%b %d, %Y")}
          </div>

          <div :if={@plan.basic_washes_per_month > 0} class="mt-4">
            <div class="flex justify-between text-sm mb-1">
              <span>Basic Washes</span>
              <span>{washes_remaining(@plan.basic_washes_per_month, @usage.basic_washes_used)} left</span>
            </div>
            <progress
              class="progress progress-primary w-full"
              value={@usage.basic_washes_used}
              max={@plan.basic_washes_per_month}
            />
          </div>

          <div :if={@plan.deep_cleans_per_month > 0} class="mt-4">
            <div class="flex justify-between text-sm mb-1">
              <span>Deep Cleans</span>
              <span>{washes_remaining(@plan.deep_cleans_per_month, @usage.deep_cleans_used)} left</span>
            </div>
            <progress
              class="progress progress-secondary w-full"
              value={@usage.deep_cleans_used}
              max={@plan.deep_cleans_per_month}
            />
          </div>

          <div class="mt-4">
            <.link navigate={~p"/account/subscription"} class="btn btn-outline btn-sm btn-block">
              Manage Subscription &amp; Billing
            </.link>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # --- data loading ---

  defp load_subscription(customer_id) do
    subscription =
      Subscription
      |> Ash.Query.for_read(:active_for_customer, %{customer_id: customer_id})
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.read!()
      |> List.first()

    case subscription do
      nil ->
        nil

      sub ->
        plan = Ash.get!(SubscriptionPlan, sub.plan_id)
        today = Date.utc_today()

        usage =
          SubscriptionUsage
          |> Ash.Query.filter(
            subscription_id == ^sub.id and
              period_start <= ^today and
              period_end >= ^today
          )
          |> Ash.read!()
          |> List.first()

        usage = usage || %{basic_washes_used: 0, deep_cleans_used: 0}
        {sub, plan, usage}
    end
  end

  # --- formatting helpers ---

  defp washes_remaining(allowance, used), do: max(allowance - used, 0)

  defp status_badge(:active), do: "badge-success"
  defp status_badge(:paused), do: "badge-warning"
  defp status_badge(:past_due), do: "badge-error"
  defp status_badge(_), do: "badge-ghost"

  defp format_status(:active), do: "Active"
  defp format_status(:paused), do: "Paused"
  defp format_status(:past_due), do: "Past Due"
  defp format_status(s), do: to_string(s)
end
```

- [ ] **Step 4: Add the route**

In `lib/mobile_car_wash_web/router.ex`, inside the `live_session :authenticated do ... end` block, add `/dashboard` as the first route (just before `live "/appointments", AppointmentsLive`):

```elixir
      live "/dashboard", DashboardLive
      live "/appointments", AppointmentsLive
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `mix test test/mobile_car_wash_web/live/dashboard_live_test.exs`
Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/mobile_car_wash_web/live/dashboard_live.ex lib/mobile_car_wash_web/router.ex test/mobile_car_wash_web/live/dashboard_live_test.exs
git commit -m "feat(dashboard): add subscriber-gated DashboardLive with subscription panel"
```

---

## Task 3: Panel B — recurring wash-days (list + inline edit + activate/deactivate/delete)

**Files:**
- Modify: `lib/mobile_car_wash_web/live/dashboard_live.ex` (mount, render, add event handlers + loaders + helpers)
- Test: `test/mobile_car_wash_web/live/dashboard_live_test.exs` (add tests)

**Interfaces:**
- Consumes: `RecurringSchedule.:for_customer` read, `RecurringSchedule.:update_preferences` (Task 1), `:activate`/`:deactivate` updates, `Ash.destroy/1`.
- Produces: `mount/3` now also assigns `:schedules` (list of display maps) and `:editing_id` (uuid or nil). Event handlers: `"edit_schedule"`, `"cancel_edit"`, `"save_preferences"`, `"pause_schedule"`, `"resume_schedule"`, `"delete_schedule"`. Display map shape per schedule: `%{id, frequency, preferred_day, preferred_time, active, service_type_name, vehicle_label}`.

- [ ] **Step 1: Write the failing tests**

Add these tests to `test/mobile_car_wash_web/live/dashboard_live_test.exs` (inside the module, after the existing tests). They reuse the `register_and_sign_in/1`, `create_plan/0`, `create_active_subscription/2` helpers. Add this alias near the top of the test module if not present: `alias MobileCarWash.Scheduling.RecurringSchedule`.

```elixir
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
      "id" => other_schedule.id,
      "schedule" => %{"frequency" => "monthly", "preferred_day" => "1", "preferred_time" => "09:00"}
    })

    unchanged = Ash.get!(RecurringSchedule, other_schedule.id)
    assert unchanged.frequency == :weekly
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/mobile_car_wash_web/live/dashboard_live_test.exs`
Expected: FAIL — "Recurring Wash-Days" not in markup; `save_preferences` event not handled.

- [ ] **Step 3: Load schedules in mount**

In `lib/mobile_car_wash_web/live/dashboard_live.ex`, update the success branch of `mount/3` to also load schedules and seed `:editing_id`. Replace the existing success branch:

```elixir
      {subscription, plan, usage} ->
        {:ok,
         socket
         |> assign(
           page_title: "Your Dashboard",
           subscription: subscription,
           plan: plan,
           usage: usage,
           editing_id: nil
         )
         |> load_schedules(customer.id)}
```

Also extend the alias line to pull in the scheduling resources:

```elixir
  alias MobileCarWash.Billing.{Subscription, SubscriptionPlan, SubscriptionUsage}
  alias MobileCarWash.Scheduling.{RecurringSchedule, ServiceType}
  alias MobileCarWash.Fleet.Vehicle
```

- [ ] **Step 4: Add the Panel B markup**

In `render/1`, insert the Panel B block immediately AFTER the closing `</div>` of the Panel A card (still inside the outer `space-y-6` container):

```elixir
      <!-- Panel B: Recurring wash-days -->
      <div class="card bg-base-100 shadow">
        <div class="card-body">
          <div class="flex justify-between items-center mb-2">
            <h2 class="card-title">Recurring Wash-Days</h2>
            <.link navigate={~p"/account/recurring"} class="btn btn-ghost btn-sm">Add</.link>
          </div>

          <p :if={@schedules == []} class="text-base-content/70 py-4">
            No recurring wash-days yet.
            <.link navigate={~p"/account/recurring"} class="link link-primary">Set one up</.link>
            so washes book themselves.
          </p>

          <div :for={schedule <- @schedules} class="border-t border-base-200 py-3 first:border-t-0">
            <div :if={@editing_id != schedule.id}>
              <div class="flex justify-between items-start">
                <div>
                  <p class="font-semibold">{schedule.service_type_name}</p>
                  <p class="text-sm text-base-content/80">
                    {format_frequency(schedule.frequency)} · {format_day(schedule.preferred_day)}s at {format_time(
                      schedule.preferred_time
                    )}
                  </p>
                  <p class="text-xs text-base-content/70">{schedule.vehicle_label}</p>
                </div>
                <span class={["badge", if(schedule.active, do: "badge-success", else: "badge-ghost")]}>
                  {if schedule.active, do: "Active", else: "Paused"}
                </span>
              </div>

              <div class="flex gap-2 mt-2">
                <button class="btn btn-outline btn-xs" phx-click="edit_schedule" phx-value-id={schedule.id}>
                  Edit
                </button>
                <button
                  :if={schedule.active}
                  class="btn btn-outline btn-xs"
                  phx-click="pause_schedule"
                  phx-value-id={schedule.id}
                >
                  Pause
                </button>
                <button
                  :if={!schedule.active}
                  class="btn btn-success btn-xs"
                  phx-click="resume_schedule"
                  phx-value-id={schedule.id}
                >
                  Resume
                </button>
                <button
                  class="btn btn-ghost btn-xs text-error"
                  phx-click="delete_schedule"
                  phx-value-id={schedule.id}
                  data-confirm="Remove this recurring wash-day?"
                >
                  Remove
                </button>
              </div>
            </div>

            <form
              :if={@editing_id == schedule.id}
              id={"edit-schedule-#{schedule.id}"}
              phx-submit="save_preferences"
            >
              <input type="hidden" name="id" value={schedule.id} />
              <div class="grid grid-cols-3 gap-2">
                <select name="schedule[frequency]" class="select select-bordered select-sm">
                  <option value="weekly" selected={schedule.frequency == :weekly}>Every week</option>
                  <option value="biweekly" selected={schedule.frequency == :biweekly}>Every 2 weeks</option>
                  <option value="monthly" selected={schedule.frequency == :monthly}>Monthly</option>
                </select>
                <select name="schedule[preferred_day]" class="select select-bordered select-sm">
                  <option :for={d <- 1..6} value={d} selected={schedule.preferred_day == d}>
                    {format_day(d)}
                  </option>
                </select>
                <input
                  type="time"
                  name="schedule[preferred_time]"
                  class="input input-bordered input-sm"
                  min="08:00"
                  max="17:00"
                  value={Calendar.strftime(schedule.preferred_time, "%H:%M")}
                />
              </div>
              <div class="flex gap-2 mt-2">
                <button type="submit" class="btn btn-primary btn-xs">Save</button>
                <button type="button" class="btn btn-ghost btn-xs" phx-click="cancel_edit">Cancel</button>
              </div>
            </form>
          </div>
        </div>
      </div>
```

- [ ] **Step 5: Add the event handlers**

In `dashboard_live.ex`, add these `handle_event/3` clauses after `mount/3` (before `render/1`):

```elixir
  @impl true
  def handle_event("edit_schedule", %{"id" => id}, socket) do
    {:noreply, assign(socket, editing_id: id)}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, editing_id: nil)}
  end

  def handle_event("save_preferences", %{"id" => id, "schedule" => params}, socket) do
    customer = socket.assigns.current_customer

    attrs = %{
      frequency: String.to_existing_atom(params["frequency"]),
      preferred_day: String.to_integer(params["preferred_day"]),
      preferred_time: parse_time(params["preferred_time"])
    }

    with {:ok, schedule} <- Ash.get(RecurringSchedule, id),
         true <- schedule.customer_id == customer.id,
         {:ok, _} <-
           schedule |> Ash.Changeset.for_update(:update_preferences, attrs) |> Ash.update() do
      {:noreply,
       socket
       |> assign(editing_id: nil)
       |> load_schedules(customer.id)
       |> put_flash(:info, "Schedule updated")}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not update schedule")}
    end
  end

  def handle_event("pause_schedule", %{"id" => id}, socket) do
    customer = socket.assigns.current_customer

    with {:ok, schedule} <- Ash.get(RecurringSchedule, id),
         true <- schedule.customer_id == customer.id,
         {:ok, _} <- schedule |> Ash.Changeset.for_update(:deactivate, %{}) |> Ash.update() do
      {:noreply,
       socket |> load_schedules(customer.id) |> put_flash(:info, "Schedule paused")}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not pause schedule")}
    end
  end

  def handle_event("resume_schedule", %{"id" => id}, socket) do
    customer = socket.assigns.current_customer

    with {:ok, schedule} <- Ash.get(RecurringSchedule, id),
         true <- schedule.customer_id == customer.id,
         {:ok, _} <- schedule |> Ash.Changeset.for_update(:activate, %{}) |> Ash.update() do
      {:noreply,
       socket |> load_schedules(customer.id) |> put_flash(:info, "Schedule resumed")}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not resume schedule")}
    end
  end

  def handle_event("delete_schedule", %{"id" => id}, socket) do
    customer = socket.assigns.current_customer

    with {:ok, schedule} <- Ash.get(RecurringSchedule, id),
         true <- schedule.customer_id == customer.id,
         :ok <- Ash.destroy(schedule) do
      {:noreply,
       socket |> load_schedules(customer.id) |> put_flash(:info, "Schedule removed")}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not remove schedule")}
    end
  end
```

- [ ] **Step 6: Add the loader and format helpers**

In `dashboard_live.ex`, add the `load_schedules/2` loader (in the data-loading section) and the format/parse helpers (in the formatting section):

```elixir
  defp load_schedules(socket, customer_id) do
    schedules =
      RecurringSchedule
      |> Ash.Query.for_read(:for_customer, %{customer_id: customer_id})
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.read!()
      |> Enum.map(fn s ->
        st = Ash.get!(ServiceType, s.service_type_id)
        v = Ash.get!(Vehicle, s.vehicle_id)

        %{
          id: s.id,
          frequency: s.frequency,
          preferred_day: s.preferred_day,
          preferred_time: s.preferred_time,
          active: s.active,
          service_type_name: st.name,
          vehicle_label: "#{v.year || ""} #{v.make} #{v.model}" |> String.trim()
        }
      end)

    assign(socket, schedules: schedules)
  end
```

```elixir
  defp parse_time(value) do
    case Time.from_iso8601("#{value}:00") do
      {:ok, t} -> t
      _ -> ~T[10:00:00]
    end
  end

  defp format_frequency(:weekly), do: "Every week"
  defp format_frequency(:biweekly), do: "Every 2 weeks"
  defp format_frequency(:monthly), do: "Monthly"
  defp format_frequency(f), do: to_string(f)

  defp format_day(1), do: "Monday"
  defp format_day(2), do: "Tuesday"
  defp format_day(3), do: "Wednesday"
  defp format_day(4), do: "Thursday"
  defp format_day(5), do: "Friday"
  defp format_day(6), do: "Saturday"
  defp format_day(7), do: "Sunday"
  defp format_day(_), do: "Unknown"

  defp format_time(time), do: Calendar.strftime(time, "%-I:%M %p")
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `mix test test/mobile_car_wash_web/live/dashboard_live_test.exs`
Expected: PASS (all Task 2 + Task 3 tests).

- [ ] **Step 8: Commit**

```bash
git add lib/mobile_car_wash_web/live/dashboard_live.ex test/mobile_car_wash_web/live/dashboard_live_test.exs
git commit -m "feat(dashboard): add recurring wash-days panel with inline edit and ownership checks"
```

---

## Task 4: Panel C — upcoming washes (read-only)

**Files:**
- Modify: `lib/mobile_car_wash_web/live/dashboard_live.ex` (mount, render, loader)
- Test: `test/mobile_car_wash_web/live/dashboard_live_test.exs` (add tests)

**Interfaces:**
- Consumes: `Appointment.:upcoming` read (status in `[:pending, :confirmed]` and `scheduled_at > now`), `AppointmentAddOn` filtered by appointment.
- Produces: `mount/3` also assigns `:upcoming` (list of display maps). Display map shape: `%{id, scheduled_at, status, price_cents, service_type_name, vehicle_label, add_on_count}`. Read-only this cycle — NO "add services" control (that is Cycle 2).

- [ ] **Step 1: Write the failing tests**

Add to `test/mobile_car_wash_web/live/dashboard_live_test.exs`. Add this alias near the top of the module: `alias MobileCarWash.Scheduling.Appointment`.

```elixir
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/mobile_car_wash_web/live/dashboard_live_test.exs`
Expected: FAIL — "Upcoming Washes" not in markup.

- [ ] **Step 3: Load upcoming washes in mount**

In `dashboard_live.ex`, extend the alias to add `Appointment` and `AppointmentAddOn`:

```elixir
  alias MobileCarWash.Scheduling.{Appointment, AppointmentAddOn, RecurringSchedule, ServiceType}
```

Then chain `load_upcoming/2` onto the mount success branch:

```elixir
      {subscription, plan, usage} ->
        {:ok,
         socket
         |> assign(
           page_title: "Your Dashboard",
           subscription: subscription,
           plan: plan,
           usage: usage,
           editing_id: nil
         )
         |> load_schedules(customer.id)
         |> load_upcoming(customer.id)}
```

- [ ] **Step 4: Add the Panel C markup**

In `render/1`, insert the Panel C block immediately AFTER the closing `</div>` of the Panel B card (still inside the outer `space-y-6` container):

```elixir
      <!-- Panel C: Upcoming washes (read-only) -->
      <div class="card bg-base-100 shadow">
        <div class="card-body">
          <h2 class="card-title mb-2">Upcoming Washes</h2>

          <p :if={@upcoming == []} class="text-base-content/70 py-4">
            No upcoming washes. Your recurring wash-days will book automatically, or
            <.link navigate={~p"/book"} class="link link-primary">book one now</.link>.
          </p>

          <div :for={appt <- @upcoming} class="border-t border-base-200 py-3 first:border-t-0">
            <div class="flex justify-between items-start">
              <div>
                <p class="font-semibold">{appt.service_type_name}</p>
                <p class="text-sm text-base-content/80">
                  {Calendar.strftime(appt.scheduled_at, "%a %b %-d, %-I:%M %p")}
                </p>
                <p class="text-xs text-base-content/70">
                  {appt.vehicle_label}
                  <span :if={appt.add_on_count > 0}>· {appt.add_on_count} add-on(s)</span>
                </p>
              </div>
              <div class="text-right">
                <p class="font-semibold">${div(appt.price_cents, 100)}</p>
                <span class="badge badge-ghost badge-sm">{format_status(appt.status)}</span>
              </div>
            </div>
          </div>
        </div>
      </div>
```

- [ ] **Step 5: Add the loader**

In `dashboard_live.ex`, add `load_upcoming/2` to the data-loading section:

```elixir
  defp load_upcoming(socket, customer_id) do
    upcoming =
      Appointment
      |> Ash.Query.for_read(:upcoming, %{customer_id: customer_id})
      |> Ash.Query.sort(scheduled_at: :asc)
      |> Ash.read!()
      |> Enum.map(fn a ->
        st = Ash.get!(ServiceType, a.service_type_id)
        v = Ash.get!(Vehicle, a.vehicle_id)

        add_on_count =
          AppointmentAddOn
          |> Ash.Query.filter(appointment_id == ^a.id)
          |> Ash.read!()
          |> length()

        %{
          id: a.id,
          scheduled_at: a.scheduled_at,
          status: a.status,
          price_cents: a.price_cents,
          service_type_name: st.name,
          vehicle_label: "#{v.year || ""} #{v.make} #{v.model}" |> String.trim(),
          add_on_count: add_on_count
        }
      end)

    assign(socket, upcoming: upcoming)
  end
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `mix test test/mobile_car_wash_web/live/dashboard_live_test.exs`
Expected: PASS (all dashboard tests).

- [ ] **Step 7: Run the full suite + precommit gate**

Run: `mix precommit`
Expected: compile with no warnings, format clean, full suite green (~1297 + new tests, 0 failures).

- [ ] **Step 8: Commit**

```bash
git add lib/mobile_car_wash_web/live/dashboard_live.ex test/mobile_car_wash_web/live/dashboard_live_test.exs
git commit -m "feat(dashboard): add read-only upcoming washes panel"
```

---

## Cycle Completion

After Task 4, the cycle is feature-complete. Hand off to **superpowers:finishing-a-development-branch**:
- Confirm `mix precommit` is green.
- Update the SDD ledger `.superpowers/sdd/progress.md` (append a "Subscriber Dashboard — Cycle 1" section; mark each task complete with its commit).
- Per project convention: stash the convention files, merge `feature/subscriber-dashboard` into local `main` with `--no-ff`, **do NOT push** (origin is intentionally behind; the user pushes manually), restore the convention files.
- Cycle 2 (add-ons join resource, `AppointmentServices.add/2` + `request_add_services/2`, `StripeClient.charge_off_session/3`, Panel B "manage add-ons" + Panel C "add services" UI, webhook extension, recurring scheduler integration) is a SEPARATE plan written after Cycle 1 merges.

## Self-Review notes (coverage against the spec, Cycle-1 slice)

- **Subscription gate** → Task 2 (redirects non-subscribers to `/subscribe`; corrected target).
- **Panel A subscription summary (read-only + link)** → Task 2.
- **Panel B recurring: inline edit of frequency/day/time** → Task 3 via `:update_preferences` (Task 1); **activate/deactivate/delete** → Task 3; **create affordance** → link to existing `/account/recurring` (reuse, not duplicate). **"Manage add-ons" is intentionally deferred to Cycle 2.**
- **Panel C upcoming washes** → Task 4, read-only (current add-ons shown as a count). **"Add services" is intentionally deferred to Cycle 2.**
- **Ownership enforcement** → Task 3 (`customer_id` check on every mutating handler; forged-id test included).
- **Empty states** → Task 3 (no schedules) + Task 4 (no upcoming).
- **Out of scope this cycle (correctly absent):** `RecurringScheduleAddOn`, `AppointmentServices`, `charge_off_session`, webhook `appointment_addons`, scheduler add-on charging, the 12h one-off edit cutoff (only relevant to the deferred add-services flow). These are Cycle 2.
