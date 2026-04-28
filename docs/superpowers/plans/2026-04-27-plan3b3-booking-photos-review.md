# Phase-1, Plan 3b-3 — Booking :photos + :review Step Rewrites + Mobile Sticky CTA

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refresh the `:photos` and `:review` step templates in `booking_live.ex`, surgically refresh `PhotoUploader` internals (mostly already on new tokens), and add a mobile sticky CTA to `:review`.

**Architecture:** Three template-only changes. State machine, all event handlers, mount/3 / handle_params/3 / load_step_data — untouched. The 6 OTHER step blocks stay alone.

**Tech Stack:** Phoenix LiveView, Tailwind v4 + daisyUI, Phoenix.Component, ExUnit.

**Spec reference:** [docs/superpowers/specs/2026-04-27-plan3b3-booking-photos-review-design.md](docs/superpowers/specs/2026-04-27-plan3b3-booking-photos-review-design.md)

**File map:**

- Modify: `lib/mobile_car_wash_web/components/photo_uploader.ex` — surgical token swaps
- Modify: `lib/mobile_car_wash_web/live/booking_live.ex` — rewrite `:photos` and `:review` step blocks
- Modify (if needed): existing booking-related test files

**Out of scope (deferred):**
- 6 other step blocks — already done in Plans 3b-1 / 3b-2
- Stripe Elements styling — N/A (Stripe Checkout hosted page; Dashboard branding in Plan 2 deployment checklist)
- Standalone `/book/success` page → **Plan 3c**
- BookingStateMachine logic, event handlers, mount/3 — never

---

## Task 0: Pre-flight verification

**Files:** none modified — read-only.

- [ ] **Step 1: Verify clean tree + Plan 3b-2 baseline green**

```bash
git status && git branch --show-current && mix test 2>&1 | tail -3
```
Expected: clean tree; ≥1060 tests passing.

- [ ] **Step 2: Note baseline test count**

Record from Step 1.

- [ ] **Step 3: Find current `hover:border-primary` references in PhotoUploader**

```bash
grep -n "hover:border-primary\|border-primary[^-]\|primary-700\|secondary-50\|tertiary-\|ring-primary" lib/mobile_car_wash_web/components/photo_uploader.ex
```
Note the lines that need swapping in Task 1.

- [ ] **Step 4: Find existing tests touching photos or review markup**

```bash
grep -lE "Problem Area|Review Your Booking|btn-primary btn-lg" test/ -r 2>/dev/null | head -5
```
Note the list — these may need assertion updates in Task 4.

---

## Task 1: Refresh PhotoUploader internals

**Files:**
- Modify: `lib/mobile_car_wash_web/components/photo_uploader.ex`

- [ ] **Step 1: Apply token swaps**

For each line found in Task 0 Step 3, apply this substitution:
- `hover:border-primary` → `hover:border-cyan-500`
- `border-primary` (without dash-suffix; standalone) → `border-cyan-500`
- `primary-700`, `primary-900` (old palette) → `cyan-700`, `cyan-800` respectively
- `secondary-50`, `secondary-100` → `base-100`, `base-200`
- `tertiary-400` → `cyan-500`
- `ring-primary` → `ring-cyan-500`

Use `mix format` after editing if you're editing more than 5 lines to keep formatting consistent.

If only 1-3 lines need swapping (per Task 0 Step 3 grep), this is just 1-3 sed-style edits.

If 10+ lines need swapping, STOP and report — that's beyond scope and the user should re-evaluate the refresh approach.

- [ ] **Step 2: Verify compile**

Run: `mix compile --warnings-as-errors 2>&1 | tail -3`
Expected: clean.

- [ ] **Step 3: Run PhotoUploader tests**

Run: `mix test test/mobile_car_wash_web/components/photo_uploader_test.exs 2>&1 | tail -5`
Expected: 0 failures (existing test count, whatever it is).

If a test fails because it asserts a specific old class name (e.g., `assert html =~ "hover:border-primary"`), update the assertion to match the new class.

- [ ] **Step 4: Commit**

