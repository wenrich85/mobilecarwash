# Phase-1, Plan 3b-2 — Booking :auth, :vehicle, :address Step Rewrites

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a shared `<.saved_record_card>` component to `BookingComponents` and rewrite the `:auth`, `:vehicle`, and `:address` step templates in `booking_live.ex` to use Plan 1's design tokens, the new card component, and an auto-show-form-when-zero-records UX.

**Architecture:** One new TDD'd component (`saved_record_card`) used by both vehicle and address lists. Three step blocks rewritten in place. State machine + all event handlers + `mount/3` / `load_step_data/2` untouched. The 5 OTHER step blocks stay alone.

**Tech Stack:** Phoenix LiveView, Tailwind v4 (with `has-[:checked]:` modifier) + daisyUI, Phoenix.Component, ExUnit.

**Spec reference:** [docs/superpowers/specs/2026-04-27-plan3b2-booking-auth-vehicle-address-design.md](docs/superpowers/specs/2026-04-27-plan3b2-booking-auth-vehicle-address-design.md)

**File map:**

- Modify: `lib/mobile_car_wash_web/live/components/booking_components.ex` — add 1 new component
- Modify: `lib/mobile_car_wash_web/live/booking_live.ex` — rewrite 3 step blocks in `render/1`
- Modify: `test/mobile_car_wash_web/live/components/booking_components_test.exs` — add 3 tests
- Modify (if needed): existing booking-related test files with assertions on old markup

**Out of scope (deferred):**
- `:photos` / `:review` rewrites → **Plan 3b-3**
- Mobile sticky CTA, Stripe Elements styling → Plan 3b-3
- BookingStateMachine logic, event handlers — never
- `/sign-in` page redesign → phase-2

---

## Task 0: Pre-flight verification

**Files:** none modified — read-only.

- [ ] **Step 1: Verify clean tree on the right branch + Plan 3b-1 baseline green**

```bash
git status && git branch --show-current && mix test 2>&1 | tail -3
```
Expected: clean tree; ≥1056 tests passing.

- [ ] **Step 2: Verify the assigns and event handlers used by :auth/:vehicle/:address still exist as expected**

```bash
grep -n "current_customer\|guest_error\|existing_vehicles\|selected_vehicle\|show_new_vehicle_form\|existing_addresses\|selected_address\|show_new_address_form" lib/mobile_car_wash_web/live/booking_live.ex | head -20
grep -n "def handle_event(\"guest_checkout\\|def handle_event(\"select_vehicle\\|def handle_event(\"save_vehicle\\|def handle_event(\"show_new_vehicle\\|def handle_event(\"select_address\\|def handle_event(\"save_address\\|def handle_event(\"show_new_address" lib/mobile_car_wash_web/live/booking_live.ex
```
Expected: all 8 assigns and all 7 handlers present. Note their line numbers.

- [ ] **Step 3: Check `/sign-in` route**

```bash
grep -E '/sign-in|/auth' lib/mobile_car_wash_web/router.ex | head -5
```
If no `live "/sign-in", ...` route exists, the `<.link navigate={~p"/sign-in"}>` block in the new `:auth` template will fail compile. Adapt to either `~p"/auth/customer/sign-in"` (Ash auth convention) OR drop the `<.link>` entirely and leave a `<%!-- TODO: add /sign-in route --%>` comment.

- [ ] **Step 4: Note the baseline test count**

Record from Step 1 for the final-checkpoint comparison.

---

## Task 1: Add `<.saved_record_card>` component (TDD)

