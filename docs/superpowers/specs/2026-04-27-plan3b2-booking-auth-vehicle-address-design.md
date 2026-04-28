# Plan 3b-2 — Booking Page :auth, :vehicle, :address Step Rewrites

**Date:** 2026-04-27
**Status:** Draft (pending user review)
**Parent spec:** [2026-04-26-phase1-redesign-and-wallaby-design.md](2026-04-26-phase1-redesign-and-wallaby-design.md) — see "Customer-facing redesigns" section
**Sibling specs:** [Plan 3b-1](2026-04-27-plan3b1-booking-components-simple-steps-design.md), Plan 3b-3 (TBD)
**Author:** Brainstormed with Claude

---

## TL;DR

Second of three Plan-3b sub-plans. Rewrites the three sub-flow-heavy step templates in `booking_live.ex`: `:auth`, `:vehicle`, `:address`. Adds one new shared component (`<.saved_record_card>`) used by both vehicle and address lists. Auth flow is reorganized as guest-first with a small "have an account?" secondary card below. Vehicle/address steps auto-show the add-new form when the user has zero saved records, otherwise show a list with a toggle button.

State machine, all event handlers, mount/3 / load_step_data — **untouched**. Only template markup and one new component.

The `:photos` and `:review` steps, plus mobile sticky CTA and Stripe Elements styling, are deferred to **Plan 3b-3**.

---

## Scope

### In scope

- **New `<.saved_record_card>` component** in `MobileCarWashWeb.BookingComponents` — generic title/subtitle card with `:selected` highlight, used by both vehicle and address lists. ~3 unit tests.
- **Rewrite 3 step templates** in `lib/mobile_car_wash_web/live/booking_live.ex`:
  - `:auth` — guest checkout form primary, sign-in/create-account secondary (Q3-A locked)
  - `:vehicle` — saved vehicles list using `<.saved_record_card>` + add-new form (auto-show if zero records, toggle when ≥1)
  - `:address` — same pattern for addresses
- Update existing booking tests if any assert on old auth/vehicle/address markup

### Explicitly out of scope (deferred)

- `:photos` / `:review` step rewrites → **Plan 3b-3**
- Mobile sticky CTA pattern → Plan 3b-3
- Stripe Elements styling → Plan 3b-3
- BookingStateMachine logic — never
- Event handler changes — never
- Standalone `/sign-in` page redesign — phase-2
- Address autocomplete (Google Places) — separate future spec
- Vehicle make/model database autocomplete — separate future spec
- Phone normalization (E.164) — already handled in handlers per project memory

---

## File architecture

| Action | Path | Notes |
|---|---|---|
| Modify | `lib/mobile_car_wash_web/live/components/booking_components.ex` | Add `<.saved_record_card>` (1 new component) |
| Modify | `lib/mobile_car_wash_web/live/booking_live.ex` | Rewrite `:auth`, `:vehicle`, `:address` step blocks |
| Modify | `test/mobile_car_wash_web/live/components/booking_components_test.exs` | Add 3 tests for `saved_record_card/1` |
| Modify (if needed) | existing booking-related test files | Assertion updates for changed markup |

### Constraints honored

- All ~1056 tests stay green (some existing assertions may need updates)
- All event handlers, state machine, mount/3 / handle_params/3 / load_step_data preserved
- Existing socket assigns preserved: `@current_customer`, `@guest_error`, `@existing_vehicles`, `@selected_vehicle`, `@show_new_vehicle_form`, `@existing_addresses`, `@selected_address`, `@show_new_address_form`
- The 5 OTHER step blocks (`:select_service` / `:schedule` / `:photos` / `:review` / `:confirmed`) untouched

---

## Locked design decisions

| Question | Choice |
|---|---|
| Saved-record card pattern | Shared `<.saved_record_card>` component (used by vehicle + address) |
| Add-new form UX | Auto-show form when zero saved records; show toggle when ≥1 |
| `:auth` step priority | Guest-first (primary card); sign-in below as small secondary card |

---

## `<.saved_record_card>` component

### API

```elixir
attr :title, :string, required: true
attr :subtitle, :string, default: nil
attr :selected, :boolean, default: false
attr :rest, :global, include: ~w(phx-click phx-value-id)
```

### Render

