# Booking Redesign — Phase 2: Add-Ons — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an admin-managed à-la-carte **add-ons** menu (wax, interior shampoo, etc.) and a new booking-wizard step so the customer can grow their package, with the live price hero and the actual Stripe charge both reflecting the selected add-ons.

**Architecture:** A new `AddOn` Ash resource (admin-managed, mirrors `ServiceType`, no Stripe product needed). A new `:add_ons` step is inserted right after `:select_service`. The LiveView passes selected add-on ids into `Booking.create_booking`, which — inside its existing DB transaction — folds the flat add-on total into the authoritative `price_cents` (so the dynamic Stripe `unit_amount` charges correctly) and snapshots the selections into an `appointment_add_ons` join table. The hero's `compute_price_breakdown/1` builds `addon_lines` from the same selections, so display and charge agree.

**Tech Stack:** Elixir 1.18 / Phoenix 1.8 LiveView / Ash 3.x + AshPostgres / Tailwind v4.

## Global Constraints

- Money is always integer **cents**; format for display only (`Pricing.format_cents/1`).
- Add-ons are **flat-priced**: their total is **not** multiplied by vehicle size and **not** reduced by subscription/loyalty/referral discounts. They add on top of the (possibly discounted) service price.
- Pricing stays **server-authoritative**: `Booking.create_booking` computes the charged `price_cents` (service price through the existing subscription→loyalty→referral pipeline, **plus** the add-on total). The LiveView never sends a trusted price — only `add_on_ids`.
- The web/mobile Stripe charge uses a dynamic `unit_amount: appointment.price_cents` (verified in `StripeClient.create_checkout_session/3` and `create_mobile_payment_intent/2`), so **add-ons need NO Stripe product/price** — folding their total into `price_cents` is sufficient.
- The approved flow places `:add_ons` **immediately after `:select_service`**, before `:auth`: `select_service → add_ons → auth → vehicle → address → photos → schedule → review → confirmed`.
- Add-on selection is **optional** (forward guard always passes; default `[]`).
- Phoenix 1.8: components use the imported `<.icon name="hero-..."/>`; no inline `<script>`; LiveView templates begin with `<Layouts.app ...>` (already in place).
- Ash migrations are generated with `mix ash.codegen <name>` then applied with `mix ecto.migrate` (test DB: `MIX_ENV=test mix ecto.migrate`).
- TDD; `mix precommit` green before the phase is done. (Note: the suite has a known, pre-existing intermittent Ash "missed notifications" async flake unrelated to this work — re-run `mix test --failed` to confirm any lone failure is the flake.)

---

## File Structure

- **Create** `lib/mobile_car_wash/scheduling/add_on.ex` — admin-managed add-on catalog resource.
- **Create** `lib/mobile_car_wash/scheduling/appointment_add_on.ex` — join row (appointment ↔ add-on) with a price snapshot.
- **Modify** `lib/mobile_car_wash/scheduling/scheduling.ex` — register both new resources.
- **Modify** `lib/mobile_car_wash/scheduling/appointment.ex` — `has_many :appointment_add_ons`.
- **Modify** `lib/mobile_car_wash/billing/pricing.ex` — `addon_lines/1` + `addons_total_cents/1` pure helpers.
- **Test** `test/mobile_car_wash/billing/pricing_test.exs` — helper cases.
- **Modify** `lib/mobile_car_wash/scheduling/booking.ex` — accept `add_on_ids`, fold add-on total into `price_cents`, persist join rows in the transaction.
- **Test** `test/mobile_car_wash/scheduling/booking_addons_test.exs` — server pricing + persistence.
- **Modify** `lib/mobile_car_wash/booking/state_machine.ex` — insert `:add_ons`.
- **Test** `test/mobile_car_wash/booking/state_machine_test.exs` — new transitions.
- **Modify** `lib/mobile_car_wash_web/live/booking_live.ex` — load add-ons, `:add_ons` step UI, toggle handler, breakdown lines, context + persist/restore, pass `add_on_ids` to `create_booking`.
- **Modify** `lib/mobile_car_wash/catalog_broadcaster.ex` — `broadcast_add_ons_updated/0` + topic message.
- **Test** `test/mobile_car_wash_web/live/booking_addons_test.exs` — toggling updates hero; selection persists; booking carries add-ons.
- **Modify** `lib/mobile_car_wash_web/live/admin/settings_live.ex` — add-ons CRUD section.
- **Test** `test/mobile_car_wash_web/live/admin/settings_addons_test.exs` — admin create/toggle.
- **Modify** `priv/repo/seeds.exs` — starter add-on menu.

---

### Task 1: AddOn resource, domain registration, migration, seeds

