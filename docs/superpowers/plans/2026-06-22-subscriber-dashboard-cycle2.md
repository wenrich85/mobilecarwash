# Subscriber Dashboard — Cycle 2 (Add-Services + Off-Session Payment) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let subscribers add à-la-carte services to a recurring schedule (future occurrences) and to a single upcoming wash (one-off), charged off-session on their saved card with a hosted Stripe Checkout fallback.

**Architecture:** A shared pure-attach core (`AppointmentServices.add/2`) is reused by three callers: the interactive one-off orchestration (`request_add_services/2`), the Stripe webhook (`appointment_addons` checkout), and the recurring 6am scheduler. Charging is separated from attachment. Off-session readiness is made reliable by saving the subscriber's default payment method at subscription checkout. The dashboard LiveView (`DashboardLive`) grows Panel-B "Manage add-ons" and Panel-C "Add services" UI on top of the existing Cycle-1 shell.

**Tech Stack:** Elixir, Phoenix LiveView, Ash + AshPostgres, Oban, Swoosh, stripity_stripe (mocked in tests).

## Global Constraints

- **Branch:** `feature/subscriber-dashboard-cycle2` (already created from `main`). Never implement on `main`.
- **Convention files** `config/dev.exs`, `AGENTS.md`, `docs/customer-flows.html` are long-standing uncommitted working-tree edits — never commit them; `git stash push -u <files>` around any branch switch/merge and pop after.
- **Gate:** `mix precommit` (compile `--warnings-as-errors`, `mix deps.unlock --unused`, `mix format`, full `mix test`) must pass with **pristine** output. Baseline before Cycle 2: **1307 tests / 0 failures**.
- **Migrations:** Ash-generated only — `mix ash.codegen <name>` then `mix ecto.migrate`. Cycle 2 adds exactly ONE migration: `recurring_schedule_add_ons` (additive). Verify no unintended drift in the generated migration.
- **Merge:** `--no-ff` into local `main`, **do NOT push** (origin is intentionally behind; the user pushes manually).
- **Ledger:** `.superpowers/sdd/progress.md` — append a "Cycle 2" section; record each task `complete (commit, review clean)`.
- **Add-ons are never covered by a subscription** — always an extra charge, size-scaled by `Pricing.calculate/2`.
- **Off-session amounts and prices are integer cents** everywhere.
- **Tests:** TDD for every backend unit. Oban runs `testing: :inline` in test (jobs execute immediately); the Mailer uses `Swoosh.Adapters.Test`. LiveView tests use `MobileCarWashWeb.ConnCase`, `async: false`, `register_with_password`, POST `/auth/customer/password/sign_in`, `recycle(conn)`, then `live(conn, path)`.

## Scenario control for Stripe mocks (used by Tasks 3–9)

Off-session outcomes are driven **deterministically by the customer's `stripe_customer_id` value** so tests need no global state:

- `stripe_customer_id` starting with `"cus_decline"` → default PM `"pm_decline"` → PaymentIntent declines.
- `stripe_customer_id` starting with `"cus_nopm"` → no default PM → `{:error, :no_payment_method}`.
- any other non-nil `stripe_customer_id` → default PM `"pm_test_default"` → PaymentIntent succeeds.
- `stripe_customer_id == nil` → `{:error, :no_payment_method}` (never calls Stripe).

## File Structure

**New files:**
- `lib/mobile_car_wash/scheduling/appointment_services.ex` — shared attach core (`add/2`), interactive orchestration (`request_add_services/2`), webhook completion (`complete_addon_checkout/1`).
- `lib/mobile_car_wash/scheduling/recurring_schedule_add_on.ex` — Ash join resource.
- `lib/mobile_car_wash/notifications/addon_charge_failed_worker.ex` — Oban worker for the recurring decline notification.
- `test/support/stripe_customer_mock.ex` — mock for `Stripe.Customer.retrieve/1`.
- Migration `priv/repo/migrations/*_add_recurring_schedule_add_ons.exs` (generated).
- Test files alongside each unit (see tasks).

**Modified files:**
- `lib/mobile_car_wash/billing/stripe_client.ex` — `charge_off_session/3`, `create_addon_checkout/5`, `save_default_payment_method` on subscription checkout, `customer_module/0`.
- `lib/mobile_car_wash/scheduling/recurring_schedule.ex` — `has_many :recurring_schedule_add_ons` + `replace_add_ons/2` helper (in `AppointmentServices` or a small module function — see Task 2).
- `lib/mobile_car_wash/scheduling.ex` — register `RecurringScheduleAddOn`.
- `lib/mobile_car_wash/scheduling/recurring_appointment_scheduler.ex` — charge + attach add-ons after base wash.
- `lib/mobile_car_wash_web/controllers/stripe_webhook_controller.ex` — `appointment_addons` branch.
- `lib/mobile_car_wash_web/live/dashboard_live.ex` — Panel-B + Panel-C add-on UI.
- `lib/mobile_car_wash/notifications/email.ex` — `addon_charge_failed/2` template.
- `test/support/stripe_payment_intent_mock.ex` — off-session success/decline branches.
- `config/test.exs` — register `:stripe_customer_module`.

---

## Task 1: `AppointmentServices.add/2` — shared pure-attach core

The reusable, charge-free attach path. Loads active add-ons by id, creates size-scaled `AppointmentAddOn` rows (identical math to the booking path), bumps `appointment.price_cents` by the delta. Returns `{:ok, appointment}` with the updated price.

**Files:**
- Create: `lib/mobile_car_wash/scheduling/appointment_services.ex`
- Test: `test/mobile_car_wash/scheduling/appointment_services_add_test.exs`

**Interfaces:**
- Consumes: `MobileCarWash.Billing.Pricing.calculate/2`, `Pricing.addons_total_cents/2`; `MobileCarWash.Scheduling.{AddOn, AppointmentAddOn, Appointment}`; `MobileCarWash.Fleet.Vehicle`; `Appointment` default `:update` action (accepts `price_cents`).
- Produces: `AppointmentServices.add(appointment, add_on_ids) :: {:ok, %Appointment{}}`. `add_on_ids` is a list of uuid strings (possibly `[]` or `nil`). With no resolvable active add-ons it is a no-op returning `{:ok, appointment}` unchanged.

- [ ] **Step 1: Write the failing test**

```elixir
# test/mobile_car_wash/scheduling/appointment_services_add_test.exs
defmodule MobileCarWash.Scheduling.AppointmentServicesAddTest do
  use MobileCarWash.DataCase, async: false

  alias MobileCarWash.Scheduling.{AppointmentServices, AppointmentAddOn, AddOn, Appointment}

  require Ash.Query

  defp fixtures(vehicle_size) do
    {:ok, customer} =
      MobileCarWash.Accounts.Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "svc-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Svc Test",
        phone: "+15125550000"
      })
      |> Ash.create()

    {:ok, service_type} =
      MobileCarWash.Scheduling.ServiceType
      |> Ash.Changeset.for_create(:create, %{
        name: "Basic Wash",
        slug: "svc-#{System.unique_integer([:positive])}",
        base_price_cents: 5_000,
        duration_minutes: 45
      })
      |> Ash.create()

    {:ok, vehicle} =
      MobileCarWash.Fleet.Vehicle
      |> Ash.Changeset.for_create(:create, %{make: "Toyota", model: "Camry", year: 2021})
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.Changeset.force_change_attribute(:size, vehicle_size)
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

    {:ok, appointment} =
      Appointment
      |> Ash.Changeset.for_create(:book, %{
        scheduled_at: DateTime.add(DateTime.utc_now(), 3 * 24 * 3600),
        price_cents: 5_000,
        duration_minutes: 45,
        customer_id: customer.id,
        vehicle_id: vehicle.id,
        address_id: address.id,
        service_type_id: service_type.id
      })
      |> Ash.create()

    {:ok, addon} =
      AddOn
      |> Ash.Changeset.for_create(:create, %{name: "Wax", slug: "wax-#{System.unique_integer([:positive])}", price_cents: 2_000})
      |> Ash.create()

    %{appointment: appointment, addon: addon}
  end

  test "attaches a size-scaled add-on row and bumps the appointment price (suv_van 1.2x)" do
    %{appointment: appt, addon: addon} = fixtures(:suv_van)

    {:ok, updated} = AppointmentServices.add(appt, [addon.id])

    # 2000 * 1.2 = 2400
    assert updated.price_cents == 5_000 + 2_400

    rows =
      AppointmentAddOn
      |> Ash.Query.filter(appointment_id == ^appt.id)
      |> Ash.read!()

    assert [%{price_cents: 2_400}] = rows
  end

  test "is a no-op when add_on_ids is empty" do
    %{appointment: appt} = fixtures(:car)
    {:ok, updated} = AppointmentServices.add(appt, [])
    assert updated.price_cents == 5_000
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/mobile_car_wash/scheduling/appointment_services_add_test.exs`
Expected: FAIL — `AppointmentServices` is undefined / `function add/2 is undefined`.

- [ ] **Step 3: Write minimal implementation**