```heex
<div
  class={[
    "relative bg-base-100 rounded-box p-4 cursor-pointer transition-shadow hover:shadow-md",
    if(@selected, do: "border-2 border-cyan-500", else: "border border-base-300")
  ]}
  {@rest}
>
  <div
    :if={@selected}
    class="absolute top-3 right-3 w-6 h-6 bg-cyan-500 text-white rounded-full flex items-center justify-center text-sm font-bold"
  >
    ✓
  </div>
  <div class="font-semibold text-base-content">{@title}</div>
  <div :if={@subtitle} class="text-sm text-base-content/60 mt-0.5">{@subtitle}</div>
</div>
```

### Tests

```elixir
describe "saved_record_card/1" do
  test "renders title and subtitle" do
    assigns = %{}
    html = rendered_to_string(~H|<.saved_record_card title="2023 Tesla Model 3" subtitle="Silver · car" />|)
    assert html =~ "2023 Tesla Model 3"
    assert html =~ "Silver · car"
  end

  test "selected state shows cyan border and check badge" do
    assigns = %{}
    html = rendered_to_string(~H|<.saved_record_card title="X" selected={true} />|)
    assert html =~ "border-cyan-500"
    assert html =~ "✓"
  end

  test "passes through phx-click and phx-value-id to root element" do
    assigns = %{}
    html = rendered_to_string(~H|<.saved_record_card title="X" phx-click="select_vehicle" phx-value-id="abc-123" />|)
    assert html =~ ~s(phx-click="select_vehicle")
    assert html =~ ~s(phx-value-id="abc-123")
  end
end
```

### Mirrors `<.service_card>`

The selected-state visual (cyan border + ✓ badge top-right) is identical to `<.service_card>` from Plan 3b-1. This gives the user a recognizable "selectable" pattern across booking steps.

---

## Step template rewrites

### `:auth`

```heex
<div :if={@current_step == :auth}>
  <div class="mb-6">
    <h1 class="text-2xl font-bold text-base-content tracking-tight">
      How would you like to continue?
    </h1>
  </div>

  <%!-- Already signed in --%>
  <div :if={@current_customer}>
    <div class="bg-success/10 border border-success/30 rounded-box p-4 mb-6">
      <div class="text-sm font-semibold text-success">
        Welcome back, {@current_customer.name}!
      </div>
    </div>
    <div class="flex justify-end">
      <button class="btn btn-primary" phx-click="next_step">Continue</button>
    </div>
  </div>

  <%!-- Guest path (primary) + sign-in path (secondary) --%>
  <div :if={!@current_customer} class="space-y-6">
    <div class="bg-base-100 border border-base-300 rounded-box p-5">
      <h2 class="text-lg font-semibold text-base-content mb-1">Continue as guest</h2>
      <p class="text-sm text-base-content/70 mb-4">
        No account needed. Just your contact info and we'll get you booked.
      </p>

      <div :if={@guest_error} class="bg-error/10 border border-error/30 rounded-lg p-3 mb-4 text-sm text-error">
        {@guest_error}
      </div>

      <form phx-submit="guest_checkout" class="space-y-3">
        <.input name="guest[name]" type="text" label="Name" placeholder="Your full name" required />
        <.input name="guest[email]" type="email" label="Email" placeholder="your@email.com" required />
        <.input name="guest[phone]" type="tel" label="Phone" placeholder="512-555-0100" />
        <button type="submit" class="btn btn-primary w-full mt-2">
          Continue as guest
        </button>
      </form>
    </div>

    <div class="bg-base-200 rounded-box p-4">
      <div class="flex items-center justify-between gap-4">
        <div>
          <div class="text-sm font-semibold text-base-content">Have an account?</div>
          <div class="text-xs text-base-content/60 mt-0.5">
            Sign in to use saved vehicles and addresses.
          </div>
        </div>
        <.link navigate={~p"/sign-in"} class="btn btn-ghost btn-sm">
          Sign in
        </.link>
      </div>
    </div>
  </div>
</div>
```

If `/sign-in` route doesn't exist, drop the `<.link>` block (or replace with placeholder href + TODO comment) — same approach as Plan 3a.

### `:vehicle`