```bash
git add lib/mobile_car_wash_web/components/photo_uploader.ex
git commit -m "booking: refresh PhotoUploader hover/border tokens to cyan-500

Surgical token swaps for hover-state consistency with the rest of
the booking flow. Most of the module was already on new design
tokens (bg-base-200, btn-primary via daisyUI, etc.); only hover/
border references needed updating."
```

If no production code changes were needed (tests passed without changes, no old tokens in PhotoUploader), skip the commit and report that PhotoUploader was already clean.

---

## Task 2: Rewrite `:photos` step block

**Files:**
- Modify: `lib/mobile_car_wash_web/live/booking_live.ex` (`:photos` step block, ~lines 459-485)

- [ ] **Step 1: Find the current `:photos` block**

Run: `grep -n '@current_step == :photos' lib/mobile_car_wash_web/live/booking_live.ex`
Note the line. The block runs from there until the next `<div :if={@current_step == :SOMETHING}>`.

- [ ] **Step 2: Replace the `:photos` block**

Find `<div :if={@current_step == :photos}>...</div>` and replace its contents with:

```heex
      <div :if={@current_step == :photos}>
        <div class="mb-6">
          <h1 class="text-2xl font-bold text-base-content tracking-tight">
            Show us what to focus on
          </h1>
          <p class="text-sm text-base-content/60 mt-1">
            Snap photos of any spots that need extra attention. Optional — tap Skip if you don't have any.
          </p>
        </div>

        <form phx-change="validate_photos" id="photo-upload-form">
          <MobileCarWashWeb.PhotoUploader.uploader
            camera_upload={@uploads.problem_photo_camera}
            library_upload={@uploads.problem_photo_library}
            uploaded_photos={@uploaded_photos}
            selected_car_part={@selected_car_part}
            show_all_parts={@show_all_parts}
            caption={@photo_caption}
          />
        </form>

        <div class="flex flex-col-reverse sm:flex-row gap-2 sm:gap-4 sm:justify-end mt-6">
          <button class="btn btn-ghost" phx-click="next_step">
            Skip — no photos
          </button>
          <button :if={@uploaded_photos != []} class="btn btn-primary" phx-click="next_step">
            Continue
          </button>
        </div>
      </div>
```

The PhotoUploader call signature stays exactly the same — same 6 attrs.

- [ ] **Step 3: Verify compile**

Run: `mix compile --warnings-as-errors 2>&1 | tail -3`
Expected: clean.

- [ ] **Step 4: Commit**

```bash
git add lib/mobile_car_wash_web/live/booking_live.ex
git commit -m "booking: rewrite :photos step (refreshed copy + thumb-friendly button order)

Heading: 'Show us what to focus on'. Subhead: tightened copy. Button
row uses flex-col-reverse on mobile so Continue (primary action) sits
above Skip (closer to thumb). Skip button removed btn-sm modifier
(now full-size for thumb-friendliness). All event handlers and
PhotoUploader attrs preserved."
```

---

## Task 3: Rewrite `:review` step block (with mobile sticky CTA)

**Files:**
- Modify: `lib/mobile_car_wash_web/live/booking_live.ex` (`:review` step block, ~lines 514-607)

- [ ] **Step 1: Find the current `:review` block**

Run: `grep -n '@current_step == :review' lib/mobile_car_wash_web/live/booking_live.ex`

- [ ] **Step 2: Replace the `:review` block**

Find `<div :if={@current_step == :review}>...</div>` and replace its contents with:

```heex
      <div :if={@current_step == :review}>
        <div class="mb-6">
          <h1 class="text-2xl font-bold text-base-content tracking-tight">
            Review your booking
          </h1>
        </div>

        <%!-- Subscription banner --%>
        <div :if={@active_subscription} class="bg-success/10 border border-success/30 rounded-box p-4 mb-4">
          <div class="text-sm font-semibold text-success">
            {@active_subscription.plan.name} plan applied
          </div>
          <div :if={@active_subscription.plan.basic_washes_per_month > 0} class="text-xs text-success/80 mt-1">
            {Map.get(@active_subscription.usage, :basic_washes_used, 0)}/{@active_subscription.plan.basic_washes_per_month} basic washes used this period
          </div>
          <div :if={@active_subscription.plan.deep_clean_discount_percent > 0} class="text-xs text-success/80 mt-1">
            {@active_subscription.plan.deep_clean_discount_percent}% off deep cleans
          </div>
        </div>

        <%!-- Loyalty (with toggle) --%>
        <% loyalty_free = MobileCarWash.Loyalty.available_free_washes(@loyalty_card) %>
        <div
          :if={loyalty_free > 0 && !@active_subscription}
          class={[
            "rounded-box p-4 mb-4",
            if(@redeem_loyalty,
              do: "bg-success/10 border border-success/30",
              else: "bg-info/10 border border-info/30"
            )
          ]}
        >
          <div class="flex items-center justify-between gap-3 flex-wrap">
            <div>
              <div class={["text-sm font-semibold", if(@redeem_loyalty, do: "text-success", else: "text-info")]}>
                {if @redeem_loyalty,
                  do: "🎁 Free wash applied!",
                  else:
                    "🎁 You have #{loyalty_free} free wash#{if loyalty_free != 1, do: "es"} available"}
              </div>
              <div class="text-xs text-base-content/60 mt-0.5">
                {if @redeem_loyalty,
                  do: "This booking is on us.",
                  else: "Earned from your loyalty punch card."}
              </div>
            </div>
            <button
              class={["btn btn-sm", if(@redeem_loyalty, do: "btn-outline", else: "btn-primary")]}
              phx-click="toggle_loyalty"
            >
              {if @redeem_loyalty, do: "Remove", else: "Apply free wash"}
            </button>
          </div>
        </div>

        <%!-- Referral --%>
        <div :if={!@redeem_loyalty && !@active_subscription} class="bg-base-100 border border-base-300 rounded-box p-4 mb-4">
          <div :if={!@referral_code}>
            <form phx-submit="apply_referral" class="flex items-center gap-2">
              <input
                type="text"
                name="code"
                class="input input-bordered input-sm flex-1 h-10"
                placeholder="Referral code"
                maxlength="8"
              />
              <button type="submit" class="btn btn-sm btn-outline">Apply</button>
            </form>
            <p :if={@referral_error} class="text-error text-xs mt-2">{@referral_error}</p>
          </div>
          <div :if={@referral_code} class="flex items-center justify-between gap-3">
            <div>
              <div class="text-sm font-semibold text-success">$10 referral discount applied</div>
              <div class="text-xs text-base-content/60 mt-0.5">Code: {@referral_code}</div>
            </div>
            <button class="btn btn-sm btn-outline" phx-click="clear_referral">Remove</button>
          </div>
        </div>

        <%!-- Booking summary --%>
        <% base_price =
          MobileCarWash.Billing.Pricing.calculate(
            @selected_service.base_price_cents,
            @selected_vehicle.size
          ) %>
        <.booking_summary
          appointment={
            %{
              scheduled_at: @selected_slot,
              price_cents: base_price - @referral_discount,
              discount_cents: if(@redeem_loyalty, do: base_price, else: @referral_discount)
            }
          }
          service={@selected_service}
          vehicle={@selected_vehicle}
          address={@selected_address}
        />

        <%!-- Desktop button row --%>
        <div class="hidden sm:flex gap-3 justify-end mt-6">
          <button class="btn btn-outline" phx-click="prev_step">Back</button>
          <button class="btn btn-primary" phx-click="confirm_booking">
            {if @redeem_loyalty, do: "Confirm — free wash!", else: "Confirm booking"}
          </button>
        </div>

        <%!-- Mobile sticky CTA --%>
        <div class="sm:hidden h-20"></div>
        <div class="sm:hidden fixed bottom-0 inset-x-0 bg-base-100 border-t border-base-300 px-4 py-3 z-40">
          <div class="flex items-center gap-3">
            <button class="btn btn-ghost btn-sm" phx-click="prev_step">Back</button>
            <button class="btn btn-primary flex-1" phx-click="confirm_booking">
              {if @redeem_loyalty,
                do: "Confirm — free!",
                else: "Confirm · $#{div(base_price - @referral_discount, 100)}"}
            </button>
          </div>
        </div>
      </div>
```