```elixir
# lib/mobile_car_wash/scheduling/appointment_services.ex
defmodule MobileCarWash.Scheduling.AppointmentServices do
  @moduledoc """
  Add-on services for appointments. `add/2` is the shared, charge-free
  attach core reused by the interactive one-off flow, the Stripe webhook,
  and the recurring scheduler. Charging lives in `request_add_services/2`
  and `complete_addon_checkout/1`.
  """

  alias MobileCarWash.Billing.Pricing
  alias MobileCarWash.Scheduling.{AddOn, Appointment, AppointmentAddOn}
  alias MobileCarWash.Fleet.Vehicle

  require Ash.Query

  @doc """
  Attaches the given add-ons to `appointment`, capturing size-scaled prices
  and bumping the appointment's `price_cents` by the delta. No payment.
  Returns `{:ok, appointment}` (unchanged if no active add-ons resolve).
  """
  def add(appointment, add_on_ids) do
    case load_active_add_ons(add_on_ids) do
      [] ->
        {:ok, appointment}

      add_ons ->
        vehicle = Ash.get!(Vehicle, appointment.vehicle_id, authorize?: false)

        Enum.each(add_ons, fn add_on ->
          AppointmentAddOn
          |> Ash.Changeset.for_create(:create, %{
            appointment_id: appointment.id,
            add_on_id: add_on.id,
            price_cents: Pricing.calculate(add_on.price_cents, vehicle.size)
          })
          |> Ash.create!()
        end)

        delta = Pricing.addons_total_cents(add_ons, vehicle.size)

        appointment
        |> Ash.Changeset.for_update(:update, %{price_cents: appointment.price_cents + delta})
        |> Ash.update()
    end
  end

  @doc false
  def load_active_add_ons(nil), do: []
  def load_active_add_ons([]), do: []

  def load_active_add_ons(ids) do
    AddOn
    |> Ash.Query.filter(id in ^ids and active == true)
    |> Ash.read!()
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/mobile_car_wash/scheduling/appointment_services_add_test.exs`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/mobile_car_wash/scheduling/appointment_services.ex test/mobile_car_wash/scheduling/appointment_services_add_test.exs
git commit -m "feat(scheduling): add AppointmentServices.add/2 shared add-on attach core"
```

---

## Task 2: `RecurringScheduleAddOn` join resource + migration + replace-set

A join row linking a recurring schedule to an add-on, so future auto-generated occurrences inherit the schedule's add-ons. Includes a "replace the schedule's add-on set" operation backing the Panel-B toggles.

**Files:**
- Create: `lib/mobile_car_wash/scheduling/recurring_schedule_add_on.ex`
- Modify: `lib/mobile_car_wash/scheduling/recurring_schedule.ex` (add `has_many`)
- Modify: `lib/mobile_car_wash/scheduling.ex` (register resource)
- Modify: `lib/mobile_car_wash/scheduling/appointment_services.ex` (add `replace_schedule_add_ons/2`, `schedule_add_on_ids/1`, `schedule_add_ons/1`)
- Generated: migration `*_add_recurring_schedule_add_ons.exs`
- Test: `test/mobile_car_wash/scheduling/recurring_schedule_add_on_test.exs`

**Interfaces:**
- Consumes: `MobileCarWash.Scheduling.{RecurringSchedule, AddOn}`; `AppointmentServices.load_active_add_ons/1` (Task 1).
- Produces:
  - `RecurringScheduleAddOn` resource (`belongs_to :recurring_schedule`, `belongs_to :add_on`, `:create` accepts `recurring_schedule_id`/`add_on_id`).
  - `AppointmentServices.replace_schedule_add_ons(schedule_id, add_on_ids) :: :ok` — deletes existing rows for the schedule, creates the new set (skips ids that aren't active add-ons).
  - `AppointmentServices.schedule_add_on_ids(schedule_id) :: [uuid]` — current set.
  - `AppointmentServices.schedule_add_ons(schedule_id) :: [%AddOn{}]` — loaded active add-ons for the schedule.

- [ ] **Step 1: Write the failing test**

```elixir
# test/mobile_car_wash/scheduling/recurring_schedule_add_on_test.exs
defmodule MobileCarWash.Scheduling.RecurringScheduleAddOnTest do
  use MobileCarWash.DataCase, async: false

  alias MobileCarWash.Scheduling.{AppointmentServices, AddOn, RecurringSchedule}

  defp schedule_fixture do
    {:ok, customer} =
      MobileCarWash.Accounts.Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "rsa-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "RSA",
        phone: "+15125550000"
      })
      |> Ash.create()

    {:ok, service_type} =
      MobileCarWash.Scheduling.ServiceType
      |> Ash.Changeset.for_create(:create, %{name: "Basic", slug: "rsa-#{System.unique_integer([:positive])}", base_price_cents: 5_000, duration_minutes: 45})
      |> Ash.create()

    {:ok, vehicle} =
      MobileCarWash.Fleet.Vehicle
      |> Ash.Changeset.for_create(:create, %{make: "Toyota", model: "Camry", year: 2021})
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create()

    {:ok, address} =
      MobileCarWash.Fleet.Address
      |> Ash.Changeset.for_create(:create, %{street: "1 Main", city: "SA", state: "TX", zip: "78259"})
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create()

    {:ok, schedule} =
      RecurringSchedule
      |> Ash.Changeset.for_create(:create, %{frequency: :weekly, preferred_day: 3, preferred_time: ~T[10:00:00]})
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.Changeset.force_change_attribute(:vehicle_id, vehicle.id)
      |> Ash.Changeset.force_change_attribute(:address_id, address.id)
      |> Ash.Changeset.force_change_attribute(:service_type_id, service_type.id)
      |> Ash.create()

    schedule
  end

  defp addon do
    {:ok, a} =
      AddOn
      |> Ash.Changeset.for_create(:create, %{name: "Wax", slug: "wax-#{System.unique_integer([:positive])}", price_cents: 2_000})
      |> Ash.create()

    a
  end

  test "replace_schedule_add_ons sets, then replaces, the schedule's add-on set" do
    schedule = schedule_fixture()
    a1 = addon()
    a2 = addon()

    :ok = AppointmentServices.replace_schedule_add_ons(schedule.id, [a1.id, a2.id])
    assert Enum.sort(AppointmentServices.schedule_add_on_ids(schedule.id)) == Enum.sort([a1.id, a2.id])

    :ok = AppointmentServices.replace_schedule_add_ons(schedule.id, [a1.id])
    assert AppointmentServices.schedule_add_on_ids(schedule.id) == [a1.id]

    :ok = AppointmentServices.replace_schedule_add_ons(schedule.id, [])
    assert AppointmentServices.schedule_add_on_ids(schedule.id) == []
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/mobile_car_wash/scheduling/recurring_schedule_add_on_test.exs`
Expected: FAIL — `RecurringScheduleAddOn`/`replace_schedule_add_ons` undefined.

- [ ] **Step 3: Create the join resource**

```elixir
# lib/mobile_car_wash/scheduling/recurring_schedule_add_on.ex
defmodule MobileCarWash.Scheduling.RecurringScheduleAddOn do
  @moduledoc """
  Join row linking a recurring schedule to an add-on. Future auto-generated
  occurrences inherit the schedule's add-on set (charged off-session per
  occurrence by the scheduler).
  """
  use Ash.Resource,
    otp_app: :mobile_car_wash,
    domain: MobileCarWash.Scheduling,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("recurring_schedule_add_ons")
    repo(MobileCarWash.Repo)
  end

  attributes do
    uuid_primary_key(:id)
    create_timestamp(:inserted_at)
  end

  relationships do
    belongs_to :recurring_schedule, MobileCarWash.Scheduling.RecurringSchedule do
      allow_nil?(false)
    end

    belongs_to :add_on, MobileCarWash.Scheduling.AddOn do
      allow_nil?(false)
    end
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      primary?(true)
      accept([:recurring_schedule_id, :add_on_id])
    end

    read :for_schedule do
      argument(:recurring_schedule_id, :uuid, allow_nil?: false)
      filter(expr(recurring_schedule_id == ^arg(:recurring_schedule_id)))
    end
  end
end
```

- [ ] **Step 4: Add the `has_many` to RecurringSchedule**

In `lib/mobile_car_wash/scheduling/recurring_schedule.ex`, inside the `relationships do` block, after the existing `belongs_to` lines, add:

```elixir
    has_many :recurring_schedule_add_ons, MobileCarWash.Scheduling.RecurringScheduleAddOn
```

- [ ] **Step 5: Register the resource in the domain**

In `lib/mobile_car_wash/scheduling.ex`, inside `resources do`, after `resource(MobileCarWash.Scheduling.RecurringSchedule)`, add:

```elixir
    resource(MobileCarWash.Scheduling.RecurringScheduleAddOn)
```

- [ ] **Step 6: Add the replace-set helpers to AppointmentServices**

Append to `lib/mobile_car_wash/scheduling/appointment_services.ex` (inside the module, and add `RecurringScheduleAddOn` to the alias list):

```elixir
  # add RecurringScheduleAddOn to the existing alias:
  # alias MobileCarWash.Scheduling.{AddOn, Appointment, AppointmentAddOn, RecurringScheduleAddOn}

  @doc """
  Replaces a recurring schedule's add-on set: deletes existing join rows,
  then creates one per active add-on id. Affects FUTURE occurrences only.
  """
  def replace_schedule_add_ons(schedule_id, add_on_ids) do
    RecurringScheduleAddOn
    |> Ash.Query.for_read(:for_schedule, %{recurring_schedule_id: schedule_id})
    |> Ash.read!()
    |> Enum.each(&Ash.destroy!/1)

    add_on_ids
    |> load_active_add_ons()
    |> Enum.each(fn add_on ->
      RecurringScheduleAddOn
      |> Ash.Changeset.for_create(:create, %{recurring_schedule_id: schedule_id, add_on_id: add_on.id})
      |> Ash.create!()
    end)

    :ok
  end

  @doc "Current add-on ids attached to a recurring schedule."
  def schedule_add_on_ids(schedule_id) do
    RecurringScheduleAddOn
    |> Ash.Query.for_read(:for_schedule, %{recurring_schedule_id: schedule_id})
    |> Ash.read!()
    |> Enum.map(& &1.add_on_id)
  end

  @doc "Loaded active AddOn records attached to a recurring schedule."
  def schedule_add_ons(schedule_id) do
    schedule_id
    |> schedule_add_on_ids()
    |> load_active_add_ons()
  end