```heex
<div :if={@current_step == :vehicle}>
  <div class="mb-6">
    <h1 class="text-2xl font-bold text-base-content tracking-tight">Your vehicle</h1>
    <p class="text-sm text-base-content/60 mt-1">
      Pick a saved vehicle, or add a new one.
    </p>
  </div>

  <%!-- Saved vehicles list --%>
  <div :if={@existing_vehicles != []} class="space-y-3 mb-6">
    <.saved_record_card
      :for={vehicle <- @existing_vehicles}
      title={"#{vehicle.year} #{vehicle.make} #{vehicle.model}"}
      subtitle={"#{vehicle.color} · #{vehicle.size}"}
      selected={@selected_vehicle && @selected_vehicle.id == vehicle.id}
      phx-click="select_vehicle"
      phx-value-id={vehicle.id}
    />
  </div>

  <%!-- "Add New" toggle button (only when ≥1 saved records) --%>
  <button
    :if={@existing_vehicles != [] and !@show_new_vehicle_form}
    class="btn btn-outline btn-sm mb-6"
    phx-click="show_new_vehicle"
  >
    + Add new vehicle
  </button>

  <%!-- Add-new form: auto-shown when no records, OR when toggle is on --%>
  <form
    :if={@existing_vehicles == [] or @show_new_vehicle_form}
    phx-submit="save_vehicle"
    class="bg-base-100 border border-base-300 rounded-box p-5 space-y-3 mb-6"
  >
    <div :if={@existing_vehicles == []} class="text-sm font-semibold text-base-content">
      Add your vehicle
    </div>
    <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
      <.input name="vehicle[make]" type="text" label="Make" placeholder="Toyota" required />
      <.input name="vehicle[model]" type="text" label="Model" placeholder="Camry" required />
    </div>
    <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
      <.input name="vehicle[year]" type="number" label="Year" placeholder="2024" />
      <.input name="vehicle[color]" type="text" label="Color" placeholder="Silver" />
    </div>

    <div>
      <label class="text-sm font-semibold text-base-content mb-2 block">Vehicle type</label>
      <div class="grid grid-cols-1 sm:grid-cols-3 gap-2">
        <label class="cursor-pointer border border-base-300 rounded-lg p-3 hover:border-cyan-500 has-[:checked]:border-cyan-500 has-[:checked]:bg-cyan-50 transition-colors">
          <input type="radio" name="vehicle[size]" value="car" class="sr-only" checked />
          <div class="text-sm font-semibold">Car</div>
          <div class="text-xs text-base-content/60">Sedan, coupe, compact</div>
        </label>
        <label class="cursor-pointer border border-base-300 rounded-lg p-3 hover:border-cyan-500 has-[:checked]:border-cyan-500 has-[:checked]:bg-cyan-50 transition-colors">
          <input type="radio" name="vehicle[size]" value="suv_van" class="sr-only" />
          <div class="text-sm font-semibold">SUV / Van</div>
          <div class="text-xs text-warning">+20% price</div>
        </label>
        <label class="cursor-pointer border border-base-300 rounded-lg p-3 hover:border-cyan-500 has-[:checked]:border-cyan-500 has-[:checked]:bg-cyan-50 transition-colors">
          <input type="radio" name="vehicle[size]" value="pickup" class="sr-only" />
          <div class="text-sm font-semibold">Pickup</div>
          <div class="text-xs text-warning">+50% price</div>
        </label>
      </div>
    </div>

    <button type="submit" class="btn btn-primary w-full">Save vehicle</button>
  </form>

  <div :if={@selected_vehicle} class="flex justify-end">
    <button class="btn btn-primary" phx-click="next_step">Continue</button>
  </div>
</div>
```

Uses Tailwind 3.4+ `has-[:checked]` selector for radio card highlighting.

### `:address`