**Files:**
- Create: `lib/mobile_car_wash/scheduling/add_on.ex`
- Modify: `lib/mobile_car_wash/scheduling/scheduling.ex`
- Modify: `priv/repo/seeds.exs`
- Test: `test/mobile_car_wash/scheduling/add_on_test.exs`

**Interfaces:**
- Produces: `MobileCarWash.Scheduling.AddOn` Ash resource with attributes
  `name` (string, required), `slug` (string, required, unique), `description`
  (string, nullable), `price_cents` (integer, required), `icon` (string,
  nullable — a hero icon name like `"sparkles"`), `active` (boolean, default
  true), `sort_order` (integer, default 0). Actions: `defaults([:read])`,
  `create :create` (primary) and `update :update` (primary) accepting
  `[:name, :slug, :description, :price_cents, :icon, :active, :sort_order]`.
  Identity `:unique_slug` on `[:slug]`. No Stripe sync.

- [ ] **Step 1: Write the failing test**

Create `test/mobile_car_wash/scheduling/add_on_test.exs`:

```elixir
defmodule MobileCarWash.Scheduling.AddOnTest do
  use MobileCarWash.DataCase, async: true

  alias MobileCarWash.Scheduling.AddOn

  test "creates an add-on with the expected fields" do
    addon =
      AddOn
      |> Ash.Changeset.for_create(:create, %{
        name: "Wax & Shine",
        slug: "wax_shine",
        description: "Hand wax",
        price_cents: 1_500,
        icon: "sparkles"
      })
      |> Ash.create!()

    assert addon.name == "Wax & Shine"
    assert addon.price_cents == 1_500
    assert addon.active == true
    assert addon.sort_order == 0
  end

  test "slug is unique" do
    attrs = %{name: "A", slug: "dup_addon", price_cents: 100}
    AddOn |> Ash.Changeset.for_create(:create, attrs) |> Ash.create!()

    assert {:error, _} =
             AddOn
             |> Ash.Changeset.for_create(:create, %{attrs | name: "B"})
             |> Ash.create()
  end
end
```

- [ ] **Step 2: Create the resource and register it**

Create `lib/mobile_car_wash/scheduling/add_on.ex` (mirrors `ServiceType`, no Stripe change):

```elixir
defmodule MobileCarWash.Scheduling.AddOn do
  @moduledoc """
  Optional à-la-carte add-on services (wax, interior shampoo, etc.) offered
  on top of a base service. Admin-managed. Flat-priced: the add-on total is
  added to the appointment charge without size multiplier or discount.
  """
  use Ash.Resource,
    otp_app: :mobile_car_wash,
    domain: MobileCarWash.Scheduling,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("add_ons")
    repo(MobileCarWash.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :name, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :slug, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :description, :string do
      public?(true)
    end

    attribute :price_cents, :integer do
      allow_nil?(false)
      public?(true)
    end

    attribute :icon, :string do
      public?(true)
      description("Hero icon name, e.g. \"sparkles\".")
    end

    attribute :active, :boolean do
      default(true)
      public?(true)
    end

    attribute :sort_order, :integer do
      default(0)
      public?(true)
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  identities do
    identity(:unique_slug, [:slug])
  end

  actions do
    defaults([:read])

    create :create do
      primary?(true)
      accept([:name, :slug, :description, :price_cents, :icon, :active, :sort_order])
    end

    update :update do
      primary?(true)
      accept([:name, :slug, :description, :price_cents, :icon, :active, :sort_order])
    end
  end
end
```

Then register it in `lib/mobile_car_wash/scheduling/scheduling.ex`, in the
`resources do ... end` block, right after the `ServiceType` line:

```elixir
    resource(MobileCarWash.Scheduling.AddOn)
```

- [ ] **Step 3: Generate and apply the migration**

Run:
```bash
mix ash.codegen create_add_ons
mix ecto.migrate
MIX_ENV=test mix ecto.migrate
```
Expected: a migration creating the `add_ons` table with a unique index on `slug`.

- [ ] **Step 4: Run the test to verify it passes**

Run: `mix test test/mobile_car_wash/scheduling/add_on_test.exs`
Expected: PASS (2 tests).

- [ ] **Step 5: Seed the starter add-on menu**

In `priv/repo/seeds.exs`, add `alias MobileCarWash.Scheduling.AddOn` near the
other aliases, and after the subscription-plans seed loop append:

```elixir
# --- Add-Ons ---

IO.puts("\nSeeding add-ons...")

for attrs <- [
      %{name: "Wax & Shine", slug: "wax_shine", price_cents: 1_500, icon: "sparkles", sort_order: 1, description: "Hand wax for a deep, protective shine."},
      %{name: "Interior Shampoo", slug: "interior_shampoo", price_cents: 2_500, icon: "sparkles", sort_order: 2, description: "Deep-clean carpets and upholstery."},
      %{name: "Pet Hair Removal", slug: "pet_hair_removal", price_cents: 1_000, icon: "sparkles", sort_order: 3, description: "Thorough removal of embedded pet hair."},
      %{name: "Engine Bay Clean", slug: "engine_bay_clean", price_cents: 2_000, icon: "sparkles", sort_order: 4, description: "Degrease and detail the engine bay."},
      %{name: "Headlight Restoration", slug: "headlight_restoration", price_cents: 3_000, icon: "sparkles", sort_order: 5, description: "Restore clouded headlights to clear."}
    ] do
  existing = AddOn |> Ash.Query.filter(slug == ^attrs.slug) |> Ash.read!()

  case existing do
    [] ->
      AddOn |> Ash.Changeset.for_create(:create, attrs) |> Ash.create!()
      IO.puts("  ✓ Created #{attrs.name}")

    [_] ->
      IO.puts("  - #{attrs.name} already exists, skipping")
  end
end
```

- [ ] **Step 6: Run seeds + commit**

Run: `mix run priv/repo/seeds.exs` (idempotent; should create 5 add-ons).
Then commit:
```bash
git add lib/mobile_car_wash/scheduling/add_on.ex lib/mobile_car_wash/scheduling/scheduling.ex priv/repo/migrations test/mobile_car_wash/scheduling/add_on_test.exs priv/repo/seeds.exs
git commit -m "feat: add AddOn catalog resource, migration, and seeds"
```

---

### Task 2: Server — persist add-ons & fold their total into the charge

**Files:**
- Create: `lib/mobile_car_wash/scheduling/appointment_add_on.ex`
- Modify: `lib/mobile_car_wash/scheduling/scheduling.ex` (register join)
- Modify: `lib/mobile_car_wash/scheduling/appointment.ex` (`has_many`)
- Modify: `lib/mobile_car_wash/billing/pricing.ex` (pure helpers)
- Test: `test/mobile_car_wash/billing/pricing_test.exs`
- Modify: `lib/mobile_car_wash/scheduling/booking.ex`
- Test: `test/mobile_car_wash/scheduling/booking_addons_test.exs`

**Interfaces:**
- Consumes: `AddOn` (Task 1); existing `Booking.create_booking/1`,
  `calculate_price/3`, `apply_loyalty_discount/3`, `maybe_apply_referral/3`,
  `create_appointment/4`.
- Produces:
  - `MobileCarWash.Scheduling.AppointmentAddOn` resource: `belongs_to
    :appointment` (allow_nil? false), `belongs_to :add_on` (allow_nil?
    false), `price_cents` (integer, required — snapshot). `create :create`
    accepting `[:appointment_id, :add_on_id, :price_cents]`.
  - `Pricing.addon_lines(add_ons :: [AddOn.t()]) :: [%{label, amount_cents}]`
    and `Pricing.addons_total_cents(add_ons :: [AddOn.t()]) :: integer`.
  - `Booking.create_booking/1` accepts `add_on_ids: [uuid]` (optional,
    default `[]`); folds `addons_total` into the charged `price_cents`; writes
    one `AppointmentAddOn` row per add-on (price snapshot) within the txn.

- [ ] **Step 1: Write the failing Pricing helper tests**

Add to `test/mobile_car_wash/billing/pricing_test.exs`:

```elixir
  describe "add-on helpers" do
    test "addons_total_cents sums flat add-on prices" do
      addons = [%{name: "Wax", price_cents: 1500}, %{name: "Pet", price_cents: 1000}]
      assert Pricing.addons_total_cents(addons) == 2500
      assert Pricing.addons_total_cents([]) == 0
    end

    test "addon_lines maps add-ons to label/amount line items" do
      addons = [%{name: "Wax", price_cents: 1500}]
      assert Pricing.addon_lines(addons) == [%{label: "Wax", amount_cents: 1500}]
    end
  end
```

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/mobile_car_wash/billing/pricing_test.exs`
Expected: FAIL — `Pricing.addons_total_cents/1` / `addon_lines/1` undefined.

- [ ] **Step 3: Implement the pure helpers**

Add to `lib/mobile_car_wash/billing/pricing.ex` before the final `end`:

```elixir
  @doc "Flat sum of add-on prices in cents (no size multiplier, no discount)."
  def addons_total_cents(add_ons) do
    Enum.sum(Enum.map(add_ons, & &1.price_cents))
  end

  @doc "Maps add-ons to receipt line items for the price breakdown."
  def addon_lines(add_ons) do
    Enum.map(add_ons, &%{label: &1.name, amount_cents: &1.price_cents})
  end