```

- [ ] **Step 7: Generate and run the migration**

Run:
```bash
mix ash.codegen add_recurring_schedule_add_ons
mix ecto.migrate
```
Open the generated `priv/repo/migrations/*_add_recurring_schedule_add_ons.exs` and confirm it ONLY creates the `recurring_schedule_add_ons` table (id, recurring_schedule_id FK, add_on_id FK, inserted_at) with no unrelated drift. If it contains unrelated changes, stop and investigate before continuing.

- [ ] **Step 8: Run the test to verify it passes**

Run: `mix test test/mobile_car_wash/scheduling/recurring_schedule_add_on_test.exs`
Expected: PASS (1 test).

- [ ] **Step 9: Commit**

```bash
git add lib/mobile_car_wash/scheduling/recurring_schedule_add_on.ex \
        lib/mobile_car_wash/scheduling/recurring_schedule.ex \
        lib/mobile_car_wash/scheduling.ex \
        lib/mobile_car_wash/scheduling/appointment_services.ex \
        priv/repo/migrations/*_add_recurring_schedule_add_ons.exs \
        priv/resource_snapshots \
        test/mobile_car_wash/scheduling/recurring_schedule_add_on_test.exs
git commit -m "feat(scheduling): add RecurringScheduleAddOn join + replace-set ops"
```
(If `priv/resource_snapshots` doesn't exist in this repo, omit it from the `git add`.)

---

## Task 3: Save the subscriber's default payment method at subscription checkout

This is the user's "add SetupIntent now" decision, implemented with the **subscription-mode-correct primitive**: `subscription_data.payment_settings.save_default_payment_method = "on_subscription"`. In subscription mode this reliably sets the customer's `invoice_settings.default_payment_method` after the first invoice — a standalone SetupIntent is redundant in this mode. This makes off-session charging (Task 4) reliably find a card instead of routinely falling back to Checkout.

**Files:**
- Modify: `lib/mobile_car_wash/billing/stripe_client.ex` (`create_subscription_checkout/3`)
- Test: `test/mobile_car_wash/billing/stripe_client_subscription_checkout_test.exs`

**Interfaces:**
- Consumes: the existing `:stripe_checkout_module` mock which records `{:create, id, params}` in ETS and exposes `calls/0`.
- Produces: `create_subscription_checkout/3` now includes `subscription_data: %{payment_settings: %{save_default_payment_method: "on_subscription"}}` in the session params.

- [ ] **Step 1: Write the failing test**

```elixir
# test/mobile_car_wash/billing/stripe_client_subscription_checkout_test.exs
defmodule MobileCarWash.Billing.StripeClientSubscriptionCheckoutTest do
  use ExUnit.Case, async: false

  alias MobileCarWash.Billing.{StripeClient, StripeCheckoutSessionMock}

  setup do
    StripeCheckoutSessionMock.init()
    :ok
  end

  test "subscription checkout saves the default payment method for off-session reuse" do
    plan = %{id: Ecto.UUID.generate(), slug: "standard", stripe_price_id: "price_test_123"}

    {:ok, _session} = StripeClient.create_subscription_checkout(plan, "buyer@test.com")

    [{:create, _id, params}] = StripeCheckoutSessionMock.calls()

    assert params.subscription_data == %{
             payment_settings: %{save_default_payment_method: "on_subscription"}
           }
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/mobile_car_wash/billing/stripe_client_subscription_checkout_test.exs`
Expected: FAIL — `params.subscription_data` is missing (KeyError or nil mismatch).

- [ ] **Step 3: Add the param**

In `lib/mobile_car_wash/billing/stripe_client.ex`, in `create_subscription_checkout/3`, extend the initial `params` map (the one with `mode: "subscription"`) to include:

```elixir
    params = %{
      mode: "subscription",
      line_items: [%{price: plan.stripe_price_id, quantity: 1}],
      metadata: %{plan_id: plan.id, plan_slug: plan.slug},
      subscription_data: %{payment_settings: %{save_default_payment_method: "on_subscription"}},
      success_url: "#{base_url}/subscribe/success?session_id={CHECKOUT_SESSION_ID}",
      cancel_url: "#{base_url}/subscribe/cancel"
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/mobile_car_wash/billing/stripe_client_subscription_checkout_test.exs`
Expected: PASS.

- [ ] **Step 5: Run the existing subscription-checkout tests for regressions**

Run: `mix test test/mobile_car_wash_web/live/booking_subscription_price_test.exs`
Expected: PASS (no behavior change beyond the added param).

- [ ] **Step 6: Commit**

```bash
git add lib/mobile_car_wash/billing/stripe_client.ex test/mobile_car_wash/billing/stripe_client_subscription_checkout_test.exs
git commit -m "feat(billing): save default payment method on subscription checkout for off-session reuse"
```

---

## Task 4: `StripeClient.charge_off_session/3` + customer mock + payment-intent mock extension

Off-session PaymentIntent on the subscriber's saved card. Reads the customer's default PM from Stripe, then confirms a PaymentIntent. Returns `{:ok, intent}` on `succeeded`, else `{:error, reason}` (`:card_declined`, `:no_payment_method`, …).

**Files:**
- Modify: `lib/mobile_car_wash/billing/stripe_client.ex` (`charge_off_session/3`, `customer_module/0`)
- Create: `test/support/stripe_customer_mock.ex`
- Modify: `test/support/stripe_payment_intent_mock.ex` (off-session branches)
- Modify: `config/test.exs` (register `:stripe_customer_module`)
- Test: `test/mobile_car_wash/billing/charge_off_session_test.exs`

**Interfaces:**
- Consumes: `payment_intent_module/0` (existing), new `customer_module/0`.
- Produces: `StripeClient.charge_off_session(stripe_customer_id, amount_cents, metadata \\ %{}) :: {:ok, map} | {:error, atom | tuple}`. A `nil` customer id short-circuits to `{:error, :no_payment_method}`.

- [ ] **Step 1: Create the Stripe customer mock**

```elixir
# test/support/stripe_customer_mock.ex
defmodule MobileCarWash.Billing.StripeCustomerMock do
  @moduledoc """
  Test mock for `Stripe.Customer.retrieve/1`. The customer id encodes the
  scenario so tests stay deterministic without global state:
    "cus_decline..." -> default PM "pm_decline" (intent will decline)
    "cus_nopm..."    -> no default PM
    anything else    -> default PM "pm_test_default" (intent will succeed)
  """
  def retrieve("cus_nopm" <> _ = id),
    do: {:ok, %{id: id, invoice_settings: %{default_payment_method: nil}}}

  def retrieve("cus_decline" <> _ = id),
    do: {:ok, %{id: id, invoice_settings: %{default_payment_method: "pm_decline"}}}

  def retrieve(id),
    do: {:ok, %{id: id, invoice_settings: %{default_payment_method: "pm_test_default"}}}
end
```

- [ ] **Step 2: Register the mock in test config**

In `config/test.exs`, after the existing Stripe mock config block, add:

```elixir
config :mobile_car_wash, :stripe_customer_module, MobileCarWash.Billing.StripeCustomerMock
```

- [ ] **Step 3: Extend the payment-intent mock for off-session branches**

In `test/support/stripe_payment_intent_mock.ex`, replace the single `create/2` with off-session-aware clauses (keep the existing non-off-session behavior as the fallback clause):

```elixir
  def create(%{off_session: true, payment_method: "pm_decline"}, _opts) do
    {:error,
     %Stripe.Error{
       source: :stripe,
       code: :card_error,
       message: "Your card was declined.",
       extra: %{card_code: :card_declined, decline_code: "generic_decline"}
     }}
  end

  def create(%{off_session: true} = params, _opts) do
    ensure_table()
    id = "pi_test_#{System.unique_integer([:positive])}"
    :ets.insert(@table, {:create, id, params})
    {:ok, %{id: id, status: "succeeded", amount: params[:amount], client_secret: "#{id}_secret_test"}}
  end

  def create(params, _opts) do
    ensure_table()
    id = "pi_test_#{System.unique_integer([:positive])}"
    client_secret = "#{id}_secret_test"
    :ets.insert(@table, {:create, id, params})
    {:ok, %{id: id, client_secret: client_secret, amount: params[:amount]}}
  end
```
Note: the default `_opts \\ []` belongs only on the first clause head; since multiple clauses now exist, give the first clause an explicit `_opts \\ []` default and the others a plain `_opts` param (Elixir requires the default on the first clause only). If the compiler warns, move the default to a separate zero-body clause head: `def create(params, opts \\ [])`.

- [ ] **Step 4: Write the failing test**

```elixir
# test/mobile_car_wash/billing/charge_off_session_test.exs
defmodule MobileCarWash.Billing.ChargeOffSessionTest do
  use ExUnit.Case, async: false

  alias MobileCarWash.Billing.StripeClient

  test "succeeds when the customer has a default payment method" do
    assert {:ok, %{status: "succeeded", amount: 2_400}} =
             StripeClient.charge_off_session("cus_test_123", 2_400, %{kind: "appointment_addons"})
  end

  test "returns :card_declined when the saved card declines" do
    assert {:error, :card_declined} =
             StripeClient.charge_off_session("cus_decline_123", 2_400)
  end

  test "returns :no_payment_method when the customer has none" do
    assert {:error, :no_payment_method} =
             StripeClient.charge_off_session("cus_nopm_123", 2_400)
  end

  test "returns :no_payment_method for a nil customer id" do
    assert {:error, :no_payment_method} = StripeClient.charge_off_session(nil, 2_400)
  end
end
```

- [ ] **Step 5: Run test to verify it fails**

Run: `mix test test/mobile_car_wash/billing/charge_off_session_test.exs`
Expected: FAIL — `charge_off_session/3` undefined.

- [ ] **Step 6: Implement `charge_off_session/3`**

In `lib/mobile_car_wash/billing/stripe_client.ex`, add the public function and helpers (and a `customer_module/0` alongside the other `*_module` privates):

```elixir
  @doc """
  Charges the customer's saved default card off-session for `amount_cents`.
  Returns `{:ok, intent}` on success, else `{:error, reason}` where reason is
  `:no_payment_method`, `:card_declined`, `{:unexpected_status, status}`, or a
  passed-through Stripe error code.
  """
  def charge_off_session(stripe_customer_id, amount_cents, metadata \\ %{})

  def charge_off_session(nil, _amount_cents, _metadata), do: {:error, :no_payment_method}

  def charge_off_session(stripe_customer_id, amount_cents, metadata) do
    with {:ok, payment_method_id} <- default_payment_method(stripe_customer_id),
         {:ok, intent} <-
           confirm_off_session_intent(stripe_customer_id, payment_method_id, amount_cents, metadata) do
      {:ok, intent}
    end
  end

  defp default_payment_method(stripe_customer_id) do
    case customer_module().retrieve(stripe_customer_id) do
      {:ok, %{invoice_settings: %{default_payment_method: pm}}} when is_binary(pm) -> {:ok, pm}
      {:ok, _} -> {:error, :no_payment_method}
      {:error, reason} -> {:error, normalize_stripe_error(reason)}
    end
  end

  defp confirm_off_session_intent(customer_id, payment_method_id, amount_cents, metadata) do
    params = %{
      amount: amount_cents,
      currency: "usd",
      customer: customer_id,
      payment_method: payment_method_id,
      off_session: true,
      confirm: true,
      metadata: metadata
    }

    case payment_intent_module().create(params) do
      {:ok, %{status: "succeeded"} = intent} -> {:ok, intent}
      {:ok, %{status: status}} -> {:error, {:unexpected_status, status}}
      {:error, reason} -> {:error, normalize_stripe_error(reason)}
    end
  end

  defp normalize_stripe_error(%Stripe.Error{extra: %{card_code: code}}), do: code
  defp normalize_stripe_error(%Stripe.Error{code: code}), do: code
  defp normalize_stripe_error(other), do: other

  defp customer_module do
    Application.get_env(:mobile_car_wash, :stripe_customer_module, Stripe.Customer)
  end
```

- [ ] **Step 7: Run test to verify it passes**

Run: `mix test test/mobile_car_wash/billing/charge_off_session_test.exs`
Expected: PASS (4 tests).

- [ ] **Step 8: Run the broader billing/booking suites for regressions from the mock change**

Run: `mix test test/mobile_car_wash/billing test/mobile_car_wash/scheduling`
Expected: PASS (the new payment-intent mock clauses preserve old behavior for non-off-session calls).

- [ ] **Step 9: Commit**

```bash
git add lib/mobile_car_wash/billing/stripe_client.ex \
        test/support/stripe_customer_mock.ex \
        test/support/stripe_payment_intent_mock.ex \
        config/test.exs \
        test/mobile_car_wash/billing/charge_off_session_test.exs
git commit -m "feat(billing): add StripeClient.charge_off_session/3 with default-PM lookup"
```

---

## Task 5: `request_add_services/2` — interactive one-off orchestration

Validate editability (status + 12h cutoff), compute the size-scaled delta, charge off-session. On success: attach via `add/2` + record a succeeded `Payment` + enqueue receipt. On failure: create a Checkout session for the delta tagged `kind: "appointment_addons"` and return `{:ok, checkout_url}`, attaching NOTHING until the webhook confirms.

**Files:**
- Modify: `lib/mobile_car_wash/billing/stripe_client.ex` (`create_addon_checkout/5`)
- Modify: `lib/mobile_car_wash/scheduling/appointment_services.ex` (`request_add_services/2`, `editable?/1`, payment helpers)
- Test: `test/mobile_car_wash/scheduling/request_add_services_test.exs`

**Interfaces:**
- Consumes: `StripeClient.charge_off_session/3` (Task 4), `StripeClient.create_addon_checkout/5` (this task), `AppointmentServices.add/2` (Task 1), `Pricing.addons_total_cents/2`, `Payment` `:create`/`:complete`/`:update`, `PaymentReceiptWorker`.
- Produces:
  - `AppointmentServices.request_add_services(appointment, add_on_ids) :: {:ok, :charged} | {:ok, checkout_url :: String.t()} | {:error, :not_editable} | {:error, :no_add_ons}`. **Caller must have verified ownership** (the appointment belongs to the acting customer) — this function enforces the status + 12h editability guard server-side.
  - `AppointmentServices.editable?(appointment) :: boolean` — `status in [:pending, :confirmed]` and `scheduled_at` is more than 12h out.
  - `StripeClient.create_addon_checkout(appointment, add_ons, add_on_ids, amount_cents, customer_email) :: {:ok, session} | {:error, reason}`.

- [ ] **Step 1: Write the failing test**

```elixir
# test/mobile_car_wash/scheduling/request_add_services_test.exs
defmodule MobileCarWash.Scheduling.RequestAddServicesTest do
  use MobileCarWash.DataCase, async: false

  import Swoosh.TestAssertions

  alias MobileCarWash.Scheduling.{AppointmentServices, AppointmentAddOn, AddOn, Appointment}
  alias MobileCarWash.Billing.Payment

  require Ash.Query

  # hours_out: how far in the future to schedule; cus: stripe_customer_id scenario
  defp setup_appt(hours_out, cus) do
    {:ok, customer} =
      MobileCarWash.Accounts.Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "ras-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "RAS",
        phone: "+15125550000"
      })
      |> Ash.Changeset.force_change_attribute(:stripe_customer_id, cus)
      |> Ash.create()

    {:ok, service_type} =
      MobileCarWash.Scheduling.ServiceType
      |> Ash.Changeset.for_create(:create, %{name: "Basic", slug: "ras-#{System.unique_integer([:positive])}", base_price_cents: 5_000, duration_minutes: 45})
      |> Ash.create()

    {:ok, vehicle} =
      MobileCarWash.Fleet.Vehicle
      |> Ash.Changeset.for_create(:create, %{make: "Toyota", model: "Camry", year: 2021})
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.Changeset.force_change_attribute(:size, :car)
      |> Ash.create()

    {:ok, address} =
      MobileCarWash.Fleet.Address
      |> Ash.Changeset.for_create(:create, %{street: "1 Main", city: "SA", state: "TX", zip: "78259"})
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create()

    {:ok, appointment} =
      Appointment
      |> Ash.Changeset.for_create(:book, %{
        scheduled_at: DateTime.add(DateTime.utc_now(), hours_out * 3600),
        price_cents: 5_000,
        duration_minutes: 45,
        customer_id: customer.id,
        vehicle_id: vehicle.id,
        address_id: address.id,
        service_type_id: service_type.id
      })
      |> Ash.create()

    {:ok, addon} =
      AddOn
      |> Ash.Changeset.for_create(:create, %{name: "Wax", slug: "wax-#{System.unique_integer([:positive])}", price_cents: 2_000})
      |> Ash.create()

    %{appointment: appointment, addon: addon}
  end

  test "rejects an appointment inside the 12h cutoff" do
    %{appointment: appt, addon: addon} = setup_appt(6, "cus_test_1")
    assert {:error, :not_editable} = AppointmentServices.request_add_services(appt, [addon.id])
  end

  test "card success: attaches add-ons, bumps price, records a succeeded payment + receipt" do
    %{appointment: appt, addon: addon} = setup_appt(48, "cus_test_2")

    assert {:ok, :charged} = AppointmentServices.request_add_services(appt, [addon.id])

    updated = Ash.get!(Appointment, appt.id)
    assert updated.price_cents == 7_000

    [row] = AppointmentAddOn |> Ash.Query.filter(appointment_id == ^appt.id) |> Ash.read!()
    assert row.price_cents == 2_000

    [payment] = Payment |> Ash.Query.filter(appointment_id == ^appt.id) |> Ash.read!()
    assert payment.status == :succeeded
    assert payment.amount_cents == 2_000

    assert_email_sent(subject: "Payment Receipt — $20.00")
  end

  test "card failure: returns a checkout_url and attaches nothing" do
    %{appointment: appt, addon: addon} = setup_appt(48, "cus_decline_3")

    assert {:ok, "https://checkout.stripe.com/pay/" <> _} =
             AppointmentServices.request_add_services(appt, [addon.id])

    assert [] = AppointmentAddOn |> Ash.Query.filter(appointment_id == ^appt.id) |> Ash.read!()
    assert Ash.get!(Appointment, appt.id).price_cents == 5_000
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/mobile_car_wash/scheduling/request_add_services_test.exs`
Expected: FAIL — `request_add_services/2` undefined.

- [ ] **Step 3: Add `create_addon_checkout/5` to StripeClient**

In `lib/mobile_car_wash/billing/stripe_client.ex`:

```elixir
  @doc """
  Creates a one-time (payment-mode) Checkout session for an add-on top-up on
  an existing appointment. Metadata carries `kind`/`appointment_id`/`add_on_ids`
  so the webhook can attach the add-ons after payment.
  """
  def create_addon_checkout(appointment, add_ons, add_on_ids, amount_cents, customer_email) do
    base_url = Application.get_env(:mobile_car_wash, :base_url, "http://localhost:4000")
    names = add_ons |> Enum.map(& &1.name) |> Enum.join(", ")

    params = %{
      mode: "payment",
      customer_email: customer_email,
      line_items: [
        %{
          price_data: %{
            currency: "usd",
            product_data: %{name: "Add-on services", description: names},
            unit_amount: amount_cents
          },
          quantity: 1
        }
      ],
      metadata: %{
        kind: "appointment_addons",
        appointment_id: appointment.id,
        add_on_ids: Enum.join(add_on_ids, ",")
      },
      success_url: "#{base_url}/dashboard?addons=success",
      cancel_url: "#{base_url}/dashboard?addons=cancel"
    }

    stripe_module().create(params)
  end
```

- [ ] **Step 4: Implement `request_add_services/2` + helpers in AppointmentServices**

Add to `lib/mobile_car_wash/scheduling/appointment_services.ex` (add `Payment` + `StripeClient` to aliases: `alias MobileCarWash.Billing.{Payment, Pricing, StripeClient}`):

```elixir
  @cutoff_seconds 12 * 3600

  @doc """
  Interactive one-off add-services flow. Caller must own the appointment.
  Charges off-session; on success attaches + records payment, on failure
  returns a hosted-checkout URL and attaches nothing.
  """
  def request_add_services(appointment, add_on_ids) do
    with true <- editable?(appointment) || {:error, :not_editable},
         add_ons when add_ons != [] <- load_active_add_ons(add_on_ids) do
      vehicle = Ash.get!(Vehicle, appointment.vehicle_id, authorize?: false)
      customer = Ash.get!(MobileCarWash.Accounts.Customer, appointment.customer_id, authorize?: false)
      amount_cents = Pricing.addons_total_cents(add_ons, vehicle.size)

      metadata = %{kind: "appointment_addons", appointment_id: appointment.id}

      case StripeClient.charge_off_session(customer.stripe_customer_id, amount_cents, metadata) do
        {:ok, intent} ->
          {:ok, _appt} = add(appointment, add_on_ids)
          record_succeeded_payment(appointment, customer, amount_cents, intent.id)
          {:ok, :charged}

        {:error, _reason} ->
          addon_checkout_fallback(appointment, customer, add_ons, add_on_ids, amount_cents)
      end
    else
      {:error, :not_editable} -> {:error, :not_editable}
      [] -> {:error, :no_add_ons}
      nil -> {:error, :no_add_ons}
    end
  end

  @doc "True when the appointment may still be modified (status + 12h cutoff)."
  def editable?(appointment) do
    appointment.status in [:pending, :confirmed] and
      DateTime.diff(appointment.scheduled_at, DateTime.utc_now()) > @cutoff_seconds
  end

  defp record_succeeded_payment(appointment, customer, amount_cents, payment_intent_id) do
    {:ok, payment} =
      Payment
      |> Ash.Changeset.for_create(:create, %{amount_cents: amount_cents, status: :pending})
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.Changeset.force_change_attribute(:appointment_id, appointment.id)
      |> Ash.create()

    {:ok, payment} =
      payment
      |> Ash.Changeset.for_update(:complete, %{stripe_payment_intent_id: payment_intent_id})
      |> Ash.update()

    enqueue_payment_receipt(payment)
    payment
  end

  defp addon_checkout_fallback(appointment, customer, add_ons, add_on_ids, amount_cents) do
    {:ok, payment} =
      Payment
      |> Ash.Changeset.for_create(:create, %{amount_cents: amount_cents, status: :pending})
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.Changeset.force_change_attribute(:appointment_id, appointment.id)
      |> Ash.create()

    case StripeClient.create_addon_checkout(appointment, add_ons, add_on_ids, amount_cents, to_string(customer.email)) do
      {:ok, session} ->
        {:ok, _} =
          payment
          |> Ash.Changeset.for_update(:update, %{stripe_checkout_session_id: session.id})
          |> Ash.update()

        {:ok, session.url}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp enqueue_payment_receipt(payment) do
    %{payment_id: payment.id}
    |> MobileCarWash.Notifications.PaymentReceiptWorker.new(queue: :notifications)
    |> Oban.insert()
  end
```

- [ ] **Step 5: Run test to verify it passes**

Run: `mix test test/mobile_car_wash/scheduling/request_add_services_test.exs`
Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/mobile_car_wash/billing/stripe_client.ex \
        lib/mobile_car_wash/scheduling/appointment_services.ex \
        test/mobile_car_wash/scheduling/request_add_services_test.exs
git commit -m "feat(scheduling): add request_add_services/2 off-session orchestration + checkout fallback"
```

---

## Task 6: Webhook `appointment_addons` completion branch

When the off-session charge failed and the customer paid via the hosted Checkout fallback, the `checkout.session.completed` webhook attaches the add-ons and marks the pending `Payment` succeeded.

**Files:**
- Modify: `lib/mobile_car_wash/scheduling/appointment_services.ex` (`complete_addon_checkout/1`)
- Modify: `lib/mobile_car_wash_web/controllers/stripe_webhook_controller.ex` (`appointment_addons` branch)
- Test: `test/mobile_car_wash_web/controllers/stripe_webhook_addons_test.exs`

**Interfaces:**
- Consumes: `AppointmentServices.add/2`, `Payment` `:by_checkout_session`/`:complete`, `PaymentReceiptWorker`.
- Produces: `AppointmentServices.complete_addon_checkout(session_map) :: :ok | {:error, term}`. `session_map` has `:id`, `:payment_intent`, and `:metadata` (string- or atom-keyed) with `kind`/`appointment_id`/`add_on_ids` (comma-joined).

- [ ] **Step 1: Write the failing test**

```elixir
# test/mobile_car_wash_web/controllers/stripe_webhook_addons_test.exs
defmodule MobileCarWashWeb.StripeWebhookAddonsTest do
  use MobileCarWash.DataCase, async: false

  alias MobileCarWash.Scheduling.{AppointmentServices, AppointmentAddOn, AddOn, Appointment}
  alias MobileCarWash.Billing.Payment

  require Ash.Query

  test "complete_addon_checkout attaches add-ons and marks the payment succeeded" do
    # minimal appointment + add-on + pending payment with a checkout session id
    {:ok, customer} =
      MobileCarWash.Accounts.Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "wh-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "WH",
        phone: "+15125550000"
      })
      |> Ash.create()

    {:ok, service_type} =
      MobileCarWash.Scheduling.ServiceType
      |> Ash.Changeset.for_create(:create, %{name: "Basic", slug: "wh-#{System.unique_integer([:positive])}", base_price_cents: 5_000, duration_minutes: 45})
      |> Ash.create()

    {:ok, vehicle} =
      MobileCarWash.Fleet.Vehicle
      |> Ash.Changeset.for_create(:create, %{make: "Toyota", model: "Camry", year: 2021})
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.Changeset.force_change_attribute(:size, :car)
      |> Ash.create()

    {:ok, address} =
      MobileCarWash.Fleet.Address
      |> Ash.Changeset.for_create(:create, %{street: "1 Main", city: "SA", state: "TX", zip: "78259"})
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create()

    {:ok, appt} =
      Appointment
      |> Ash.Changeset.for_create(:book, %{
        scheduled_at: DateTime.add(DateTime.utc_now(), 48 * 3600),
        price_cents: 5_000,
        duration_minutes: 45,
        customer_id: customer.id,
        vehicle_id: vehicle.id,
        address_id: address.id,
        service_type_id: service_type.id
      })
      |> Ash.create()

    {:ok, addon} =
      AddOn
      |> Ash.Changeset.for_create(:create, %{name: "Wax", slug: "wax-#{System.unique_integer([:positive])}", price_cents: 2_000})
      |> Ash.create()

    {:ok, payment} =
      Payment
      |> Ash.Changeset.for_create(:create, %{amount_cents: 2_000, status: :pending})
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.Changeset.force_change_attribute(:appointment_id, appt.id)
      |> Ash.Changeset.force_change_attribute(:stripe_checkout_session_id, "cs_test_addon_1")
      |> Ash.create()

    session = %{
      id: "cs_test_addon_1",
      payment_intent: "pi_test_addon_1",
      metadata: %{"kind" => "appointment_addons", "appointment_id" => appt.id, "add_on_ids" => addon.id}
    }

    assert :ok = AppointmentServices.complete_addon_checkout(session)

    assert [%{price_cents: 2_000}] =
             AppointmentAddOn |> Ash.Query.filter(appointment_id == ^appt.id) |> Ash.read!()

    assert Ash.get!(Appointment, appt.id).price_cents == 7_000
    assert Ash.get!(Payment, payment.id).status == :succeeded
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/mobile_car_wash_web/controllers/stripe_webhook_addons_test.exs`
Expected: FAIL — `complete_addon_checkout/1` undefined.

- [ ] **Step 3: Implement `complete_addon_checkout/1`**

Add to `lib/mobile_car_wash/scheduling/appointment_services.ex`:

```elixir
  @doc """
  Webhook completion for a hosted add-on checkout: attach the add-ons and mark
  the pending payment succeeded.
  """
  def complete_addon_checkout(session) do
    metadata = Map.get(session, :metadata) || %{}
    appointment_id = metadata["appointment_id"] || metadata[:appointment_id]
    add_on_ids = parse_ids(metadata["add_on_ids"] || metadata[:add_on_ids])

    with {:ok, appointment} <- Ash.get(Appointment, appointment_id, authorize?: false),
         {:ok, _appt} <- add(appointment, add_on_ids) do
      mark_payment_succeeded(Map.get(session, :id), Map.get(session, :payment_intent))
      :ok
    end
  end

  defp parse_ids(nil), do: []
  defp parse_ids(""), do: []
  defp parse_ids(csv) when is_binary(csv), do: String.split(csv, ",", trim: true)
  defp parse_ids(list) when is_list(list), do: list

  defp mark_payment_succeeded(nil, _pi), do: :ok

  defp mark_payment_succeeded(session_id, payment_intent_id) do
    Payment
    |> Ash.Query.for_read(:by_checkout_session, %{session_id: session_id})
    |> Ash.read!()
    |> List.first()
    |> case do
      nil ->
        :ok

      payment ->
        {:ok, payment} =
          payment
          |> Ash.Changeset.for_update(:complete, %{stripe_payment_intent_id: payment_intent_id})
          |> Ash.update()

        enqueue_payment_receipt(payment)
        :ok
    end
  end
```

- [ ] **Step 4: Add the webhook branch**

In `lib/mobile_car_wash_web/controllers/stripe_webhook_controller.ex`, add `alias MobileCarWash.Scheduling.AppointmentServices` and replace the `checkout.session.completed` clause with:

```elixir
  defp process_event(%{type: "checkout.session.completed"} = event) do
    session = event.data.object
    metadata = Map.get(session, :metadata) || %{}
    kind = metadata["kind"] || metadata[:kind]

    cond do
      kind == "appointment_addons" ->
        Logger.info("Stripe add-on checkout completed: #{session.id}")
        AppointmentServices.complete_addon_checkout(session)

      Map.get(session, :mode) == "subscription" ->
        Logger.info("Stripe subscription checkout completed: #{session.id}")
        SubscriptionOrchestrator.create_from_checkout(session)

      true ->
        Logger.info("Stripe payment checkout completed: #{session.id}")
        payment_intent_id = Map.get(session, :payment_intent)
        Booking.complete_payment(session.id, payment_intent_id)
    end
  end
```

- [ ] **Step 5: Run test to verify it passes**

Run: `mix test test/mobile_car_wash_web/controllers/stripe_webhook_addons_test.exs`
Expected: PASS.

- [ ] **Step 6: Run the existing webhook tests for regressions**

Run: `mix test test/mobile_car_wash_web/controllers`
Expected: PASS (booking + subscription checkout paths unaffected — different/absent `kind`).

- [ ] **Step 7: Commit**

```bash
git add lib/mobile_car_wash/scheduling/appointment_services.ex \
        lib/mobile_car_wash_web/controllers/stripe_webhook_controller.ex \
        test/mobile_car_wash_web/controllers/stripe_webhook_addons_test.exs
git commit -m "feat(billing): webhook attaches add-ons on appointment_addons checkout completion"
```

---

## Task 7: Recurring scheduler add-on charging + decline notification

When the 6am worker books a recurring occurrence whose schedule has add-ons, charge the saved card off-session and attach on success. On failure, leave the base wash unchanged and enqueue a "card declined for add-ons" notification. (The scheduler bypasses the Booking orchestrator and has no size pricing — the size-scaled `add/2` path supplies it.)

**Files:**
- Create: `lib/mobile_car_wash/notifications/addon_charge_failed_worker.ex`
- Modify: `lib/mobile_car_wash/notifications/email.ex` (`addon_charge_failed/2`)
- Modify: `lib/mobile_car_wash/scheduling/recurring_appointment_scheduler.ex` (`create_appointment/2` tail)
- Test: `test/mobile_car_wash/scheduling/recurring_scheduler_addons_test.exs`

**Interfaces:**
- Consumes: `AppointmentServices.{schedule_add_ons/1, add/2}`, `StripeClient.charge_off_session/3`, `Pricing.addons_total_cents/2`, `Email.addon_charge_failed/2`.
- Produces: scheduler attaches schedule add-ons to each generated occurrence on charge success; `AddOnChargeFailedWorker.perform/1` (`%{"appointment_id" => id}`) sends the decline email.

- [ ] **Step 1: Write the failing test**

```elixir
# test/mobile_car_wash/scheduling/recurring_scheduler_addons_test.exs
defmodule MobileCarWash.Scheduling.RecurringSchedulerAddonsTest do
  use MobileCarWash.DataCase, async: false

  import Swoosh.TestAssertions

  alias MobileCarWash.Scheduling.{AppointmentServices, AppointmentAddOn, AddOn, Appointment, RecurringAppointmentScheduler}

  require Ash.Query

  defp build(cus) do
    {:ok, customer} =
      MobileCarWash.Accounts.Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "rsch-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "RSch",
        phone: "+15125550000"
      })
      |> Ash.Changeset.force_change_attribute(:stripe_customer_id, cus)
      |> Ash.create()

    {:ok, service_type} =
      MobileCarWash.Scheduling.ServiceType
      |> Ash.Changeset.for_create(:create, %{name: "Basic", slug: "rsch-#{System.unique_integer([:positive])}", base_price_cents: 5_000, duration_minutes: 45})
      |> Ash.create()

    {:ok, vehicle} =
      MobileCarWash.Fleet.Vehicle
      |> Ash.Changeset.for_create(:create, %{make: "Toyota", model: "Camry", year: 2021})
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.Changeset.force_change_attribute(:size, :car)
      |> Ash.create()

    {:ok, address} =
      MobileCarWash.Fleet.Address
      |> Ash.Changeset.for_create(:create, %{street: "1 Main", city: "SA", state: "TX", zip: "78259"})
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create()

    {:ok, schedule} =
      MobileCarWash.Scheduling.RecurringSchedule
      |> Ash.Changeset.for_create(:create, %{frequency: :weekly, preferred_day: 3, preferred_time: ~T[10:00:00]})
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.Changeset.force_change_attribute(:vehicle_id, vehicle.id)
      |> Ash.Changeset.force_change_attribute(:address_id, address.id)
      |> Ash.Changeset.force_change_attribute(:service_type_id, service_type.id)
      |> Ash.create()

    {:ok, addon} =
      AddOn
      |> Ash.Changeset.for_create(:create, %{name: "Wax", slug: "wax-#{System.unique_integer([:positive])}", price_cents: 2_000})
      |> Ash.create()

    :ok = AppointmentServices.replace_schedule_add_ons(schedule.id, [addon.id])
    %{schedule: schedule}
  end

  test "charge success: occurrence gets the schedule's add-ons attached and price bumped" do
    %{schedule: schedule} = build("cus_test_sch")
    date = Date.add(Date.utc_today(), 5)

    assert {:ok, appt} = RecurringAppointmentScheduler.create_appointment(schedule, date)

    assert [%{price_cents: 2_000}] =
             AppointmentAddOn |> Ash.Query.filter(appointment_id == ^appt.id) |> Ash.read!()

    assert Ash.get!(Appointment, appt.id).price_cents == 5_000 + 2_000
  end

  test "charge decline: base wash kept, no add-ons, decline email enqueued" do
    %{schedule: schedule} = build("cus_decline_sch")
    date = Date.add(Date.utc_today(), 5)

    assert {:ok, appt} = RecurringAppointmentScheduler.create_appointment(schedule, date)

    assert [] = AppointmentAddOn |> Ash.Query.filter(appointment_id == ^appt.id) |> Ash.read!()
    assert Ash.get!(Appointment, appt.id).price_cents == 5_000
    assert_email_sent(subject: "Action needed: card declined for add-ons")
  end
end
```
Note: `create_appointment/2` is currently a private function. Step 4 promotes it to public (`def`) so it is directly testable and so the add-on tail is exercised.

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/mobile_car_wash/scheduling/recurring_scheduler_addons_test.exs`
Expected: FAIL — `create_appointment/2` is private (UndefinedFunctionError) / add-on charging not implemented.

- [ ] **Step 3: Add the email template**

In `lib/mobile_car_wash/notifications/email.ex`, add (matching the existing Swoosh/Layout style):

```elixir
  @doc """
  Sent when a recurring occurrence's add-ons could not be charged off-session.
  The base wash still happens; the customer is asked to update billing.
  """
  def addon_charge_failed(customer, service_name) do
    billing_url = "https://drivewaydetailcosa.com/account/subscription"

    inner_html = """
    <h2 style="margin:0 0 12px;font-size:20px;color:#0f172a;">We couldn't add your extras</h2>
    <p>Hi #{customer.name},</p>
    <p>Your upcoming <strong>#{service_name}</strong> is still booked, but we were
    unable to charge your saved card for the add-on services on this wash.</p>
    <p>The base wash will go ahead as scheduled. To keep your add-ons, please
    update your payment method.</p>
    <p style="margin:24px 0;">#{Layout.button("Update billing", billing_url)}</p>
    """

    inner_text = """
    We couldn't add your extras

    Hi #{customer.name},

    Your upcoming #{service_name} is still booked, but we were unable to charge
    your saved card for the add-on services on this wash. The base wash will go
    ahead as scheduled. To keep your add-ons, please update your payment method:

    #{billing_url}
    """

    new()
    |> to({customer.name, to_string(customer.email)})
    |> from(@from)
    |> subject("Action needed: card declined for add-ons")
    |> html_body(Layout.wrap_html(inner_html))
    |> text_body(Layout.wrap_text(inner_text))
  end
```

- [ ] **Step 4: Add the worker**

```elixir
# lib/mobile_car_wash/notifications/addon_charge_failed_worker.ex
defmodule MobileCarWash.Notifications.AddOnChargeFailedWorker do
  @moduledoc "Notifies a customer that their saved card was declined for recurring add-ons."
  use Oban.Worker, queue: :notifications, max_attempts: 3

  alias MobileCarWash.Notifications.Email
  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Scheduling.{Appointment, ServiceType}

  require Logger

  @impl true
  def perform(%Oban.Job{args: %{"appointment_id" => appointment_id}}) do
    with {:ok, appointment} <- Ash.get(Appointment, appointment_id, authorize?: false),
         {:ok, customer} <- Ash.get(Customer, appointment.customer_id, authorize?: false) do
      service_name =
        case Ash.get(ServiceType, appointment.service_type_id, authorize?: false) do
          {:ok, st} -> st.name
          _ -> "Detailing Service"
        end

      Email.addon_charge_failed(customer, service_name)
      |> MobileCarWash.Mailer.deliver()

      :ok
    else
      {:error, reason} ->
        Logger.error("Failed to send add-on decline notice: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
```

- [ ] **Step 5: Wire add-on charging into the scheduler**

In `lib/mobile_car_wash/scheduling/recurring_appointment_scheduler.ex`:

1. Change `defp create_appointment(schedule, date) do` to `def create_appointment(schedule, date) do`.
2. Replace the final `|> Ash.create()` of the `with` body so the created appointment is post-processed:

```elixir
  def create_appointment(schedule, date) do
    {:ok, service_type} = Ash.get(ServiceType, schedule.service_type_id)

    with {:ok, block} <- find_or_generate_block(service_type, date, schedule.preferred_time),
         {:ok, appointment} <-
           Appointment
           |> Ash.Changeset.for_create(:book, %{
             customer_id: schedule.customer_id,
             vehicle_id: schedule.vehicle_id,
             address_id: schedule.address_id,
             service_type_id: schedule.service_type_id,
             scheduled_at: block.starts_at,
             appointment_block_id: block.id,
             price_cents: service_type.base_price_cents,
             duration_minutes: service_type.duration_minutes,
             notes: "Auto-scheduled (recurring)"
           })
           |> Ash.Changeset.force_change_attribute(:recurring_schedule_id, schedule.id)
           |> Ash.create() do
      {:ok, charge_and_attach_add_ons(schedule, appointment)}
    end
  end

  defp charge_and_attach_add_ons(schedule, appointment) do
    case MobileCarWash.Scheduling.AppointmentServices.schedule_add_ons(schedule.id) do
      [] ->
        appointment

      add_ons ->
        vehicle = Ash.get!(MobileCarWash.Fleet.Vehicle, schedule.vehicle_id, authorize?: false)
        customer = Ash.get!(MobileCarWash.Accounts.Customer, schedule.customer_id, authorize?: false)
        amount_cents = MobileCarWash.Billing.Pricing.addons_total_cents(add_ons, vehicle.size)
        add_on_ids = Enum.map(add_ons, & &1.id)

        metadata = %{kind: "recurring_addons", appointment_id: appointment.id}

        case MobileCarWash.Billing.StripeClient.charge_off_session(customer.stripe_customer_id, amount_cents, metadata) do
          {:ok, _intent} ->
            {:ok, updated} = MobileCarWash.Scheduling.AppointmentServices.add(appointment, add_on_ids)
            updated

          {:error, reason} ->
            Logger.warning("Add-on charge declined for appointment #{appointment.id}: #{inspect(reason)}")

            %{appointment_id: appointment.id}
            |> MobileCarWash.Notifications.AddOnChargeFailedWorker.new(queue: :notifications)
            |> Oban.insert()

            appointment
        end
    end
  end
```
(If `MobileCarWash.Fleet.Vehicle` isn't already aliased in this module, use the fully-qualified name as shown.)

- [ ] **Step 6: Run test to verify it passes**

Run: `mix test test/mobile_car_wash/scheduling/recurring_scheduler_addons_test.exs`
Expected: PASS (2 tests).

- [ ] **Step 7: Run the existing scheduler tests for regressions**

Run: `mix test test/mobile_car_wash/scheduling/recurring_appointment_scheduler_test.exs`
Expected: PASS (schedules with no add-ons behave exactly as before).

- [ ] **Step 8: Commit**

```bash
git add lib/mobile_car_wash/notifications/addon_charge_failed_worker.ex \
        lib/mobile_car_wash/notifications/email.ex \
        lib/mobile_car_wash/scheduling/recurring_appointment_scheduler.ex \
        test/mobile_car_wash/scheduling/recurring_scheduler_addons_test.exs
git commit -m "feat(scheduling): charge + attach recurring add-ons per occurrence with decline notice"
```

---

## Task 8: Panel B — "Manage add-ons" UI on recurring schedules

Toggle/replace a schedule's add-on set in the dashboard, showing the per-wash size-scaled cost so the customer knows each future occurrence is charged.

**Files:**
- Modify: `lib/mobile_car_wash_web/live/dashboard_live.ex`
- Test: `test/mobile_car_wash_web/live/dashboard_live_test.exs` (add cases)

**Interfaces:**
- Consumes: `AppointmentServices.{schedule_add_on_ids/1, replace_schedule_add_ons/1}`, all active `AddOn`s, `Pricing.calculate/2`.
- Produces: `manage_addons` / `save_addons` / `cancel_addons` events; `@all_add_ons` assign; per-schedule `add_on_ids` + `add_ons_per_wash_cents` in the Panel-B display map; `@managing_addons_id` assign.

- [ ] **Step 1: Write the failing test**

```elixir
# append to test/mobile_car_wash_web/live/dashboard_live_test.exs

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
    assert MobileCarWash.Scheduling.AppointmentServices.schedule_add_on_ids(schedule.id) == [addon.id]
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/mobile_car_wash_web/live/dashboard_live_test.exs -k "attach add-ons to a recurring schedule"`
Expected: FAIL — no "Manage add-ons" button / event.

- [ ] **Step 3: Load active add-ons + per-schedule add-on data in mount and `load_schedules/2`**

In `lib/mobile_car_wash_web/live/dashboard_live.ex`:

1. Add `AddOn` to the `MobileCarWash.Scheduling` alias and `Pricing` alias: `alias MobileCarWash.Billing.{Pricing, Subscription, SubscriptionPlan, SubscriptionUsage}` and add `AddOn`, `AppointmentServices` to the Scheduling alias.
2. In `mount/3`, in the success branch `assign(...)`, add `managing_addons_id: nil` and load all active add-ons:

```elixir
           all_add_ons:
             AddOn |> Ash.Query.filter(active == true) |> Ash.Query.sort(sort_order: :asc) |> Ash.read!(),
```

3. In `load_schedules/2`, extend each schedule's display map with its add-on set and per-wash cost:

```elixir
        add_on_ids = AppointmentServices.schedule_add_on_ids(s.id)
        add_ons = AppointmentServices.schedule_add_ons(s.id)
        per_wash = Pricing.addons_total_cents(add_ons, v.size)

        %{
          id: s.id,
          frequency: s.frequency,
          preferred_day: s.preferred_day,
          preferred_time: s.preferred_time,
          active: s.active,
          service_type_name: st.name,
          vehicle_label: "#{v.year || ""} #{v.make} #{v.model}" |> String.trim(),
          add_on_ids: add_on_ids,
          add_ons_per_wash_cents: per_wash
        }
```

- [ ] **Step 4: Add the events**

Add handlers (near the other schedule handlers):

```elixir
  def handle_event("manage_addons", %{"id" => id}, socket) do
    {:noreply, assign(socket, managing_addons_id: id)}
  end

  def handle_event("cancel_addons", _params, socket) do
    {:noreply, assign(socket, managing_addons_id: nil)}
  end

  def handle_event("save_addons", %{"schedule_id" => id} = params, socket) do
    customer = socket.assigns.current_customer
    add_on_ids = Map.get(params, "add_on_ids", [])

    with {:ok, schedule} <- Ash.get(RecurringSchedule, id),
         true <- schedule.customer_id == customer.id do
      :ok = AppointmentServices.replace_schedule_add_ons(id, add_on_ids)

      {:noreply,
       socket
       |> assign(managing_addons_id: nil)
       |> load_schedules(customer.id)
       |> put_flash(:info, "Add-ons updated")}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not update add-ons")}
    end
  end
```

- [ ] **Step 5: Add Panel-B markup**

In the Panel-B per-schedule block, inside the non-editing `<div :if={@editing_id != schedule.id}>`, add a "Manage add-ons" button to the button row and a per-wash cost line; and add a managing form. Insert the button after the "Edit" button:

```heex
                <button
                  class="btn btn-outline btn-xs"
                  phx-click="manage_addons"
                  phx-value-id={schedule.id}
                >
                  Manage add-ons
                </button>
```

Add a cost line under the cadence `<p>` (only when there are add-ons):

```heex
                  <p :if={schedule.add_ons_per_wash_cents > 0} class="text-xs text-base-content/70">
                    + ${div(schedule.add_ons_per_wash_cents, 100)} add-ons per wash
                  </p>
```

Add the managing form after the edit `<form>` (sibling, guarded by `@managing_addons_id`):

```heex
            <form
              :if={@managing_addons_id == schedule.id}
              id={"manage-addons-#{schedule.id}"}
              phx-submit="save_addons"
            >
              <input type="hidden" name="schedule_id" value={schedule.id} />
              <p class="text-sm font-medium mb-1">Add-ons (charged each future wash)</p>
              <label :for={a <- @all_add_ons} class="flex items-center gap-2 py-1">
                <input
                  type="checkbox"
                  name="add_on_ids[]"
                  value={a.id}
                  checked={a.id in schedule.add_on_ids}
                  class="checkbox checkbox-sm"
                />
                <span class="text-sm">{a.name} — ${div(a.price_cents, 100)}</span>
              </label>
              <div class="flex gap-2 mt-2">
                <button type="submit" class="btn btn-primary btn-xs">Save add-ons</button>
                <button type="button" class="btn btn-ghost btn-xs" phx-click="cancel_addons">
                  Cancel
                </button>
              </div>
            </form>
```

- [ ] **Step 6: Run test to verify it passes**

Run: `mix test test/mobile_car_wash_web/live/dashboard_live_test.exs -k "attach add-ons to a recurring schedule"`
Expected: PASS.

- [ ] **Step 7: Run the whole dashboard test file**

Run: `mix test test/mobile_car_wash_web/live/dashboard_live_test.exs`
Expected: PASS (all Cycle-1 tests still green).

- [ ] **Step 8: Commit**

```bash
git add lib/mobile_car_wash_web/live/dashboard_live.ex test/mobile_car_wash_web/live/dashboard_live_test.exs
git commit -m "feat(dashboard): Panel B manage add-ons for recurring schedules"
```

---

## Task 9: Panel C — "Add services" on editable upcoming washes

A picker on each editable upcoming appointment (status + 12h cutoff), driving `request_add_services/2`. Card success re-renders with the new price; card failure redirects to the hosted checkout URL. Non-editable appointments show add-ons read-only with a "too late to modify" note. Ownership + editability enforced server-side.

**Files:**
- Modify: `lib/mobile_car_wash_web/live/dashboard_live.ex`
- Test: `test/mobile_car_wash_web/live/dashboard_live_test.exs` (add cases)

**Interfaces:**
- Consumes: `AppointmentServices.{request_add_services/2, editable?/1}`, `@all_add_ons`.
- Produces: `add_services` / `manage_appt_addons` / `cancel_appt_addons` events; per-appointment `editable` + `id` in the Panel-C display map; `@adding_services_id` assign.

- [ ] **Step 1: Write the failing tests**

```elixir
# append to test/mobile_car_wash_web/live/dashboard_live_test.exs

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
      |> Ash.Changeset.for_create(:create, %{name: "Tire Shine", slug: "ts-#{System.unique_integer([:positive])}", price_cents: 1_500})
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
    |> Ash.Changeset.for_update(:update, %{scheduled_at: DateTime.add(DateTime.utc_now(), 6 * 3600)})
    |> Ash.update!()

    {:ok, _view, html} = live(conn, ~p"/dashboard")
    assert html =~ "Too late to modify"
    refute html =~ "add-services-#{appt.id}"
  end
```
Note: `create_upcoming_appointment/1` schedules 3 days out (editable). The second test pushes it inside the cutoff. If the generic `:update` rejects `scheduled_at` in the past-guard, 6h out is still future, so it is accepted.

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/mobile_car_wash_web/live/dashboard_live_test.exs -k "Add services|too-late"`
Expected: FAIL — no "Add services" button / event / note.

- [ ] **Step 3: Add `editable` to the Panel-C display map**

In `load_upcoming/2`, add the field to the per-appointment map (the helper already has the loaded `Appointment` struct `a`):

```elixir
        %{
          id: a.id,
          scheduled_at: a.scheduled_at,
          status: a.status,
          price_cents: a.price_cents,
          service_type_name: st.name,
          vehicle_label: "#{v.year || ""} #{v.make} #{v.model}" |> String.trim(),
          add_on_count: add_on_count,
          editable: AppointmentServices.editable?(a)
        }
```

Also add `adding_services_id: nil` to the `mount/3` success-branch assigns.

- [ ] **Step 4: Add the events**

```elixir
  def handle_event("manage_appt_addons", %{"id" => id}, socket) do
    {:noreply, assign(socket, adding_services_id: id)}
  end

  def handle_event("cancel_appt_addons", _params, socket) do
    {:noreply, assign(socket, adding_services_id: nil)}
  end

  def handle_event("add_services", %{"appointment_id" => id} = params, socket) do
    customer = socket.assigns.current_customer
    add_on_ids = Map.get(params, "add_on_ids", [])

    with {:ok, appt} <- Ash.get(Appointment, id),
         true <- appt.customer_id == customer.id do
      case AppointmentServices.request_add_services(appt, add_on_ids) do
        {:ok, :charged} ->
          {:noreply,
           socket
           |> assign(adding_services_id: nil)
           |> load_upcoming(customer.id)
           |> put_flash(:info, "Services added")}

        {:ok, checkout_url} when is_binary(checkout_url) ->
          {:noreply, redirect(socket, external: checkout_url)}

        {:error, :not_editable} ->
          {:noreply, put_flash(socket, :error, "This wash can no longer be modified")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not add services")}
      end
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not add services")}
    end
  end
```

- [ ] **Step 5: Add Panel-C markup**

Replace the Panel-C per-appointment inner block to add the picker (editable) or the read-only note (not editable). Inside `<div :for={appt <- @upcoming} ...>`, after the existing price/status block, add:

```heex
            <div class="mt-2">
              <button
                :if={appt.editable && @adding_services_id != appt.id}
                class="btn btn-outline btn-xs"
                phx-click="manage_appt_addons"
                phx-value-id={appt.id}
              >
                Add services
              </button>

              <p :if={!appt.editable} class="text-xs text-base-content/60 italic">
                Too late to modify
              </p>

              <form
                :if={appt.editable && @adding_services_id == appt.id}
                id={"add-services-#{appt.id}"}
                phx-submit="add_services"
              >
                <input type="hidden" name="appointment_id" value={appt.id} />
                <p class="text-sm font-medium mb-1">Add services (charged now)</p>
                <label :for={a <- @all_add_ons} class="flex items-center gap-2 py-1">
                  <input
                    type="checkbox"
                    name="add_on_ids[]"
                    value={a.id}
                    class="checkbox checkbox-sm"
                  />
                  <span class="text-sm">{a.name} — ${div(a.price_cents, 100)}</span>
                </label>
                <div class="flex gap-2 mt-2">
                  <button type="submit" class="btn btn-primary btn-xs">Add &amp; pay</button>
                  <button type="button" class="btn btn-ghost btn-xs" phx-click="cancel_appt_addons">
                    Cancel
                  </button>
                </div>
              </form>
            </div>
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `mix test test/mobile_car_wash_web/live/dashboard_live_test.exs -k "Add services|too-late"`
Expected: PASS.

- [ ] **Step 7: Run the whole dashboard test file**

Run: `mix test test/mobile_car_wash_web/live/dashboard_live_test.exs`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add lib/mobile_car_wash_web/live/dashboard_live.ex test/mobile_car_wash_web/live/dashboard_live_test.exs
git commit -m "feat(dashboard): Panel C add services to editable upcoming washes"
```

---

## Final: full gate + branch completion

- [ ] **Step 1: Run the full precommit gate**

Run: `mix precommit`
Expected: compile clean (`--warnings-as-errors`), format clean, deps unlocked-unused clean, **all tests pass** (baseline 1307 + the new Cycle-2 tests, 0 failures). Output must be pristine — investigate any warning.

- [ ] **Step 2: Whole-branch code review**

Use **superpowers:requesting-code-review** for a final whole-branch review (opus). Address any critical findings before merging.

- [ ] **Step 3: Finish the branch**

Use **superpowers:finishing-a-development-branch**: stash the convention files, merge `feature/subscriber-dashboard-cycle2` into `main` with `--no-ff`, pop the stash, **do NOT push**. Append the Cycle-2 record to `.superpowers/sdd/progress.md`.

---

## Self-Review (completed against the spec)

- **Spec §Components coverage:** DashboardLive Panel B (Task 8) + Panel C (Task 9); `RecurringScheduleAddOn` + replace-set (Task 2); `AppointmentServices.add/2` (Task 1); `charge_off_session/3` (Task 4); `request_add_services/2` (Task 5); webhook extension (Task 6); recurring scheduler integration (Task 7). `:update_preferences` already shipped in Cycle 1.
- **Spec §Decisions:** future-only recurring add-ons (Task 2/7); 12h+status editable cutoff (Task 5 `editable?/1`, enforced in Tasks 5/9); off-session→Checkout fallback (Tasks 4/5/6); recurring per-occurrence failure → base wash + notification (Task 7). User-added decision: reliable default-PM at checkout (Task 3).
- **Spec §Data Flow / §Error Handling:** all five flows covered; `:no_payment_method`/decline both route to fallback (Task 4 tests + Task 5/7 branches); ownership at LiveView call sites + editability guard server-side (Tasks 5/8/9).
- **Spec §Testing Strategy:** payment-intent mock extended for success AND decline (Task 4); per-unit TDD; both add-on attach paths assert size-scaled price equals the booking path.
- **Type consistency:** `add/2`, `request_add_services/2`, `complete_addon_checkout/1`, `replace_schedule_add_ons/2`, `schedule_add_on_ids/1`, `schedule_add_ons/1`, `editable?/1`, `charge_off_session/3`, `create_addon_checkout/5` names are used identically across tasks. Display-map keys (`add_on_ids`, `add_ons_per_wash_cents`, `editable`) match between loader and HEEx.
- **Deferred (not built):** on-site embedded payment; propagating recurring changes to already-booked appointments; restyling `/account/*`; self-service PM management — all per spec §Deferred.
