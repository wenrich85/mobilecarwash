# Admin Manual Appointments & Blocks Calendar — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the admin a week-calendar to quickly add/delete appointment blocks, and a form to manually create appointments that bypass payment for a client while still recording the full-value transaction.

**Architecture:** Two admin LiveView surfaces (a week calendar replacing the current `/admin/blocks` list, and a new manual-appointment form) backed by one new `Booking.admin_create_booking/1` orchestrator. Comp tracking is added to the `Payment` resource (full value recorded, $0 collected, `comped` flag). A guarded block-delete context function prevents deleting blocks that still hold appointments. Everything reuses the existing Ash resources, the `Booking` module's private notification helpers, and the established admin-LiveView test/login conventions.

**Tech Stack:** Elixir, Phoenix LiveView, Ash Framework, AshPostgres, DaisyUI/Tailwind, Oban (notifications).

## Global Constraints

- Dev server runs on **port 4010** (not 4000).
- Full test suite command: `mix test`. Format check: `mix format --check-formatted`.
- Three files are uncommitted by project convention and must NEVER be staged/committed: `config/dev.exs`, `AGENTS.md`, `docs/customer-flows.html`. Use `git add <explicit paths>` only — never `git add -A` / `git add .`.
- Money is stored in integer cents everywhere. `amount_cents` on a Payment is the full service value; `collected_cents` is what was actually taken in.
- Ash migrations are generated with `mix ash_postgres.generate_migrations --name <name>`, then applied with `mix ecto.migrate`. Never hand-write the schema migration; edit only to add data backfill.
- Creating a `Vehicle` or `Address` for a customer requires `Ash.Changeset.force_change_attribute(:customer_id, id)` — `customer_id` is not in those resources' create `accept` lists.
- Admin LiveViews live under `MobileCarWashWeb.Admin.*` in `lib/mobile_car_wash_web/live/admin/`. Routes go in the `live_session :admin` block in `lib/mobile_car_wash_web/router.ex` (around line 240).
- Admin LiveView tests authenticate with the `create_admin/0` + `sign_in/2` helper pattern shown in `test/mobile_car_wash_web/live/admin/dispatch_live_command_center_test.exs` (copy it into each new test file; there is no shared helper).

---

## File Structure

- `lib/mobile_car_wash/billing/payment.ex` — add `collected_cents`, `comped`, `comp_reason`; add `record_manual` create action; extend `:complete` to stamp `collected_cents`.
- `priv/repo/migrations/<ts>_add_payment_comp_fields.exs` — generated migration + backfill.
- `lib/mobile_car_wash/scheduling/appointment.ex` — add `admin_book` create action.
- `lib/mobile_car_wash/scheduling/appointment_block.ex` — add `:destroy` to defaults.
- `lib/mobile_car_wash/scheduling/blocks.ex` — NEW context: `create_block/1`, `delete_block/1` (guarded).
- `lib/mobile_car_wash/scheduling/booking.ex` — add `admin_create_booking/1` + private client/vehicle/address resolution helpers.
- `lib/mobile_car_wash_web/live/admin/blocks_live.ex` — replace list UI with a week calendar (add/delete blocks).
- `lib/mobile_car_wash_web/live/admin/manual_appointment_live.ex` — NEW manual-appointment form LiveView.
- `lib/mobile_car_wash_web/router.ex` — add `/admin/appointments/new` route.
- Tests alongside each of the above.

---

## Task 1: Payment comp-tracking fields + `record_manual` action

**Files:**
- Modify: `lib/mobile_car_wash/billing/payment.ex`
- Create: `priv/repo/migrations/<generated>_add_payment_comp_fields.exs`
- Test: `test/mobile_car_wash/billing/payment_manual_test.exs`

**Interfaces:**
- Produces:
  - `Payment` attributes `collected_cents :: integer | nil`, `comped :: boolean` (default `false`), `comp_reason :: String.t() | nil`.
  - Action `Payment` `create :record_manual` accepting `%{amount_cents, collected_cents, comped, comp_reason}`; sets `status: :succeeded`, `paid_at: now`; validates `comp_reason` present when `comped == true`. `customer_id`/`appointment_id` are set by the caller via `force_change_attribute`.
  - `:complete` now also sets `collected_cents = amount_cents`.

- [ ] **Step 1: Write the failing test**

```elixir
# test/mobile_car_wash/billing/payment_manual_test.exs
defmodule MobileCarWash.Billing.PaymentManualTest do
  use MobileCarWash.DataCase, async: true

  alias MobileCarWash.Billing.Payment
  alias MobileCarWash.Accounts.Customer

  defp customer do
    Customer
    |> Ash.Changeset.for_create(:create_guest, %{
      name: "Comp Client",
      email: "comp-#{System.unique_integer([:positive])}@test.com",
      phone: "+15125550111"
    })
    |> Ash.create!(authorize?: false)
  end

  test "record_manual for a comp records full value, zero collected, succeeded" do
    cust = customer()

    {:ok, payment} =
      Payment
      |> Ash.Changeset.for_create(:record_manual, %{
        amount_cents: 5000,
        collected_cents: 0,
        comped: true,
        comp_reason: "VIP friend"
      })
      |> Ash.Changeset.force_change_attribute(:customer_id, cust.id)
      |> Ash.create(authorize?: false)

    assert payment.amount_cents == 5000
    assert payment.collected_cents == 0
    assert payment.comped == true
    assert payment.comp_reason == "VIP friend"
    assert payment.status == :succeeded
    assert payment.paid_at
  end

  test "record_manual requires a reason when comped" do
    cust = customer()

    {:error, error} =
      Payment
      |> Ash.Changeset.for_create(:record_manual, %{
        amount_cents: 5000,
        collected_cents: 0,
        comped: true
      })
      |> Ash.Changeset.force_change_attribute(:customer_id, cust.id)
      |> Ash.create(authorize?: false)

    assert Exception.message(error) =~ "comp_reason"
  end

  test "record_manual for a paid manual booking records the collected amount" do
    cust = customer()

    {:ok, payment} =
      Payment
      |> Ash.Changeset.for_create(:record_manual, %{
        amount_cents: 5000,
        collected_cents: 5000,
        comped: false
      })
      |> Ash.Changeset.force_change_attribute(:customer_id, cust.id)
      |> Ash.create(authorize?: false)

    assert payment.comped == false
    assert payment.collected_cents == 5000
    assert payment.status == :succeeded
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/mobile_car_wash/billing/payment_manual_test.exs`
Expected: FAIL — `record_manual` action does not exist (`No such action record_manual`).

- [ ] **Step 3: Add the attributes to the Payment resource**

In `lib/mobile_car_wash/billing/payment.ex`, inside the `attributes do` block, after the `paid_at` attribute (line 41), add:

```elixir
    attribute :collected_cents, :integer do
      public?(true)
      description("Amount actually taken in. Differs from amount_cents on comped bookings (0 collected).")
    end

    attribute :comped, :boolean do
      default(false)
      allow_nil?(false)
      public?(true)
    end

    attribute :comp_reason, :string do
      public?(true)
    end
```

- [ ] **Step 4: Add the `record_manual` action and extend `:complete`**

In the `actions do` block of `lib/mobile_car_wash/billing/payment.ex`, add this action after the `:complete` action (after line 82):