The replacement preserves:
- All event handlers (`confirm_booking`, `prev_step`, `toggle_loyalty`, `clear_referral`, `apply_referral`)
- All socket assigns
- The `<.booking_summary>` call (already refreshed in 3b-1)
- `Pricing.calculate/2` and `Loyalty.available_free_washes/1` calls
- All conditional logic for subscription / loyalty / referral states

- [ ] **Step 3: Verify compile**

Run: `mix compile --warnings-as-errors 2>&1 | tail -3`
Expected: clean.

- [ ] **Step 4: Commit**

```bash
git add lib/mobile_car_wash_web/live/booking_live.ex
git commit -m "booking: rewrite :review step (refreshed alerts + mobile sticky CTA)

Refreshes 3 alert blocks (subscription, loyalty, referral) from
DaisyUI alert-* classes to utility tokens (bg-success/10 etc.).
Adds mobile sticky CTA at the bottom of viewport for the Confirm
button + abbreviated total. 80px spacer prevents content hiding
under the bar. State machine + handlers untouched."
```

---

## Task 4: Triage existing booking-related tests

**Files:** any existing test files broken by markup changes.

- [ ] **Step 1: Run full test suite**

Run: `mix test 2>&1 | tee /tmp/plan3b3-regression.log | tail -10`

- [ ] **Step 2: Triage failures**

For each failing assertion:
- Read the rendered HTML in the failure
- Update assertion to match new markup OR drop assertions that no longer make sense

Common updates:
- `assert html =~ "alert-success"` → `assert html =~ "bg-success"` (or just drop)
- `assert html =~ "Problem Area Photos"` → `assert html =~ "Show us what to focus on"`
- `assert html =~ "Review Your Booking"` → `assert html =~ "Review your booking"`
- `assert html =~ "Apply Free Wash"` → `assert html =~ "Apply free wash"`
- `assert html =~ "Confirm Booking"` → `assert html =~ "Confirm booking"`

- [ ] **Step 3: Re-run tests**

Run: `mix test 2>&1 | tail -3`
Expected: 0 failures.

- [ ] **Step 4: Commit (if test changes made)**

```bash
git add -p
git commit -m "test: update assertions for refreshed :photos + :review markup"
```

If no changes needed, skip.

---

## Task 5: Final verification

**Files:** none modified.

- [ ] **Step 1: Run full test suite**

Run: `mix test 2>&1 | tail -3`
Expected: ≥1060 tests, 0 failures (Plan 3b-3 doesn't add new tests since it's pure markup refresh).

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

Open `http://localhost:4000/book` and click through to step 5 (`:photos`):
- See refreshed heading "Show us what to focus on"
- Try uploading (or skip) — both buttons work; Continue stacks above Skip on narrow viewport
- Continue to step 6 (`:schedule`) — already shipped in 3b-1, should still work
- Continue to step 7 (`:review`) — see refreshed alerts and booking summary
- On mobile viewport (resize browser to ~375px wide): see sticky CTA at bottom; "Back" and "Confirm · $X" both visible and clickable; 80px gap below content prevents bottom of summary from being hidden
- Click Confirm — should redirect to Stripe Checkout (or to `:confirmed` step if subscription/loyalty covers it)

Stop the server.

- [ ] **Step 4: Confirm git log**

Run: `git log --oneline main..HEAD | head -10`
Expect 2-4 commits from Plan 3b-3.

- [ ] **Step 5: Report Plan 3b-3 complete**

Summary:
- `:photos` step refreshed (heading, subhead, button order)
- PhotoUploader internal tokens (if any old ones existed)
- `:review` step refreshed (3 alerts in utility tokens, booking_summary already done in 3b-1)
- Mobile sticky CTA added on `:review` only

All 8 booking step blocks now refreshed across Plans 3b-1, 3b-2, 3b-3. Plan 3c (standalone `/book/success`) is the last booking-related work in phase-1.

---

## What's NOT in Plan 3b-3

- The 6 OTHER step blocks — already done
- Stripe Elements styling — N/A (Stripe Checkout hosted page)
- Standalone `/book/success` page → **Plan 3c**
- BookingStateMachine logic, event handlers — never