**Files:**
- Modify: `lib/mobile_car_wash_web/live/components/booking_components.ex` (append before module's final `end`)
- Modify: `test/mobile_car_wash_web/live/components/booking_components_test.exs` (append before module's final `end`)

- [ ] **Step 1: Append failing tests**

Add to `test/mobile_car_wash_web/live/components/booking_components_test.exs` before the module's closing `end`:

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

- [ ] **Step 2: Run tests, verify failure**

Run: `mix test test/mobile_car_wash_web/live/components/booking_components_test.exs --only describe:saved_record_card`
Expected: function undefined error.

- [ ] **Step 3: Add `saved_record_card/1` to BookingComponents**

Append to `lib/mobile_car_wash_web/live/components/booking_components.ex` before the module's final `end`:

```elixir
  @doc """
  Renders a generic selectable card for a saved record (vehicle, address,
  payment method, etc.). Pairs with `:phx-click` events for selection.

  ## Examples

      <.saved_record_card
        title="2023 Tesla Model 3"
        subtitle="Silver · car"
        selected={true}
        phx-click="select_vehicle"
        phx-value-id={vehicle.id}
      />
  """
  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  attr :selected, :boolean, default: false
  attr :rest, :global, include: ~w(phx-click phx-value-id)

  def saved_record_card(assigns) do
    ~H"""
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
    """
  end
```

- [ ] **Step 4: Run tests, verify pass**

Run: `mix test test/mobile_car_wash_web/live/components/booking_components_test.exs`
Expected: 21 tests pass (18 existing from Plan 3b-1 + 3 new).

- [ ] **Step 5: Commit**

```bash
git add lib/mobile_car_wash_web/live/components/booking_components.ex test/mobile_car_wash_web/live/components/booking_components_test.exs
git commit -m "booking: add <.saved_record_card> generic selectable card

Used by :vehicle and :address step lists in Plan 3b-2 to render
saved vehicles and addresses with a uniform selectable pattern
(cyan border + check badge mirrors <.service_card>)."
```

---

## Task 2: Rewrite `:auth` step

**Files:**
- Modify: `lib/mobile_car_wash_web/live/booking_live.ex` (the `:auth` step block, ~lines 260-338)

- [ ] **Step 1: Read current `:auth` block**

Run: `sed -n '258,340p' lib/mobile_car_wash_web/live/booking_live.ex`
Note: the existing template has `<.link navigate={~p"/sign-in"}>` and a "Create Account" link. If `/sign-in` doesn't exist (per Task 0 Step 3), adapt the new template before applying.

- [ ] **Step 2: Replace the `:auth` step block**

Find `<div :if={@current_step == :auth}>...</div>` and replace its contents with:

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

          <%!-- TODO: spec calls for "Sign in" link to /sign-in. Verify route exists; otherwise drop this block or repoint to /auth/customer/sign-in. --%>
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

**If `/sign-in` route doesn't exist** (Task 0 Step 3 found nothing matching), replace the `<.link navigate={~p"/sign-in"} ...>` block with:

```heex
              <a href="#" class="btn btn-ghost btn-sm pointer-events-none opacity-50" aria-disabled="true">
                Sign in (coming soon)
              </a>
```

OR drop the entire `<div class="bg-base-200 rounded-box p-4">...</div>` block. Either is acceptable. Document the choice in the commit message.

- [ ] **Step 3: Verify compile**

Run: `mix compile --warnings-as-errors 2>&1 | tail -3`
Expected: `Generated mobile_car_wash app`. If route error, adapt per Step 2 fallback.

- [ ] **Step 4: Commit**

```bash
git add lib/mobile_car_wash_web/live/booking_live.ex
git commit -m "booking: rewrite :auth step (guest-first, sign-in secondary)

Reorganizes auth step around guest-first flow per spec. Refreshes
visuals to Plan 1 tokens. Uses <.input> from CoreComponents for
form fields. All event handlers (guest_checkout, next_step) and
@current_customer / @guest_error assigns preserved."
```

---

## Task 3: Rewrite `:vehicle` step

**Files:**
- Modify: `lib/mobile_car_wash_web/live/booking_live.ex` (the `:vehicle` step block, ~lines 340-461)

- [ ] **Step 1: Read current `:vehicle` block**

Run: `sed -n '340,462p' lib/mobile_car_wash_web/live/booking_live.ex`
Note assign names and form field names for substitution.

- [ ] **Step 2: Replace the `:vehicle` step block**

Find `<div :if={@current_step == :vehicle}>...</div>` and replace its contents with:

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

- [ ] **Step 3: Verify compile**

Run: `mix compile --warnings-as-errors 2>&1 | tail -3`
Expected: clean.

If you see `undefined assign @selected_vehicle` or similar, the assign is named differently. Inspect `mount/3` and `load_step_data/2` and adapt.

- [ ] **Step 4: Commit**

```bash
git add lib/mobile_car_wash_web/live/booking_live.ex
git commit -m "booking: rewrite :vehicle step against <.saved_record_card>

Saved vehicles list uses the new <.saved_record_card>. Add-new form
auto-shows when zero saved vehicles, otherwise reveals via toggle.
Vehicle type radio cards use Tailwind 'has-[:checked]' modifier for
selection highlight (replaces explicit radio circles)."
```

---

## Task 4: Rewrite `:address` step

**Files:**
- Modify: `lib/mobile_car_wash_web/live/booking_live.ex` (the `:address` step block, ~lines 463-545)

- [ ] **Step 1: Read current `:address` block**

Run: `sed -n '462,545p' lib/mobile_car_wash_web/live/booking_live.ex`

- [ ] **Step 2: Replace the `:address` step block**

Find `<div :if={@current_step == :address}>...</div>` and replace its contents with:

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

If the existing template has additional content after the zone indicator (it might end at line 545 or extend further — re-verify against your sed output), preserve only what's relevant. The "Continue" button at the bottom is the natural end of the step block.

- [ ] **Step 3: Verify compile**

Run: `mix compile --warnings-as-errors 2>&1 | tail -3`
Expected: clean.

- [ ] **Step 4: Commit**

```bash
git add lib/mobile_car_wash_web/live/booking_live.ex
git commit -m "booking: rewrite :address step against <.saved_record_card>

Saved addresses list uses the new <.saved_record_card>. Add-new form
auto-shows when zero saved addresses, otherwise reveals via toggle.
Zone indicator alert preserved from existing template, restyled to
new design tokens."
```

---

## Task 5: Triage existing booking-related tests

**Files:** any existing test files broken by the markup changes.

- [ ] **Step 1: Run full project test suite**

Run: `mix test 2>&1 | tee /tmp/plan3b2-regression.log | tail -10`
Expected: most tests pass. Some may fail if they assert on:
- Old `:auth` step's "Welcome back" alert classes (`alert alert-success`)
- Old `:vehicle` step's `radio radio-primary` classes
- Old `:address` step's `card-body py-3` classes
- Form field names like `vehicle[make]` (these stay) — should NOT need updating
- Anything else asserting specific Tailwind classes

- [ ] **Step 2: Triage failures and update assertions**

For each failing assertion:
- Read the rendered HTML in the failure message
- Update the assertion to match the new markup OR drop assertions that no longer make sense
- DO NOT change production code to satisfy stale tests

Common updates:
- `assert html =~ "ring-2 ring-primary"` → `assert html =~ "border-cyan-500"`
- `assert html =~ "alert-success"` → `assert html =~ "border-success"`
- `assert html =~ "radio radio-primary"` → drop OR `assert html =~ "vehicle[size]"`

- [ ] **Step 3: Re-run tests**

Run: `mix test 2>&1 | tail -3`
Expected: 0 failures, count = baseline + 3 new component tests = ≥1059.

- [ ] **Step 4: Commit (if any test changes made)**

```bash
git add -p   # selectively stage just assertion updates
git commit -m "test: update booking test assertions for new auth/vehicle/address markup"
```

If no test changes were needed, skip this commit.

---

## Task 6: Final verification

**Files:** none modified.

- [ ] **Step 1: Run full test suite**

Run: `mix test 2>&1 | tail -3`
Expected: ≥1059 tests passing, 0 failures.

- [ ] **Step 2: Compile + format + assets**

```bash
mix compile --warnings-as-errors 2>&1 | tail -3
mix format --check-formatted 2>&1 | tail -3
mix assets.deploy 2>&1 | tail -5
```
All clean. If format flags issues: `mix format && git add -A && git commit -m "chore: mix format"`.

- [ ] **Step 3: Boot dev server, smoke-test the booking flow**

```bash
mix phx.server
```

Open `http://localhost:4000/book`. Click through:
- Step 1 (`:select_service`): pick Basic. Continue.
- Step 2 (`:auth`): see new guest-first form. Submit dummy info → moves to step 3.
- Step 3 (`:vehicle`): with no saved vehicles, the add-new form should appear directly. Fill it in, click Save Vehicle. Vehicle should appear as a selectable card. Continue.
- Step 4 (`:address`): same auto-show pattern. Add an address. Continue.
- Step 5 onwards: still the OLD design (Plan 3b-3 territory). Acceptable.

If anything 500s or renders broken, inspect and fix before declaring complete.

Stop the server.

- [ ] **Step 4: Confirm git log**

Run: `git log --oneline main..HEAD | head -10` (or `git log --oneline -10` if working on main)
You should see 4-5 commits from Plan 3b-2 (Tasks 1-4 + maybe Task 5).

- [ ] **Step 5: Report Plan 3b-2 complete**

Summary:
- 1 new component (`<.saved_record_card>`) with 3 tests
- 3 step templates rewritten (`:auth`, `:vehicle`, `:address`)
- Saved-records lists use the new shared card
- Add-new forms auto-show when zero saved records, toggle when ≥1
- All event handlers + state machine + mount/3 untouched

Recommend the user click through `/book` step 2 → step 4 to visually verify before promoting. Plans 3b-3 (photos/review) and 3c (success page) are still ahead.

---

## What's NOT in Plan 3b-2

- `:photos` / `:review` step rewrites → **Plan 3b-3**
- Mobile sticky CTA pattern → Plan 3b-3
- Stripe Elements styling → Plan 3b-3
- Standalone `/book/success` page → **Plan 3c**
- BookingStateMachine logic — never
- Event handler changes — never
- `/sign-in` page redesign → phase-2
- Address autocomplete (Google Places) — separate future spec
- Vehicle make/model database autocomplete — separate future spec