```elixir
    create :record_manual do
      @doc "Records a manually-created payment (admin comp or off-platform collection). Always succeeded."
      accept([:amount_cents, :collected_cents, :comped, :comp_reason])

      change(set_attribute(:status, :succeeded))
      change(set_attribute(:paid_at, &DateTime.utc_now/0))

      validate(present(:comp_reason),
        where: [attribute_equals(:comped, true)],
        message: "comp_reason is required when comping a booking"
      )
    end
```

Then, inside the existing `update :complete do` action, add this change so normal (Stripe) payments also carry `collected_cents` once they succeed. Add it directly after the `change(set_attribute(:paid_at, &DateTime.utc_now/0))` line (line 68):

```elixir
      change(fn changeset, _context ->
        Ash.Changeset.change_attribute(
          changeset,
          :collected_cents,
          changeset.data.amount_cents
        )
      end)
```

- [ ] **Step 5: Generate and backfill the migration**

Run: `mix ash_postgres.generate_migrations --name add_payment_comp_fields`

Then open the newly generated file in `priv/repo/migrations/` and add a backfill so existing succeeded payments show full collection. Inside the generated `def up do` block, after the `alter table` statements, add:

```elixir
    execute("UPDATE payments SET collected_cents = amount_cents WHERE collected_cents IS NULL")
```

- [ ] **Step 6: Apply the migration**

Run: `mix ecto.migrate`
Expected: migration applies cleanly, no errors.

- [ ] **Step 7: Run the test to verify it passes**

Run: `mix test test/mobile_car_wash/billing/payment_manual_test.exs`
Expected: PASS (3 tests).

- [ ] **Step 8: Format and commit**

```bash
mix format
git add lib/mobile_car_wash/billing/payment.ex \
        test/mobile_car_wash/billing/payment_manual_test.exs \
        priv/repo/migrations
git commit -m "feat(billing): add comp tracking + record_manual action to Payment"
```

---

## Task 2: Appointment `admin_book` action

**Files:**
- Modify: `lib/mobile_car_wash/scheduling/appointment.ex`
- Test: `test/mobile_car_wash/scheduling/appointment_admin_book_test.exs`

**Interfaces:**
- Produces: `Appointment` `create :admin_book` accepting `%{scheduled_at, notes, customer_id, vehicle_id, address_id, service_type_id, technician_id}` + arguments `price_cents`, `duration_minutes`, `discount_cents`. Sets `status: :confirmed`, leaves `appointment_block_id` nil, applies NO future-date or capacity validation (admin override).

- [ ] **Step 1: Write the failing test**

```elixir
# test/mobile_car_wash/scheduling/appointment_admin_book_test.exs
defmodule MobileCarWash.Scheduling.AppointmentAdminBookTest do
  use MobileCarWash.DataCase, async: true

  alias MobileCarWash.Scheduling.{Appointment, ServiceType}
  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Fleet.{Vehicle, Address}

  defp fixtures do
    cust =
      Customer
      |> Ash.Changeset.for_create(:create_guest, %{
        name: "Admin Booked",
        email: "adminbook-#{System.unique_integer([:positive])}@test.com",
        phone: "+15125550122"
      })
      |> Ash.create!(authorize?: false)

    service =
      ServiceType
      |> Ash.Changeset.for_create(:create, %{
        name: "Basic Wash",
        slug: "basic_#{System.unique_integer([:positive])}",
        base_price_cents: 5000,
        duration_minutes: 45
      })
      |> Ash.create!(authorize?: false)

    vehicle =
      Vehicle
      |> Ash.Changeset.for_create(:create, %{make: "Toyota", model: "Camry", size: :car})
      |> Ash.Changeset.force_change_attribute(:customer_id, cust.id)
      |> Ash.create!(authorize?: false)

    address =
      Address
      |> Ash.Changeset.for_create(:create, %{
        street: "123 Main St",
        city: "Austin",
        state: "TX",
        zip: "78701"
      })
      |> Ash.Changeset.force_change_attribute(:customer_id, cust.id)
      |> Ash.create!(authorize?: false)

    %{cust: cust, service: service, vehicle: vehicle, address: address}
  end

  test "admin_book creates a confirmed, standalone appointment in the past without error" do
    %{cust: cust, service: service, vehicle: vehicle, address: address} = fixtures()
    # Deliberately in the past — admin override must NOT reject it.
    past = DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.truncate(:second)

    {:ok, appt} =
      Appointment
      |> Ash.Changeset.for_create(:admin_book, %{
        scheduled_at: past,
        customer_id: cust.id,
        vehicle_id: vehicle.id,
        address_id: address.id,
        service_type_id: service.id,
        price_cents: 5000,
        duration_minutes: 45
      })
      |> Ash.create(authorize?: false)

    assert appt.status == :confirmed
    assert appt.appointment_block_id == nil
    assert appt.price_cents == 5000
    assert appt.duration_minutes == 45
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/mobile_car_wash/scheduling/appointment_admin_book_test.exs`
Expected: FAIL — `No such action admin_book`.

- [ ] **Step 3: Add the `admin_book` action**

In `lib/mobile_car_wash/scheduling/appointment.ex`, inside the `actions do` block, add this action after the `:book` action (after line 144):

```elixir
    create :admin_book do
      @doc "Admin-created appointment. Confirmed immediately, standalone (no block), bypasses availability/future-date checks."
      accept([
        :scheduled_at,
        :notes,
        :customer_id,
        :vehicle_id,
        :address_id,
        :service_type_id,
        :technician_id
      ])

      argument(:price_cents, :integer, allow_nil?: false)
      argument(:duration_minutes, :integer, allow_nil?: false)
      argument(:discount_cents, :integer, default: 0)

      change(set_attribute(:price_cents, arg(:price_cents)))
      change(set_attribute(:duration_minutes, arg(:duration_minutes)))
      change(set_attribute(:discount_cents, arg(:discount_cents)))
      change(set_attribute(:status, :confirmed))
    end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/mobile_car_wash/scheduling/appointment_admin_book_test.exs`
Expected: PASS.

- [ ] **Step 5: Format and commit**

```bash
mix format
git add lib/mobile_car_wash/scheduling/appointment.ex \
        test/mobile_car_wash/scheduling/appointment_admin_book_test.exs
git commit -m "feat(scheduling): add admin_book action for manual appointments"
```

---

## Task 3: Guarded block delete (`Blocks` context)

**Files:**
- Modify: `lib/mobile_car_wash/scheduling/appointment_block.ex`
- Create: `lib/mobile_car_wash/scheduling/blocks.ex`
- Test: `test/mobile_car_wash/scheduling/blocks_test.exs`

**Interfaces:**
- Produces:
  - `AppointmentBlock` gains `:destroy` in its `defaults`.
  - `MobileCarWash.Scheduling.Blocks.delete_block(id)` → `:ok | {:error, :block_has_appointments} | {:error, :block_not_found}`. Deletes only empty blocks.
  - `MobileCarWash.Scheduling.Blocks.create_block(attrs)` → `{:ok, block} | {:error, changeset}`. Thin wrapper over `AppointmentBlock` `:create`.

- [ ] **Step 1: Write the failing test**