```

- [ ] **Step 4: Run to verify the helper tests pass**

Run: `mix test test/mobile_car_wash/billing/pricing_test.exs`
Expected: PASS.

- [ ] **Step 5: Create the join resource and register it**

Create `lib/mobile_car_wash/scheduling/appointment_add_on.ex`:

```elixir
defmodule MobileCarWash.Scheduling.AppointmentAddOn do
  @moduledoc """
  Join row linking an appointment to a selected add-on, capturing the
  add-on price at booking time so historical receipts stay correct even
  if the add-on's price later changes.
  """
  use Ash.Resource,
    otp_app: :mobile_car_wash,
    domain: MobileCarWash.Scheduling,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("appointment_add_ons")
    repo(MobileCarWash.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :price_cents, :integer do
      allow_nil?(false)
      public?(true)
    end

    create_timestamp(:inserted_at)
  end

  relationships do
    belongs_to :appointment, MobileCarWash.Scheduling.Appointment do
      allow_nil?(false)
    end

    belongs_to :add_on, MobileCarWash.Scheduling.AddOn do
      allow_nil?(false)
    end
  end

  actions do
    defaults([:read])

    create :create do
      primary?(true)
      accept([:appointment_id, :add_on_id, :price_cents])
    end
  end
end
```

Register in `lib/mobile_car_wash/scheduling/scheduling.ex` after the `AddOn` line:

```elixir
    resource(MobileCarWash.Scheduling.AppointmentAddOn)
```

Add the relationship to `lib/mobile_car_wash/scheduling/appointment.ex` in the
`relationships do ... end` block (after the existing `belongs_to`/`has_many`
entries):

```elixir
    has_many :appointment_add_ons, MobileCarWash.Scheduling.AppointmentAddOn
```

- [ ] **Step 6: Generate and apply the migration**

Run:
```bash
mix ash.codegen create_appointment_add_ons
mix ecto.migrate
MIX_ENV=test mix ecto.migrate
```
Expected: a migration creating `appointment_add_ons` with FKs to
`appointments` and `add_ons`.

- [ ] **Step 7: Write the failing server booking test**

Create `test/mobile_car_wash/scheduling/booking_addons_test.exs`. Mirror the
setup of the existing `test/mobile_car_wash/scheduling/booking_test.exs`
(read it first for how it builds a customer, vehicle, address, service, and
block, and how it calls `Booking.create_booking/1`). The new assertions:

```elixir
  test "folds add-on total into price and persists join rows", ctx do
    wax = add_on("wax_shine", 1_500)
    pet = add_on("pet_hair", 1_000)

    {:ok, %{appointment: appt}} =
      Booking.create_booking(base_params(ctx) |> Map.put(:add_on_ids, [wax.id, pet.id]))

    # Car basic wash $50 base + $25 add-ons = $75
    assert appt.price_cents == 7_500

    appt = Ash.load!(appt, :appointment_add_ons)
    assert length(appt.appointment_add_ons) == 2
    assert Enum.sort(Enum.map(appt.appointment_add_ons, & &1.price_cents)) == [1_000, 1_500]
  end

  test "no add_on_ids leaves price unchanged and creates no join rows", ctx do
    {:ok, %{appointment: appt}} = Booking.create_booking(base_params(ctx))
    assert appt.price_cents == 5_000
    appt = Ash.load!(appt, :appointment_add_ons)
    assert appt.appointment_add_ons == []
  end
```

(Provide `add_on/2` and `base_params/1` helpers in the test, matching the
existing booking test's param shape; `base_params` must include a car-sized
vehicle so the base price is exactly `5_000`.)

- [ ] **Step 8: Run to verify failure**

Run: `mix test test/mobile_car_wash/scheduling/booking_addons_test.exs`
Expected: FAIL — price is `5_000` (add-ons not folded) and no join rows.

- [ ] **Step 9: Implement the server fold + persistence**

In `lib/mobile_car_wash/scheduling/booking.ex`:

1. Extend the `@type booking_params` with `optional(:add_on_ids) => [String.t()]`.

2. In the `create_booking/1` `with` chain, after the discount pipeline
   computes the service `price_cents` and before `create_appointment`, load
   the add-ons and fold their total in. Replace the segment that currently
   reads:

```elixir
             {price_cents, discount_cents} =
               maybe_apply_referral(price_cents, discount_cents, params[:referral_code]),
             {:ok, appointment} <-
               create_appointment(params, service_type, price_cents, discount_cents),
```

   with:

```elixir
             {price_cents, discount_cents} =
               maybe_apply_referral(price_cents, discount_cents, params[:referral_code]),
             add_ons = load_add_ons(params[:add_on_ids]),
             price_cents = price_cents + MobileCarWash.Billing.Pricing.addons_total_cents(add_ons),
             {:ok, appointment} <-
               create_appointment(params, service_type, price_cents, discount_cents),
             :ok <- create_appointment_add_ons(appointment, add_ons),
```

3. Add the two private helpers (near the other `defp`s):

```elixir
  defp load_add_ons(nil), do: []
  defp load_add_ons([]), do: []

  defp load_add_ons(ids) do
    require Ash.Query

    MobileCarWash.Scheduling.AddOn
    |> Ash.Query.filter(id in ^ids)
    |> Ash.read!()
  end

  defp create_appointment_add_ons(_appointment, []), do: :ok

  defp create_appointment_add_ons(appointment, add_ons) do
    Enum.each(add_ons, fn add_on ->
      MobileCarWash.Scheduling.AppointmentAddOn
      |> Ash.Changeset.for_create(:create, %{
        appointment_id: appointment.id,
        add_on_id: add_on.id,
        price_cents: add_on.price_cents
      })
      |> Ash.create!()
    end)

    :ok
  end
```

Note: folding add-ons in **before** `create_appointment` keeps the existing
`appointment.price_cents == 0` subscription-covered auto-confirm branch
correct — a subscriber who adds add-ons has `price_cents > 0` and is routed
to checkout for the add-on amount.

- [ ] **Step 10: Run to verify the server tests pass**

Run: `mix test test/mobile_car_wash/scheduling/booking_addons_test.exs test/mobile_car_wash/scheduling/booking_test.exs`
Expected: PASS (new add-on tests + existing booking tests unaffected).

- [ ] **Step 11: Commit**

```bash
git add lib/mobile_car_wash/scheduling/appointment_add_on.ex lib/mobile_car_wash/scheduling/scheduling.ex lib/mobile_car_wash/scheduling/appointment.ex lib/mobile_car_wash/billing/pricing.ex test/mobile_car_wash/billing/pricing_test.exs lib/mobile_car_wash/scheduling/booking.ex test/mobile_car_wash/scheduling/booking_addons_test.exs priv/repo/migrations
git commit -m "feat: charge and persist booking add-ons server-side"
```

---

### Task 3: State machine — insert the `:add_ons` step

**Files:**
- Modify: `lib/mobile_car_wash/booking/state_machine.ex`
- Test: `test/mobile_car_wash/booking/state_machine_test.exs`

**Interfaces:**
- Produces: `:add_ons` step between `:select_service` and `:auth`. Optional
  forward guard; `can_be_on?(:add_ons, ctx)` requires a selected service.
  `selected_add_ons` is part of the context map (list).

- [ ] **Step 1: Write the failing tests**

Add to `test/mobile_car_wash/booking/state_machine_test.exs`:

```elixir
  describe "transition with :add_ons step" do
    test "select_service advances to :add_ons" do
      ctx = context_with(%{selected_service: service()})
      assert {:ok, :add_ons} = StateMachine.transition(:forward, :select_service, ctx)
    end

    test ":add_ons advances to :auth when no customer" do
      ctx = context_with(%{selected_service: service()})
      assert {:ok, :auth} = StateMachine.transition(:forward, :add_ons, ctx)
    end

    test ":add_ons skips :auth straight to :vehicle when customer present" do
      ctx = context_with(%{selected_service: service(), current_customer: customer()})
      assert {:ok, :vehicle} = StateMachine.transition(:forward, :add_ons, ctx)
    end

    test ":add_ons is optional — forward always allowed with a service" do
      ctx = context_with(%{selected_service: service()})
      assert {:ok, :auth} = StateMachine.transition(:forward, :add_ons, ctx)
    end

    test "back from :auth returns to :add_ons" do
      ctx = context_with(%{selected_service: service()})
      assert {:ok, :add_ons} = StateMachine.transition(:back, :auth, ctx)
    end

    test "back from :vehicle returns to :add_ons when customer present (auth skipped)" do
      ctx = context_with(%{selected_service: service(), current_customer: customer()})
      assert {:ok, :add_ons} = StateMachine.transition(:back, :vehicle, ctx)
    end
  end
```

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/mobile_car_wash/booking/state_machine_test.exs`
Expected: FAIL — `select_service` still advances to `:auth`, no `:add_ons`.

- [ ] **Step 3: Edit the state machine**

In `lib/mobile_car_wash/booking/state_machine.ex`:

1. `@steps` — insert `:add_ons` after `:select_service`:
```elixir
  @steps [:select_service, :add_ons, :auth, :vehicle, :address, :photos, :schedule, :review, :confirmed]
```

2. The `@type step` union — add `| :add_ons` after `:select_service`.

3. `can_be_on?` — add after the `:select_service` clause:
```elixir
  def can_be_on?(:add_ons, ctx), do: present?(ctx, :selected_service)
```

4. `validate_forward_guard` — add (optional step, always passes):
```elixir
  defp validate_forward_guard(:add_ons, _ctx), do: :ok
```

5. `raw_next` — change the `:select_service` clause and add `:add_ons`:
```elixir
  defp raw_next(:select_service), do: {:ok, :add_ons}
  defp raw_next(:add_ons), do: {:ok, :auth}
```

6. `raw_prev` — change the `:auth` clause and add `:add_ons`:
```elixir
  defp raw_prev(:auth), do: {:ok, :add_ons}
  defp raw_prev(:add_ons), do: {:ok, :select_service}
```

7. `maybe_skip` — the back-skip when a customer is present must now land on
   `:add_ons` instead of `:select_service`. Change:
```elixir
  defp maybe_skip(:auth, :back, ctx) when ctx.current_customer != nil, do: {:ok, :add_ons}
```

- [ ] **Step 4: Run to verify the tests pass**

Run: `mix test test/mobile_car_wash/booking/state_machine_test.exs`
Expected: PASS (new + existing transition tests).

- [ ] **Step 5: Commit**

```bash
git add lib/mobile_car_wash/booking/state_machine.ex test/mobile_car_wash/booking/state_machine_test.exs
git commit -m "feat: insert optional :add_ons step after service selection"
```

---

### Task 4: BookingLive — `:add_ons` step UI and wiring

**Files:**
- Modify: `lib/mobile_car_wash_web/live/booking_live.ex`
- Modify: `lib/mobile_car_wash/catalog_broadcaster.ex`
- Test: `test/mobile_car_wash_web/live/booking_addons_test.exs`

**Interfaces:**
- Consumes: `AddOn` read; `Pricing.addon_lines/1`; the state machine `:add_ons`
  step; `CatalogBroadcaster`.
- Produces: socket assigns `:available_add_ons` (list, loaded at mount) and
  `:selected_add_ons` (list, default `[]`); a `"toggle_add_on"` event handler
  keyed by add-on id; an `:add_ons` step render block; `selected_add_ons` in
  `build_context/1`, persisted as `addon_ids` in `persist_booking_state/1`
  and restored in `restore_from_cache/1`; `compute_price_breakdown/1` builds
  `addon_lines` from `selected_add_ons`; `confirm_booking` passes
  `add_on_ids` into `Booking.create_booking/1`.

- [ ] **Step 1: Add the broadcaster message**

In `lib/mobile_car_wash/catalog_broadcaster.ex` add:
```elixir
  def broadcast_add_ons_updated do
    PubSub.broadcast(@pubsub, @topic, :add_ons_updated)
  end
```

- [ ] **Step 2: Write the failing LiveView test**

Create `test/mobile_car_wash_web/live/booking_addons_test.exs`:

```elixir
defmodule MobileCarWashWeb.BookingAddonsTest do
  use MobileCarWashWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias MobileCarWash.Scheduling.{ServiceType, AddOn}

  setup do
    ServiceType
    |> Ash.Changeset.for_create(:create, %{
      name: "Basic Wash", slug: "basic_wash", description: "x",
      base_price_cents: 5_000, duration_minutes: 45
    })
    |> Ash.create!()

    AddOn
    |> Ash.Changeset.for_create(:create, %{
      name: "Wax & Shine", slug: "wax_shine", price_cents: 1_500, icon: "sparkles"
    })
    |> Ash.create!()

    :ok
  end

  test "add-ons step lists add-ons and toggling one raises the hero total", %{conn: conn} do
    {:ok, view, _} = live(conn, "/book")
    render_click(view, "select_service", %{"slug" => "basic_wash"})

    html = render_click(view, "next_step", %{})
    assert html =~ "Wax &amp; Shine"
    # base only so far
    assert html =~ "$50.00"

    addon = MobileCarWash.Scheduling.AddOn |> Ash.read!() |> hd()
    html = render_click(view, "toggle_add_on", %{"id" => addon.id})

    # base + wax
    assert html =~ "$65.00"
  end
end
```

- [ ] **Step 3: Run to verify failure**

Run: `mix test test/mobile_car_wash_web/live/booking_addons_test.exs`
Expected: FAIL — no `:add_ons` step / `toggle_add_on` handler; total stays $50.

- [ ] **Step 4: Load add-ons at mount + initialize selection**

In `mount/3` in `lib/mobile_car_wash_web/live/booking_live.ex`:
- Load active add-ons near where `services` is loaded:
```elixir
    add_ons =
      MobileCarWash.Scheduling.AddOn
      |> Ash.Query.filter(active == true)
      |> Ash.read!()
      |> Enum.sort_by(& &1.sort_order)
```
- Add to `base_assigns`: `selected_add_ons: restored_assigns[:selected_add_ons] || []`.
- Add to the main `assign(...)` block: `available_add_ons: add_ons,` and
  `selected_add_ons: base_assigns.selected_add_ons,`.

Also add a `handle_info(:add_ons_updated, ...)` clause mirroring the existing
`:services_updated` clause, reloading `available_add_ons`.

- [ ] **Step 5: Add the toggle handler**

Add near the other `handle_event/3` clauses:
```elixir
  def handle_event("toggle_add_on", %{"id" => id}, socket) do
    add_on = Enum.find(socket.assigns.available_add_ons, &(&1.id == id))

    selected =
      if Enum.any?(socket.assigns.selected_add_ons, &(&1.id == id)) do
        Enum.reject(socket.assigns.selected_add_ons, &(&1.id == id))
      else
        socket.assigns.selected_add_ons ++ [add_on]
      end

    socket =
      socket
      |> assign(selected_add_ons: selected)
      |> assign_price_breakdown()
      |> persist_booking_state()

    {:noreply, socket}
  end
```

- [ ] **Step 6: Build addon_lines in the breakdown**

In `compute_price_breakdown/1`, replace `addon_lines: []` with:
```elixir
      addon_lines: Pricing.addon_lines(assigns[:selected_add_ons] || []),
```

- [ ] **Step 7: Render the `:add_ons` step**

Add a step block immediately after the `:select_service` block (before
`:auth`). Toggle cards reflect selection; each fires `toggle_add_on`:
```heex
<div :if={@current_step == :add_ons}>
  <div class="mb-6">
    <h1 class="text-2xl font-bold text-base-content tracking-tight">Make it shine</h1>
    <p class="text-sm text-base-content/70 mt-1">Optional add-ons — tap to include.</p>
  </div>

  <div class="space-y-2">
    <button
      :for={addon <- @available_add_ons}
      type="button"
      phx-click="toggle_add_on"
      phx-value-id={addon.id}
      class={[
        "w-full flex items-center justify-between rounded-box border p-4 text-left transition",
        Enum.any?(@selected_add_ons, &(&1.id == addon.id)) && "border-success bg-success/10",
        !Enum.any?(@selected_add_ons, &(&1.id == addon.id)) && "border-base-300"
      ]}
    >
      <span class="flex items-center gap-3">
        <.icon name="hero-sparkles" class="size-5 text-base-content/60" />
        <span>
          <span class="block font-semibold text-base-content">{addon.name}</span>
          <span :if={addon.description} class="block text-xs text-base-content/60">{addon.description}</span>
        </span>
      </span>
      <span class="font-semibold text-base-content">+{Pricing.format_cents(addon.price_cents)}</span>
    </button>
  </div>

  <div class="flex justify-between mt-6">
    <button class="btn btn-ghost" phx-click="prev_step">Back</button>
    <button class="btn btn-primary" phx-click="next_step">Continue</button>
  </div>
</div>
```

- [ ] **Step 8: Thread selection through context, persistence, and booking**

- In `build_context/1`, add: `selected_add_ons: assigns[:selected_add_ons]`.
- In `persist_booking_state/1`, add to the cached map:
  `addon_ids: Enum.map(socket.assigns.selected_add_ons || [], & &1.id)`.
- In `restore_from_cache/1`, load add-ons from `cached[:addon_ids]` (reuse the
  file's existing `safe_get/2`-style loader; reject nils) and put
  `selected_add_ons: add_ons` into the restored assigns map.
- In the `confirm_booking` handler, where `Booking.create_booking/1` params
  are assembled, add:
  `add_on_ids: Enum.map(socket.assigns.selected_add_ons || [], & &1.id)`.

- [ ] **Step 9: Run the booking suites**

Run: `mix test test/mobile_car_wash_web/live/booking_addons_test.exs test/mobile_car_wash_web/live/ test/features/customer_booking_test.exs`
Expected: PASS (new add-ons test + no regressions; the `:add_ons` step shifts
the wizard but existing tests drive events, not fixed step counts).

- [ ] **Step 10: Commit**

```bash
git add lib/mobile_car_wash_web/live/booking_live.ex lib/mobile_car_wash/catalog_broadcaster.ex test/mobile_car_wash_web/live/booking_addons_test.exs
git commit -m "feat: add-ons booking step with live price + persistence"
```

---

### Task 5: Admin — manage the add-on menu

**Files:**
- Modify: `lib/mobile_car_wash_web/live/admin/settings_live.ex`
- Test: `test/mobile_car_wash_web/live/admin/settings_addons_test.exs`

**Interfaces:**
- Consumes: `AddOn` resource; `CatalogBroadcaster.broadcast_add_ons_updated/0`.
- Produces: an "Add-Ons" section in the admin settings page — list active/
  inactive add-ons, create a new one, and toggle active. Mirrors the existing
  services CRUD in this LiveView.

- [ ] **Step 1: Write the failing admin test**

Read `test/mobile_car_wash_web/live/admin/` for the existing admin-auth setup
(how a test signs in an admin and mounts `/admin/settings`), then create
`test/mobile_car_wash_web/live/admin/settings_addons_test.exs` following that
pattern. Assertions:

```elixir
  test "admin can create an add-on", %{conn: conn} do
    {:ok, view, _} = live(conn, "/admin/settings")

    view
    |> form("#add-on-form", add_on: %{name: "Clay Bar", slug: "clay_bar", price_cents: "2000"})
    |> render_submit()

    assert MobileCarWash.Scheduling.AddOn
           |> Ash.read!()
           |> Enum.any?(&(&1.slug == "clay_bar"))
  end
```

(Match the actual form id and field names you introduce in Step 3; if the
existing services form converts dollars→cents via a `dollars_to_cents/1`
helper, reuse it and submit a dollar string instead.)

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/mobile_car_wash_web/live/admin/settings_addons_test.exs`
Expected: FAIL — no add-on form / section.

- [ ] **Step 3: Implement the add-ons section**

In `lib/mobile_car_wash_web/live/admin/settings_live.ex`, mirroring the
existing services CRUD:
- `mount/3`: load `add_ons` via a `load_add_ons/0` helper; assign them.
- Handlers: `add_add_on` (create from form attrs, broadcast
  `broadcast_add_ons_updated/0`, reload), `toggle_add_on` (flip `active`,
  broadcast, reload). Reuse the file's `dollars_to_cents/1`/`to_int/1` helpers
  for price parsing.
- Template: an "Add-Ons" card listing existing add-ons (name, price, active
  toggle) and a create form (`#add-on-form`) with name, slug, price, icon.

- [ ] **Step 4: Run to verify the admin test passes**

Run: `mix test test/mobile_car_wash_web/live/admin/settings_addons_test.exs`
Expected: PASS.

- [ ] **Step 5: Full precommit + commit**

Run: `mix precommit`
Expected: green (a lone async flake may appear — re-run `mix test --failed` to confirm it is the known pre-existing "missed notifications" flake, not this change).

```bash
git add lib/mobile_car_wash_web/live/admin/settings_live.ex test/mobile_car_wash_web/live/admin/settings_addons_test.exs
git commit -m "feat: admin add-on menu management"
```

---

## Self-Review

- **Spec coverage:** admin-managed add-ons resource ✓ (Task 1, 5); add-ons own
  step after service ✓ (Task 3, 4); flat pricing folded into the charge
  server-authoritatively ✓ (Task 2); hero reflects add-ons live ✓ (Task 4 +
  `Pricing.addon_lines`); price snapshot for history ✓ (`AppointmentAddOn`);
  starter menu seeded + editable ✓ (Task 1, 5). No Stripe products needed —
  justified by the dynamic `unit_amount` checkout (Global Constraints).
- **Placeholders:** new files carry complete code. Edits to large existing
  files (`booking_live.ex`, `booking.ex`, `settings_live.ex`,
  `state_machine.ex`, `appointment.ex`, `scheduling.ex`, `seeds.exs`,
  `pricing.ex`) are anchored against named clauses/blocks with the exact code
  to insert; Tasks 2/4/5 instruct reading the cited sibling pattern
  (existing booking test, services CRUD, admin-auth test setup) before
  mirroring — necessary because those helpers/ids are local to files the
  implementer must follow rather than reinvent.
- **Type consistency:** add-on line item shape `%{label, amount_cents}`
  matches `Pricing.breakdown/1`'s `addon_lines` contract from Phase 1.
  `selected_add_ons`/`available_add_ons` are lists of `AddOn` structs
  throughout; persistence uses `addon_ids` (uuid list); server takes
  `add_on_ids`. `addons_total_cents/1` and `addon_lines/1` both read
  `.price_cents`/`.name` from `AddOn`.

## Notes for later phases (not part of this plan)

- The review step + technician/admin views may want to *display* the selected
  add-ons (they're persisted via `appointment_add_ons`); surfacing them in
  those UIs is follow-on polish, not required for charging correctly.
- Phase 3 (NHTSA vehicle) and Phase 4 (geocoder address) are unaffected by
  this work and remain separately planned.