```heex
<div :if={@current_step == :address}>
  <div class="mb-6">
    <h1 class="text-2xl font-bold text-base-content tracking-tight">Service location</h1>
    <p class="text-sm text-base-content/60 mt-1">
      Pick a saved address, or add a new one.
    </p>
  </div>

  <%!-- Saved addresses list --%>
  <div :if={@existing_addresses != []} class="space-y-3 mb-6">
    <.saved_record_card
      :for={addr <- @existing_addresses}
      title={addr.street}
      subtitle={"#{addr.city}, #{addr.state} #{addr.zip}"}
      selected={@selected_address && @selected_address.id == addr.id}
      phx-click="select_address"
      phx-value-id={addr.id}
    />
  </div>

  <%!-- "Add New" toggle button (only when ≥1 saved records) --%>
  <button
    :if={@existing_addresses != [] and !@show_new_address_form}
    class="btn btn-outline btn-sm mb-6"
    phx-click="show_new_address"
  >
    + Add new address
  </button>

  <%!-- Add-new form --%>
  <form
    :if={@existing_addresses == [] or @show_new_address_form}
    phx-submit="save_address"
    class="bg-base-100 border border-base-300 rounded-box p-5 space-y-3 mb-6"
  >
    <div :if={@existing_addresses == []} class="text-sm font-semibold text-base-content">
      Where should we come?
    </div>
    <.input name="address[street]" type="text" label="Street address" placeholder="123 Main St" required />
    <div class="grid grid-cols-1 sm:grid-cols-3 gap-3">
      <.input name="address[city]" type="text" label="City" placeholder="San Antonio" required />
      <.input name="address[state]" type="text" label="State" value="TX" required />
      <.input name="address[zip]" type="text" label="ZIP" placeholder="78261" required />
    </div>
    <button type="submit" class="btn btn-primary w-full">Save address</button>
  </form>

  <%!-- Zone indicator (preserved from existing) --%>
  <div :if={@selected_address && @selected_address.zone} class="bg-info/10 border border-info/30 rounded-lg p-3 mb-4 text-sm text-info">
    Service zone: {@selected_address.zone}
  </div>

  <div :if={@selected_address} class="flex justify-end">
    <button class="btn btn-primary" phx-click="next_step">Continue</button>
  </div>
</div>
```

### What stays

- All `phx-click`, `phx-submit`, `phx-value-id` wiring preserved
- All socket assigns preserved (per "Constraints honored" above)
- All event handlers (`guest_checkout`, `select_vehicle`, `save_vehicle`, `show_new_vehicle`, `select_address`, `save_address`, `show_new_address`, `next_step`) — untouched
- The 5 OTHER step blocks (`:select_service` / `:schedule` / `:photos` / `:review` / `:confirmed`) — untouched

---

## Mobile behavior

Tailwind breakpoints — `sm` 640.

| Region | Mobile rule |
|---|---|
| `:auth` guest form | Single-column; Sign-in card stacks below |
| `:vehicle` saved cards | Stack vertically, full-width |
| `:vehicle` make/model row | 2-col → 1-col stack at `sm` |
| `:vehicle` year/color row | 2-col → 1-col stack at `sm` |
| `:vehicle` size selector | 3-col radio grid → 1-col stack at `sm` |
| `:address` saved cards | Stack vertically |
| `:address` city/state/zip row | 3-col → 1-col stack at `sm` |
| Continue button | Right-aligned desktop; left as-is on mobile (sticky CTA deferred to 3b-3) |

**Touch targets:** all primary actions ≥44×44px.

---

## Risks

1. **`has-[:checked]` Tailwind v4 selector** — natively supported. If radio-card highlight doesn't work post-implementation, fall back to the old `radio radio-primary` pattern with a visible radio circle.
2. **`/sign-in` route doesn't exist** — same as Plan 3a. Drop the link or use placeholder + TODO comment.
3. **Existing booking tests** may assert on old markup ("Continue as Guest" header, `radio-primary` classes). Implementer triages with grep.
4. **Phone field optional in form, required by some downstream flows** — preserved as optional per existing UX.
5. **Form spacing differences** — `<.input>` has its own padding; visual review at PR.
6. **Auto-show form vs toggle conflict** — when `@existing_vehicles == []` and `@show_new_vehicle_form == true` (because user clicked toggle on a previous render with records, then deleted them), the form shows once via the OR condition. The "Add new" toggle button has the AND condition `@existing_vehicles != [] and !@show_new_vehicle_form` so it correctly hides when records are zero. **Verify** `mount/3` initializes `@show_new_vehicle_form` and `@show_new_address_form` to `false`.

---

## Open questions / TBDs

1. **`/sign-in` route** — verify at implementation; drop link if missing.
2. **`@show_new_vehicle_form` / `@show_new_address_form` initialization** — verify both default `false` in `mount/3` / `load_step_data`.

---

## Effort estimate

| Block | Estimate |
|---|---|
| `<.saved_record_card>` component + 3 tests | 0.25 day |
| Rewrite `:auth` step | 0.25 day |
| Rewrite `:vehicle` step | 0.5 day |
| Rewrite `:address` step | 0.25 day |
| Bug fixing + existing-test updates | 0.25 day |
| **Total** | **~1.5 days** of focused work |