```elixir
# test/mobile_car_wash/scheduling/blocks_test.exs
defmodule MobileCarWash.Scheduling.BlocksTest do
  use MobileCarWash.DataCase, async: true

  alias MobileCarWash.Scheduling.{Blocks, AppointmentBlock, Appointment, ServiceType}
  alias MobileCarWash.Operations.Technician
  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Fleet.{Vehicle, Address}

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

  defp tech do
    Technician
    |> Ash.Changeset.for_create(:create, %{name: "Tech #{System.unique_integer([:positive])}"})
    |> Ash.create!(authorize?: false)
  end

  defp block(service, tech) do
    starts_at = DateTime.utc_now() |> DateTime.add(2 * 86_400, :second) |> DateTime.truncate(:second)

    AppointmentBlock
    |> Ash.Changeset.for_create(:create, %{
      service_type_id: service.id,
      technician_id: tech.id,
      starts_at: starts_at,
      ends_at: DateTime.add(starts_at, 3 * 3600, :second),
      closes_at: DateTime.add(starts_at, -3600, :second),
      capacity: 3,
      status: :open
    })
    |> Ash.create!(authorize?: false)
  end

  test "delete_block removes an empty block" do
    b = block(service(), tech())
    assert :ok = Blocks.delete_block(b.id)
    assert {:error, _} = Ash.get(AppointmentBlock, b.id)
  end

  test "delete_block refuses a block that has appointments" do
    svc = service()
    t = tech()
    b = block(svc, t)

    cust =
      Customer
      |> Ash.Changeset.for_create(:create_guest, %{
        name: "In Block",
        email: "inblock-#{System.unique_integer([:positive])}@test.com",
        phone: "+15125550133"
      })
      |> Ash.create!(authorize?: false)

    vehicle =
      Vehicle
      |> Ash.Changeset.for_create(:create, %{make: "Honda", model: "Civic", size: :car})
      |> Ash.Changeset.force_change_attribute(:customer_id, cust.id)
      |> Ash.create!(authorize?: false)

    address =
      Address
      |> Ash.Changeset.for_create(:create, %{street: "1 A St", city: "Austin", state: "TX", zip: "78701"})
      |> Ash.Changeset.force_change_attribute(:customer_id, cust.id)
      |> Ash.create!(authorize?: false)

    Appointment
    |> Ash.Changeset.for_create(:admin_book, %{
      scheduled_at: b.starts_at,
      customer_id: cust.id,
      vehicle_id: vehicle.id,
      address_id: address.id,
      service_type_id: svc.id,
      price_cents: 5000,
      duration_minutes: 45
    })
    |> Ash.Changeset.force_change_attribute(:appointment_block_id, b.id)
    |> Ash.create!(authorize?: false)

    assert {:error, :block_has_appointments} = Blocks.delete_block(b.id)
    assert {:ok, _} = Ash.get(AppointmentBlock, b.id)
  end

  test "delete_block returns not_found for a missing id" do
    assert {:error, :block_not_found} = Blocks.delete_block(Ash.UUID.generate())
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/mobile_car_wash/scheduling/blocks_test.exs`
Expected: FAIL — `MobileCarWash.Scheduling.Blocks` is undefined.

- [ ] **Step 3: Add `:destroy` to AppointmentBlock defaults**

In `lib/mobile_car_wash/scheduling/appointment_block.ex`, change line 80 from:

```elixir
    defaults([:read])
```

to:

```elixir
    defaults([:read, :destroy])
```

- [ ] **Step 4: Create the Blocks context**

```elixir
# lib/mobile_car_wash/scheduling/blocks.ex
defmodule MobileCarWash.Scheduling.Blocks do
  @moduledoc """
  Admin block management helpers: quick create, and a guarded delete that
  refuses to remove a block that still holds appointments.
  """

  alias MobileCarWash.Scheduling.AppointmentBlock

  @doc "Creates an appointment block. Thin wrapper over the resource :create action."
  def create_block(attrs) do
    AppointmentBlock
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create(authorize?: false)
  end

  @doc """
  Deletes a block only if it holds no appointments. Returns `:ok`,
  `{:error, :block_has_appointments}`, or `{:error, :block_not_found}`.
  """
  def delete_block(id) do
    case Ash.get(AppointmentBlock, id, load: [:appointment_count], authorize?: false) do
      {:ok, %{appointment_count: count} = block} when count in [0, nil] ->
        case Ash.destroy(block, authorize?: false) do
          :ok -> :ok
          {:ok, _} -> :ok
          {:error, reason} -> {:error, reason}
        end

      {:ok, _block} ->
        {:error, :block_has_appointments}

      {:error, _} ->
        {:error, :block_not_found}
    end
  end
end
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `mix test test/mobile_car_wash/scheduling/blocks_test.exs`
Expected: PASS (3 tests).

- [ ] **Step 6: Format and commit**

```bash
mix format
git add lib/mobile_car_wash/scheduling/appointment_block.ex \
        lib/mobile_car_wash/scheduling/blocks.ex \
        test/mobile_car_wash/scheduling/blocks_test.exs
git commit -m "feat(scheduling): guarded block delete via Blocks context"
```

---

## Task 4: `admin_create_booking/1` orchestrator

**Files:**
- Modify: `lib/mobile_car_wash/scheduling/booking.ex`
- Test: `test/mobile_car_wash/scheduling/admin_create_booking_test.exs`

**Interfaces:**
- Consumes: `Appointment.:admin_book` (Task 2), `Payment.:record_manual` (Task 1), existing private helpers in `Booking` (`enqueue_confirmation_email/1`, `enqueue_sms_confirmation/1`, `enqueue_push_confirmation/1`, `enqueue_appointment_reminder/1`, `enqueue_sms_reminder/1`, `enqueue_push_reminder/1`), `MobileCarWash.Billing.Pricing.calculate/2`, `CashFlowEngine.record_deposit/2`, `Customer.:create_guest`, `Customer.:by_email`.
- Produces: `Booking.admin_create_booking(params)` → `{:ok, %{appointment: appt, payment: payment}}` | `{:error, term}`.

  `params` map:
  ```
  %{
    # client — exactly one of:
    customer_id: String.t(),                 # existing
    new_customer: %{name:, email:, phone:},  # create/dedupe by email
    # vehicle — exactly one of:
    vehicle_id: String.t(),
    new_vehicle: %{make:, model:, size:},    # size in [:car, :suv_van, :pickup]
    # address — exactly one of:
    address_id: String.t(),
    new_address: %{street:, city:, state:, zip:},
    service_type_id: String.t(),
    scheduled_at: DateTime.t(),
    technician_id: String.t() | nil,         # optional
    notes: String.t() | nil,                 # optional
    waive_payment?: boolean(),
    comp_reason: String.t() | nil,           # required when waive_payment?
    collected_cents: integer() | nil,        # when not waived; defaults to full price
    notify_client?: boolean()
  }
  ```

- [ ] **Step 1: Write the failing test**

```elixir
# test/mobile_car_wash/scheduling/admin_create_booking_test.exs
defmodule MobileCarWash.Scheduling.AdminCreateBookingTest do
  use MobileCarWash.DataCase, async: false
  use Oban.Testing, repo: MobileCarWash.Repo

  alias MobileCarWash.Scheduling.{Booking, ServiceType, Appointment}
  alias MobileCarWash.Billing.Payment
  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Fleet.{Vehicle, Address}

  require Ash.Query

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
      |> Ash.Changeset.for_create(:create, %{street: "9 Oak", city: "Austin", state: "TX", zip: "78701"})
      |> Ash.Changeset.force_change_attribute(:customer_id, cust.id)
      |> Ash.create!(authorize?: false)

    %{cust: cust, vehicle: vehicle, address: address}
  end

  defp base_params(svc) do
    %{
      service_type_id: svc.id,
      scheduled_at: DateTime.utc_now() |> DateTime.add(3 * 86_400, :second) |> DateTime.truncate(:second),
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
      |> Map.merge(%{customer_id: cust.id, vehicle_id: v.id, address_id: a.id, waive_payment?: false})

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
      |> Map.merge(%{customer_id: cust.id, vehicle_id: v.id, address_id: a.id, waive_payment?: true, comp_reason: "x"})

    {:ok, _} = Booking.admin_create_booking(silent)
    refute_enqueued(worker: MobileCarWash.Notifications.BookingConfirmationWorker)

    loud = Map.put(silent, :notify_client?, true)
    {:ok, _} = Booking.admin_create_booking(loud)
    assert_enqueued(worker: MobileCarWash.Notifications.BookingConfirmationWorker)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/mobile_car_wash/scheduling/admin_create_booking_test.exs`
Expected: FAIL — `Booking.admin_create_booking/1` is undefined.

- [ ] **Step 3: Add the orchestrator to Booking**

In `lib/mobile_car_wash/scheduling/booking.ex`, add the aliases and the public function + private helpers. First, ensure `Customer` and `Pricing` are reachable — add near the top aliases (after line 28):

```elixir
  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Billing.Pricing
```

Then add this public function immediately after `create_booking/1` (after its `end` on line 93) — it lives in the same module so it can call the existing private `enqueue_*` helpers:

```elixir
  @doc """
  Admin-only: creates a confirmed appointment directly, bypassing Stripe.
  Always records a Payment (full service value; $0 collected when waived).
  See the plan/spec for the full params contract.
  """
  def admin_create_booking(params) do
    result =
      Repo.transaction(fn ->
        with {:ok, service_type} <- fetch_service_type(params.service_type_id),
             {:ok, customer} <- resolve_client(params),
             {:ok, vehicle} <- resolve_vehicle(params, customer.id),
             {:ok, address} <- resolve_address(params, customer.id),
             price_cents = Pricing.calculate(service_type.base_price_cents, vehicle.size),
             {:ok, appointment} <-
               create_admin_appointment(params, service_type, customer, vehicle, address, price_cents),
             {:ok, payment} <- record_manual_payment(params, appointment, customer, price_cents) do
          %{appointment: appointment, payment: payment}
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)

    case result do
      {:ok, %{appointment: appointment, payment: payment}} ->
        maybe_record_admin_cash_flow(payment, appointment)
        maybe_notify_admin_booking(params, appointment)
        AppointmentTracker.broadcast_new_appointment(appointment.id)
        {:ok, %{appointment: appointment, payment: payment}}

      other ->
        other
    end
  end

  # --- admin booking helpers ---

  defp resolve_client(%{customer_id: id}) when is_binary(id) and id != "" do
    case Ash.get(Customer, id, authorize?: false) do
      {:ok, customer} -> {:ok, customer}
      {:error, _} -> {:error, :customer_not_found}
    end
  end

  defp resolve_client(%{new_customer: %{email: email} = attrs}) do
    case find_customer_by_email(email) do
      {:ok, existing} ->
        {:ok, existing}

      :none ->
        Customer
        |> Ash.Changeset.for_create(:create_guest, attrs)
        |> Ash.create(authorize?: false)
    end
  end

  defp resolve_client(_), do: {:error, :client_required}

  defp find_customer_by_email(email) do
    case Customer
         |> Ash.Query.for_read(:by_email, %{email: email})
         |> Ash.read!(authorize?: false) do
      [customer | _] -> {:ok, customer}
      [] -> :none
    end
  end

  defp resolve_vehicle(%{vehicle_id: id}, customer_id) when is_binary(id) and id != "" do
    verify_vehicle_ownership(id, customer_id)
  end

  defp resolve_vehicle(%{new_vehicle: attrs}, customer_id) do
    Vehicle
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.Changeset.force_change_attribute(:customer_id, customer_id)
    |> Ash.create(authorize?: false)
  end

  defp resolve_vehicle(_, _), do: {:error, :vehicle_required}

  defp resolve_address(%{address_id: id}, customer_id) when is_binary(id) and id != "" do
    verify_address_ownership(id, customer_id)
  end

  defp resolve_address(%{new_address: attrs}, customer_id) do
    Address
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.Changeset.force_change_attribute(:customer_id, customer_id)
    |> Ash.create(authorize?: false)
  end

  defp resolve_address(_, _), do: {:error, :address_required}

  defp create_admin_appointment(params, service_type, customer, vehicle, address, price_cents) do
    Appointment
    |> Ash.Changeset.for_create(:admin_book, %{
      scheduled_at: params.scheduled_at,
      notes: params[:notes],
      customer_id: customer.id,
      vehicle_id: vehicle.id,
      address_id: address.id,
      service_type_id: service_type.id,
      technician_id: params[:technician_id],
      price_cents: price_cents,
      duration_minutes: service_type.duration_minutes
    })
    |> Ash.create(authorize?: false)
  end

  defp record_manual_payment(params, appointment, customer, price_cents) do
    waived? = params[:waive_payment?] == true

    collected =
      cond do
        waived? -> 0
        is_integer(params[:collected_cents]) -> params[:collected_cents]
        true -> price_cents
      end

    Payment
    |> Ash.Changeset.for_create(:record_manual, %{
      amount_cents: price_cents,
      collected_cents: collected,
      comped: waived?,
      comp_reason: params[:comp_reason]
    })
    |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
    |> Ash.Changeset.force_change_attribute(:appointment_id, appointment.id)
    |> Ash.create(authorize?: false)
  end

  defp maybe_record_admin_cash_flow(%{collected_cents: collected}, appointment)
       when is_integer(collected) and collected > 0 do
    record_payment_in_cash_flow(%{amount_cents: collected}, appointment)
  end

  defp maybe_record_admin_cash_flow(_payment, _appointment), do: :ok

  defp maybe_notify_admin_booking(%{notify_client?: true}, appointment) do
    enqueue_confirmation_email(appointment)
    enqueue_sms_confirmation(appointment)
    enqueue_push_confirmation(appointment)
    enqueue_appointment_reminder(appointment)
    enqueue_sms_reminder(appointment)
    enqueue_push_reminder(appointment)
    :ok
  end

  defp maybe_notify_admin_booking(_params, _appointment), do: :ok
```

Note: `record_payment_in_cash_flow/2` already exists (line 577) and reads `payment.amount_cents`; passing `%{amount_cents: collected}` reuses it to record only the collected amount.

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/mobile_car_wash/scheduling/admin_create_booking_test.exs`
Expected: PASS (5 tests).

- [ ] **Step 5: Format and commit**

```bash
mix format
git add lib/mobile_car_wash/scheduling/booking.ex \
        test/mobile_car_wash/scheduling/admin_create_booking_test.exs
git commit -m "feat(scheduling): admin_create_booking orchestrator (comp + record transaction)"
```

---

## Task 5: Blocks week-calendar LiveView (add + delete)

**Files:**
- Modify: `lib/mobile_car_wash_web/live/admin/blocks_live.ex`
- Test: `test/mobile_car_wash_web/live/admin/blocks_live_calendar_test.exs`

**Interfaces:**
- Consumes: `MobileCarWash.Scheduling.Blocks.create_block/1`, `Blocks.delete_block/1`.
- Produces: `/admin/blocks` renders a 7-day week grid. Elements the test relies on: `#blocks-calendar`, `#block-add-form` (appears after clicking a day), a block card with `id="block-#{id}"`, a delete button `phx-click="delete_block"` for empty blocks, and a disabled/absent delete for booked blocks (a `.block-locked` marker instead).

- [ ] **Step 1: Write the failing test**

```elixir
# test/mobile_car_wash_web/live/admin/blocks_live_calendar_test.exs
defmodule MobileCarWashWeb.Admin.BlocksLiveCalendarTest do
  use MobileCarWashWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  require Ash.Query

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Scheduling.{AppointmentBlock, Appointment, ServiceType}
  alias MobileCarWash.Operations.Technician
  alias MobileCarWash.Fleet.{Vehicle, Address}

  defp create_admin do
    {:ok, admin} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "admin-blocks-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Blocks Admin",
        phone: "+15125550301"
      })
      |> Ash.create()

    admin
    |> Ash.Changeset.for_update(:update, %{role: :admin})
    |> Ash.update!(authorize?: false)
  end

  defp sign_in(conn, user) do
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> post("/auth/customer/password/sign_in", %{
      "customer" => %{"email" => to_string(user.email), "password" => "Password123!"}
    })
    |> recycle()
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

  defp tech do
    Technician
    |> Ash.Changeset.for_create(:create, %{name: "Cal Tech #{System.unique_integer([:positive])}"})
    |> Ash.create!(authorize?: false)
  end

  defp empty_block(svc, t) do
    starts_at = DateTime.utc_now() |> DateTime.add(2 * 86_400, :second) |> DateTime.truncate(:second)

    AppointmentBlock
    |> Ash.Changeset.for_create(:create, %{
      service_type_id: svc.id,
      technician_id: t.id,
      starts_at: starts_at,
      ends_at: DateTime.add(starts_at, 3 * 3600, :second),
      closes_at: DateTime.add(starts_at, -3600, :second),
      capacity: 3,
      status: :open
    })
    |> Ash.create!(authorize?: false)
  end

  test "renders the week calendar", %{conn: conn} do
    conn = sign_in(conn, create_admin())
    {:ok, view, _html} = live(conn, ~p"/admin/blocks")
    assert has_element?(view, "#blocks-calendar")
  end

  test "deletes an empty block", %{conn: conn} do
    svc = service()
    t = tech()
    b = empty_block(svc, t)

    conn = sign_in(conn, create_admin())
    {:ok, view, _html} = live(conn, ~p"/admin/blocks")

    # Navigate to the week that contains the block, then delete it.
    assert has_element?(view, "#block-#{b.id}")
    view |> element("#block-#{b.id} button[phx-click='delete_block']") |> render_click()

    refute has_element?(view, "#block-#{b.id}")
    assert {:error, _} = Ash.get(AppointmentBlock, b.id)
  end

  test "a booked block shows a locked marker and cannot be deleted", %{conn: conn} do
    svc = service()
    t = tech()
    b = empty_block(svc, t)

    cust =
      Customer
      |> Ash.Changeset.for_create(:create_guest, %{
        name: "Booked",
        email: "booked-#{System.unique_integer([:positive])}@test.com",
        phone: "+15125550177"
      })
      |> Ash.create!(authorize?: false)

    vehicle =
      Vehicle
      |> Ash.Changeset.for_create(:create, %{make: "Kia", model: "Soul", size: :car})
      |> Ash.Changeset.force_change_attribute(:customer_id, cust.id)
      |> Ash.create!(authorize?: false)

    address =
      Address
      |> Ash.Changeset.for_create(:create, %{street: "5 Elm", city: "Austin", state: "TX", zip: "78701"})
      |> Ash.Changeset.force_change_attribute(:customer_id, cust.id)
      |> Ash.create!(authorize?: false)

    Appointment
    |> Ash.Changeset.for_create(:admin_book, %{
      scheduled_at: b.starts_at,
      customer_id: cust.id,
      vehicle_id: vehicle.id,
      address_id: address.id,
      service_type_id: svc.id,
      price_cents: 5000,
      duration_minutes: 45
    })
    |> Ash.Changeset.force_change_attribute(:appointment_block_id, b.id)
    |> Ash.create!(authorize?: false)

    conn = sign_in(conn, create_admin())
    {:ok, view, _html} = live(conn, ~p"/admin/blocks")

    assert has_element?(view, "#block-#{b.id} .block-locked")
    refute has_element?(view, "#block-#{b.id} button[phx-click='delete_block']")
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `mix test test/mobile_car_wash_web/live/admin/blocks_live_calendar_test.exs`
Expected: FAIL — no `#blocks-calendar` element / no `delete_block` handler.

- [ ] **Step 3: Rewrite BlocksLive as a week calendar**

Replace the contents of `lib/mobile_car_wash_web/live/admin/blocks_live.ex` with the following. It keeps the existing generate/optimize/cancel/closes_at handlers, adds week navigation, per-day add-block, and guarded delete.

```elixir
defmodule MobileCarWashWeb.Admin.BlocksLive do
  @moduledoc """
  Admin week-calendar of appointment blocks. Click a day to add a block;
  click an empty block to delete it. Blocks holding appointments are locked.
  """
  use MobileCarWashWeb, :live_view

  alias MobileCarWash.Scheduling.{AppointmentBlock, Blocks, BlockGenerator, BlockOptimizer}
  alias MobileCarWash.Scheduling.ServiceType
  alias MobileCarWash.Operations.Technician

  require Ash.Query

  @generate_days 14

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Appointment Blocks",
       week_start: monday_of(Date.utc_today()),
       adding_day: nil,
       technicians: active_technicians(),
       service_types: service_types(),
       generate_days: @generate_days
     )
     |> load_week()}
  end

  # === week navigation ===

  @impl true
  def handle_event("prev_week", _params, socket) do
    {:noreply, socket |> assign(week_start: Date.add(socket.assigns.week_start, -7), adding_day: nil) |> load_week()}
  end

  def handle_event("next_week", _params, socket) do
    {:noreply, socket |> assign(week_start: Date.add(socket.assigns.week_start, 7), adding_day: nil) |> load_week()}
  end

  def handle_event("this_week", _params, socket) do
    {:noreply, socket |> assign(week_start: monday_of(Date.utc_today()), adding_day: nil) |> load_week()}
  end

  # === add block ===

  def handle_event("open_add", %{"day" => day}, socket) do
    {:noreply, assign(socket, adding_day: day)}
  end

  def handle_event("cancel_add", _params, socket) do
    {:noreply, assign(socket, adding_day: nil)}
  end

  def handle_event("create_block", params, socket) do
    with {:ok, starts_at} <- parse_datetime_local(params["starts_at"]),
         {:ok, ends_at} <- parse_datetime_local(params["ends_at"]) do
      attrs = %{
        service_type_id: params["service_type_id"],
        technician_id: params["technician_id"],
        starts_at: starts_at,
        ends_at: ends_at,
        closes_at: DateTime.add(starts_at, -3600, :second),
        capacity: String.to_integer(params["capacity"] || "3"),
        status: :open
      }

      case Blocks.create_block(attrs) do
        {:ok, _block} ->
          {:noreply,
           socket
           |> assign(adding_day: nil)
           |> load_week()
           |> put_flash(:info, "Block added.")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not add block — check the fields.")}
      end
    else
      _ -> {:noreply, put_flash(socket, :error, "Invalid start/end time.")}
    end
  end

  # === delete block (guarded) ===

  def handle_event("delete_block", %{"id" => id}, socket) do
    case Blocks.delete_block(id) do
      :ok ->
        {:noreply, socket |> load_week() |> put_flash(:info, "Block deleted.")}

      {:error, :block_has_appointments} ->
        {:noreply, put_flash(socket, :error, "Move or cancel its appointments before deleting this block.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not delete block.")}
    end
  end

  # === existing block ops (kept) ===

  def handle_event("optimize_now", %{"id" => id}, socket) do
    case BlockOptimizer.close_and_optimize(id) do
      {:ok, _} -> {:noreply, socket |> load_week() |> put_flash(:info, "Block optimized — customers notified.")}
      {:error, :already_optimized} -> {:noreply, put_flash(socket, :error, "Block has already been optimized.")}
      {:error, reason} -> {:noreply, put_flash(socket, :error, "Optimize failed: #{inspect(reason)}")}
    end
  end

  def handle_event("generate_blocks", params, socket) do
    tech_id = params["technician_id"] || fallback_tech_id(socket)

    if tech_id in [nil, ""] do
      {:noreply, put_flash(socket, :error, "No active technician found — create one before generating blocks.")}
    else
      :ok = BlockGenerator.generate_ahead(@generate_days, technician_id: tech_id)
      {:noreply, socket |> load_week() |> put_flash(:info, "Generated blocks for the next #{@generate_days} days.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto py-8 px-4">
      <div class="flex justify-between items-center mb-6 flex-wrap gap-2">
        <h1 class="text-3xl font-bold">Appointment Blocks</h1>
        <div class="flex items-center gap-2">
          <.link navigate={~p"/admin/appointments/new"} class="btn btn-secondary btn-sm">
            + New Appointment
          </.link>
          <form phx-submit="generate_blocks" class="flex items-end gap-2">
            <select :if={@technicians != []} name="technician_id" class="select select-bordered select-sm">
              <option :for={tech <- @technicians} value={tech.id}>{tech.name}</option>
            </select>
            <button type="submit" class="btn btn-primary btn-sm"
              data-confirm="Generate blocks for the next 14 days?">
              Generate {@generate_days} Days
            </button>
          </form>
        </div>
      </div>

      <div class="flex items-center justify-between mb-4">
        <button class="btn btn-ghost btn-sm" phx-click="prev_week">← Prev</button>
        <div class="font-semibold">
          Week of {Calendar.strftime(@week_start, "%b %-d, %Y")}
        </div>
        <div class="flex gap-2">
          <button class="btn btn-ghost btn-sm" phx-click="this_week">Today</button>
          <button class="btn btn-ghost btn-sm" phx-click="next_week">Next →</button>
        </div>
      </div>

      <div id="blocks-calendar" class="grid grid-cols-1 md:grid-cols-7 gap-2">
        <div :for={day <- week_days(@week_start)} class="border border-base-200 rounded-lg p-2 min-h-40">
          <div class="text-xs font-semibold text-base-content/70 mb-2">
            {Calendar.strftime(day, "%a %-m/%-d")}
          </div>

          <div :for={block <- blocks_on(@blocks, day)} id={"block-#{block.id}"}
               class="card bg-base-100 shadow-sm mb-2">
            <div class="card-body p-2 text-xs">
              <div class="font-bold">{block.service_type.name}</div>
              <div>
                {Calendar.strftime(block.starts_at, "%-I:%M")}–{Calendar.strftime(block.ends_at, "%-I:%M %p")}
              </div>
              <div class="text-base-content/70">
                {block.appointment_count} / {block.capacity} booked
              </div>
              <button :if={block.appointment_count in [0, nil] and block.status == :open}
                class="btn btn-error btn-outline btn-xs mt-1"
                phx-click="delete_block" phx-value-id={block.id}
                data-confirm="Delete this empty block?">
                Delete
              </button>
              <span :if={not (block.appointment_count in [0, nil]) or block.status != :open}
                class="block-locked text-base-content/50 mt-1">
                Locked
              </span>
            </div>
          </div>

          <button class="btn btn-ghost btn-xs w-full" phx-click="open_add"
                  phx-value-day={Date.to_iso8601(day)}>
            + Add
          </button>

          <form :if={@adding_day == Date.to_iso8601(day)} id="block-add-form"
                phx-submit="create_block" class="mt-2 space-y-1 text-xs">
            <input type="datetime-local" name="starts_at" required class="input input-bordered input-xs w-full"
                   value={"#{Date.to_iso8601(day)}T09:00"} />
            <input type="datetime-local" name="ends_at" required class="input input-bordered input-xs w-full"
                   value={"#{Date.to_iso8601(day)}T12:00"} />
            <select name="service_type_id" required class="select select-bordered select-xs w-full">
              <option :for={st <- @service_types} value={st.id}>{st.name}</option>
            </select>
            <select name="technician_id" required class="select select-bordered select-xs w-full">
              <option :for={tech <- @technicians} value={tech.id}>{tech.name}</option>
            </select>
            <input type="number" name="capacity" value="3" min="1" class="input input-bordered input-xs w-full" />
            <div class="flex gap-1">
              <button type="submit" class="btn btn-primary btn-xs flex-1">Save</button>
              <button type="button" class="btn btn-ghost btn-xs" phx-click="cancel_add">Cancel</button>
            </div>
          </form>
        </div>
      </div>
    </div>
    """
  end

  # === helpers ===

  defp monday_of(date) do
    Date.add(date, -(Date.day_of_week(date) - 1))
  end

  defp week_days(week_start), do: Enum.map(0..6, &Date.add(week_start, &1))

  defp blocks_on(blocks, day) do
    blocks
    |> Enum.filter(fn b -> DateTime.to_date(b.starts_at) == day end)
    |> Enum.sort_by(& &1.starts_at, DateTime)
  end

  defp load_week(socket) do
    week_start = socket.assigns.week_start
    {:ok, from} = DateTime.new(week_start, ~T[00:00:00])
    {:ok, to} = DateTime.new(Date.add(week_start, 7), ~T[00:00:00])

    blocks =
      AppointmentBlock
      |> Ash.Query.filter(starts_at >= ^from and starts_at < ^to and status != :cancelled)
      |> Ash.Query.sort(starts_at: :asc)
      |> Ash.Query.load([:service_type, :technician, :appointment_count])
      |> Ash.read!(authorize?: false)

    assign(socket, blocks: blocks)
  end

  defp service_types do
    ServiceType |> Ash.read!(authorize?: false)
  end

  defp active_technicians do
    Technician
    |> Ash.Query.filter(active == true)
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.read!(authorize?: false)
  end

  defp fallback_tech_id(socket) do
    case socket.assigns.technicians do
      [first | _] -> first.id
      _ -> nil
    end
  end

  defp parse_datetime_local(value) when is_binary(value) and value != "" do
    case NaiveDateTime.from_iso8601(value <> ":00") do
      {:ok, ndt} -> {:ok, DateTime.from_naive!(ndt, "Etc/UTC")}
      error -> error
    end
  end

  defp parse_datetime_local(_), do: {:error, :invalid}
end
```

Note: the calendar filters out `:cancelled` blocks. The `blocks_live_test.exs` "cancelling a block" data-only test still passes (it doesn't render the LiveView). If the old `blocks_live_test.exs` asserts on removed list markup, update those assertions to the new calendar in Step 4.

- [ ] **Step 4: Reconcile the old test file**

Run: `mix test test/mobile_car_wash_web/live/admin/blocks_live_test.exs`
If any test asserts on removed list-view markup (e.g. "Generate Next 14 Days" exact copy, "View appointments"), update those assertions to the new calendar markup, or delete the now-duplicated UI assertions (the new calendar test file covers rendering). Keep the auth-guard test and the pure cancel data test.

- [ ] **Step 5: Run both test files to verify they pass**

Run: `mix test test/mobile_car_wash_web/live/admin/blocks_live_calendar_test.exs test/mobile_car_wash_web/live/admin/blocks_live_test.exs`
Expected: PASS.

- [ ] **Step 6: Format and commit**

```bash
mix format
git add lib/mobile_car_wash_web/live/admin/blocks_live.ex \
        test/mobile_car_wash_web/live/admin/blocks_live_calendar_test.exs \
        test/mobile_car_wash_web/live/admin/blocks_live_test.exs
git commit -m "feat(admin): week-calendar block management with guarded delete"
```

---

## Task 6: Manual-appointment form LiveView + route

**Files:**
- Create: `lib/mobile_car_wash_web/live/admin/manual_appointment_live.ex`
- Modify: `lib/mobile_car_wash_web/router.ex`
- Test: `test/mobile_car_wash_web/live/admin/manual_appointment_live_test.exs`

**Interfaces:**
- Consumes: `Booking.admin_create_booking/1`.
- Produces: LiveView at `/admin/appointments/new`. Submits a `manual_appointment` form. On success, redirects to `/admin/dispatch` with a flash. Test relies on: `#manual-appointment-form`, a client mode toggle (existing vs new), and a `waive` checkbox that requires `comp_reason`.

- [ ] **Step 1: Write the failing test**

```elixir
# test/mobile_car_wash_web/live/admin/manual_appointment_live_test.exs
defmodule MobileCarWashWeb.Admin.ManualAppointmentLiveTest do
  use MobileCarWashWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  require Ash.Query

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Scheduling.{ServiceType, Appointment}
  alias MobileCarWash.Billing.Payment

  defp create_admin do
    {:ok, admin} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "admin-manual-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Manual Admin",
        phone: "+15125550302"
      })
      |> Ash.create()

    admin
    |> Ash.Changeset.for_update(:update, %{role: :admin})
    |> Ash.update!(authorize?: false)
  end

  defp sign_in(conn, user) do
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> post("/auth/customer/password/sign_in", %{
      "customer" => %{"email" => to_string(user.email), "password" => "Password123!"}
    })
    |> recycle()
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

  test "renders the manual appointment form", %{conn: conn} do
    conn = sign_in(conn, create_admin())
    {:ok, view, _html} = live(conn, ~p"/admin/appointments/new")
    assert has_element?(view, "#manual-appointment-form")
  end

  test "creates a comped appointment for a brand-new client", %{conn: conn} do
    svc = service()
    conn = sign_in(conn, create_admin())
    {:ok, view, _html} = live(conn, ~p"/admin/appointments/new")

    when_iso =
      DateTime.utc_now() |> DateTime.add(2 * 86_400, :second) |> Calendar.strftime("%Y-%m-%dT%H:%M")

    params = %{
      "client_mode" => "new",
      "new_customer_name" => "Walk Up",
      "new_customer_email" => "walkup-#{System.unique_integer([:positive])}@test.com",
      "new_customer_phone" => "+15125550188",
      "vehicle_make" => "Kia",
      "vehicle_model" => "Soul",
      "vehicle_size" => "car",
      "address_street" => "5 Elm",
      "address_city" => "Austin",
      "address_state" => "TX",
      "address_zip" => "78701",
      "service_type_id" => svc.id,
      "scheduled_at" => when_iso,
      "waive" => "true",
      "comp_reason" => "Owner comp",
      "notify_client" => "false"
    }

    result =
      view
      |> form("#manual-appointment-form", manual_appointment: params)
      |> render_submit()

    # LiveView redirects to dispatch on success.
    assert {:error, {:redirect, %{to: "/admin/dispatch"}}} = result

    appt = Appointment |> Ash.read!(authorize?: false) |> List.first()
    assert appt.status == :confirmed
    payment = Payment |> Ash.read!(authorize?: false) |> List.first()
    assert payment.comped == true
    assert payment.collected_cents == 0
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `mix test test/mobile_car_wash_web/live/admin/manual_appointment_live_test.exs`
Expected: FAIL — route/LiveView does not exist.

- [ ] **Step 3: Add the route**

In `lib/mobile_car_wash_web/router.ex`, inside the `live_session :admin` block (near the existing admin `live` routes around line 240–270), add:

```elixir
      live "/admin/appointments/new", ManualAppointmentLive, :new
```

- [ ] **Step 4: Create the LiveView**

```elixir
# lib/mobile_car_wash_web/live/admin/manual_appointment_live.ex
defmodule MobileCarWashWeb.Admin.ManualAppointmentLive do
  @moduledoc """
  Admin form to manually create an appointment. Supports an existing or new
  client, an inline vehicle + address, and a waive-payment (comp) option that
  still records the full-value transaction.
  """
  use MobileCarWashWeb, :live_view

  alias MobileCarWash.Scheduling.{Booking, ServiceType}
  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Operations.Technician

  require Ash.Query

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "New Appointment",
       client_mode: "existing",
       waive: false,
       customers: customers(),
       service_types: service_types(),
       technicians: technicians()
     )}
  end

  @impl true
  def handle_event("set_client_mode", %{"mode" => mode}, socket) do
    {:noreply, assign(socket, client_mode: mode)}
  end

  def handle_event("toggle_waive", params, socket) do
    {:noreply, assign(socket, waive: params["waive"] == "true")}
  end

  def handle_event("submit", %{"manual_appointment" => p}, socket) do
    case Booking.admin_create_booking(build_params(p)) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Appointment created.")
         |> push_navigate(to: ~p"/admin/dispatch")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not create appointment: #{inspect(reason)}")}
    end
  end

  defp build_params(p) do
    base = %{
      service_type_id: p["service_type_id"],
      scheduled_at: parse_dt(p["scheduled_at"]),
      technician_id: blank_to_nil(p["technician_id"]),
      notes: blank_to_nil(p["notes"]),
      waive_payment?: p["waive"] == "true",
      comp_reason: blank_to_nil(p["comp_reason"]),
      notify_client?: p["notify_client"] == "true"
    }

    base
    |> put_client(p)
    |> put_vehicle(p)
    |> put_address(p)
  end

  defp put_client(acc, %{"client_mode" => "existing"} = p),
    do: Map.put(acc, :customer_id, p["customer_id"])

  defp put_client(acc, p) do
    Map.put(acc, :new_customer, %{
      name: p["new_customer_name"],
      email: p["new_customer_email"],
      phone: p["new_customer_phone"]
    })
  end

  # Existing client + an existing vehicle selection uses vehicle_id; otherwise inline.
  defp put_vehicle(acc, %{"vehicle_id" => id}) when is_binary(id) and id != "",
    do: Map.put(acc, :vehicle_id, id)

  defp put_vehicle(acc, p) do
    Map.put(acc, :new_vehicle, %{
      make: p["vehicle_make"],
      model: p["vehicle_model"],
      size: String.to_existing_atom(p["vehicle_size"] || "car")
    })
  end

  defp put_address(acc, %{"address_id" => id}) when is_binary(id) and id != "",
    do: Map.put(acc, :address_id, id)

  defp put_address(acc, p) do
    Map.put(acc, :new_address, %{
      street: p["address_street"],
      city: p["address_city"],
      state: p["address_state"] || "TX",
      zip: p["address_zip"]
    })
  end

  defp parse_dt(value) when is_binary(value) and value != "" do
    {:ok, ndt} = NaiveDateTime.from_iso8601(value <> ":00")
    DateTime.from_naive!(ndt, "Etc/UTC")
  end

  defp parse_dt(_), do: nil

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(v), do: v

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto py-8 px-4">
      <h1 class="text-3xl font-bold mb-6">New Appointment</h1>

      <form id="manual-appointment-form" phx-submit="submit" class="space-y-4">
        <div class="join">
          <button type="button" class={["btn btn-sm join-item", @client_mode == "existing" && "btn-active"]}
                  phx-click="set_client_mode" phx-value-mode="existing">Existing client</button>
          <button type="button" class={["btn btn-sm join-item", @client_mode == "new" && "btn-active"]}
                  phx-click="set_client_mode" phx-value-mode="new">New client</button>
        </div>
        <input type="hidden" name="manual_appointment[client_mode]" value={@client_mode} />

        <div :if={@client_mode == "existing"}>
          <label class="label label-text">Client</label>
          <select name="manual_appointment[customer_id]" class="select select-bordered w-full">
            <option :for={c <- @customers} value={c.id}>{c.name} ({c.email})</option>
          </select>
        </div>

        <div :if={@client_mode == "new"} class="grid grid-cols-1 gap-2">
          <input name="manual_appointment[new_customer_name]" placeholder="Name" class="input input-bordered w-full" />
          <input name="manual_appointment[new_customer_email]" placeholder="Email" class="input input-bordered w-full" />
          <input name="manual_appointment[new_customer_phone]" placeholder="Phone" class="input input-bordered w-full" />
        </div>

        <div class="grid grid-cols-3 gap-2">
          <input name="manual_appointment[vehicle_make]" placeholder="Make" class="input input-bordered" />
          <input name="manual_appointment[vehicle_model]" placeholder="Model" class="input input-bordered" />
          <select name="manual_appointment[vehicle_size]" class="select select-bordered">
            <option value="car">Car</option>
            <option value="suv_van">SUV/Van</option>
            <option value="pickup">Pickup</option>
          </select>
        </div>

        <div class="grid grid-cols-2 gap-2">
          <input name="manual_appointment[address_street]" placeholder="Street" class="input input-bordered" />
          <input name="manual_appointment[address_city]" placeholder="City" class="input input-bordered" />
          <input name="manual_appointment[address_state]" value="TX" placeholder="State" class="input input-bordered" />
          <input name="manual_appointment[address_zip]" placeholder="ZIP" class="input input-bordered" />
        </div>

        <div class="grid grid-cols-2 gap-2">
          <select name="manual_appointment[service_type_id]" class="select select-bordered">
            <option :for={st <- @service_types} value={st.id}>{st.name}</option>
          </select>
          <input type="datetime-local" name="manual_appointment[scheduled_at]" required class="input input-bordered" />
        </div>

        <select name="manual_appointment[technician_id]" class="select select-bordered w-full">
          <option value="">No technician (assign later)</option>
          <option :for={t <- @technicians} value={t.id}>{t.name}</option>
        </select>

        <label class="label cursor-pointer justify-start gap-2">
          <input type="checkbox" name="manual_appointment[waive]" value="true" class="checkbox"
                 phx-click="toggle_waive" phx-value-waive={to_string(!@waive)} />
          <span class="label-text">Waive payment (comp)</span>
        </label>

        <input :if={@waive} name="manual_appointment[comp_reason]" required
               placeholder="Reason for comp" class="input input-bordered w-full" />

        <label class="label cursor-pointer justify-start gap-2">
          <input type="checkbox" name="manual_appointment[notify_client]" value="true" checked class="checkbox" />
          <span class="label-text">Notify client (confirmation + reminders)</span>
        </label>

        <button type="submit" class="btn btn-primary w-full">Create appointment</button>
      </form>
    </div>
    """
  end

  defp customers do
    Customer
    |> Ash.Query.filter(role in [:customer, :guest])
    |> Ash.Query.sort(name: :asc)
    |> Ash.read!(authorize?: false)
  end

  defp service_types, do: ServiceType |> Ash.read!(authorize?: false)

  defp technicians do
    Technician
    |> Ash.Query.filter(active == true)
    |> Ash.read!(authorize?: false)
  end
end
```

Note: the `waive` checkbox uses `toggle_waive` to reveal the required `comp_reason` field; on submit, `p["waive"] == "true"` drives the actual comp. The `notify_client` checkbox is checked by default (matches the "default on" decision).

- [ ] **Step 5: Run the test to verify it passes**

Run: `mix test test/mobile_car_wash_web/live/admin/manual_appointment_live_test.exs`
Expected: PASS (2 tests).

- [ ] **Step 6: Add the Dispatch entry point**

In `lib/mobile_car_wash_web/live/admin/dispatch_live.ex` render (or the command-bar region in `DispatchComponents`), add a link near the top controls:

```elixir
<.link navigate={~p"/admin/appointments/new"} class="btn btn-secondary btn-sm">+ New Appointment</.link>
```

- [ ] **Step 7: Format and commit**

```bash
mix format
git add lib/mobile_car_wash_web/live/admin/manual_appointment_live.ex \
        lib/mobile_car_wash_web/router.ex \
        lib/mobile_car_wash_web/live/admin/dispatch_live.ex \
        test/mobile_car_wash_web/live/admin/manual_appointment_live_test.exs
git commit -m "feat(admin): manual appointment form with comp + notify options"
```

---

## Task 7: Full-suite verification

**Files:** none (verification only).

- [ ] **Step 1: Run the full test suite**

Run: `mix test`
Expected: all green. Known-flaky `test/mobile_car_wash_web/controllers/api/v1/admin_blocks_controller_test.exs:40` — if it is the ONLY failure, re-run just that file once (`mix test test/.../admin_blocks_controller_test.exs`) to confirm it's the race, not a regression.

- [ ] **Step 2: Format check**

Run: `mix format --check-formatted`
Expected: no output (clean).

- [ ] **Step 3: Manual smoke (optional, dev server on port 4010)**

Boot the server and click through: create a block on the calendar, delete an empty one, confirm a booked block is locked; create a comped appointment for a new client and confirm it appears in Dispatch and a Payment row exists with `comped: true`, `collected_cents: 0`.

- [ ] **Step 4: Final review/merge**

Use `superpowers:requesting-code-review`, then `superpowers:finishing-a-development-branch` to integrate.

---

## Self-Review Notes

- **Spec coverage:** Payment comp fields + full-value/$0-collected (Task 1); `admin_book` confirmed standalone (Task 2); guarded delete "empty deletes, booked protected" (Task 3); orchestrator with existing-or-new client, inline vehicle/address, comp vs collected, notify toggle, transaction always recorded, cash-flow records collected only (Task 4); week-calendar add/delete UI (Task 5); manual-appointment form + Dispatch/calendar entry points (Task 6). All design sections map to a task.
- **Type consistency:** `admin_create_booking/1` return `{:ok, %{appointment:, payment:}}` is consumed only by the LiveView (ignores the shape beyond success). `Blocks.delete_block/1` `{:error, :block_has_appointments}` atom is matched identically in the LiveView and its test. `record_manual` accept list matches the orchestrator's changeset keys.
- **Deviations noted:** the manual-appointment surface is a dedicated `/admin/appointments/new` LiveView (linked from Dispatch and the calendar) rather than an in-page modal — functionally equivalent, simpler to test, honors "launched from Dispatch and the calendar."
