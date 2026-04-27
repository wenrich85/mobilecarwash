# Plan 3b-1 — Booking Components Refresh + Simple Step Templates Design

**Date:** 2026-04-27
**Status:** Draft (pending user review)
**Parent spec:** [2026-04-26-phase1-redesign-and-wallaby-design.md](2026-04-26-phase1-redesign-and-wallaby-design.md) — see "Customer-facing redesigns" section
**Author:** Brainstormed with Claude

---

## TL;DR

First of three Plan-3b sub-plans focusing on the booking page rewrite. Refreshes the 6 components in `MobileCarWashWeb.BookingComponents` to use Plan 1's design tokens, replaces the daisyUI step indicator with a progress-bar pattern, refreshes the service-card with a clearer selectable state, swaps the schedule step's `<input type="date">` for a horizontal date strip, and rewrites the 3 simplest step templates (`:select_service`, `:schedule`, `:confirmed`) in `booking_live.ex`.

The `Booking.StateMachine` module, all 22+ event handlers, and `mount/3` data loading are **untouched**. Only markup, component internals, and 3 step blocks change.

The 5 sub-flow-heavy step templates (`:auth`, `:vehicle`, `:address`, `:photos`, `:review`) are deferred to Plans **3b-2** and **3b-3**.

---

## Scope

### In scope

- **Refresh all 6 components** in `lib/mobile_car_wash_web/live/components/booking_components.ex`:
  - `step_indicator` — replace daisyUI `steps` pattern with progress bar + "Step X of 8 — Label" line + "Next: …" hint
  - `service_card` — refresh as a selectable card (full-card click, cyan ring + ✓ badge on selected)
  - `block_window_picker` — replace `<input type="date">` with a horizontal scrollable date strip (next 7 days as chips); refresh block list buttons
  - `time_slot_picker` — refresh chip styling
  - `booking_summary` — refresh tokens (used in `:review` step — actual usage in Plan 3b-3)
  - `confirmation_card` — refresh with cyan check icon, headline, key-value details list
- **Rewrite 3 step templates** in `booking_live.ex` `render/1`:
  - `:select_service` — service tier card grid + Continue (Continue disabled when no selection)
  - `:schedule` — `block_window_picker` (now date-strip-based) + Continue (disabled when no block)
  - `:confirmed` — `confirmation_card` + "Track your appointment" link to `/book/success`
- New component test file (`booking_components_test.exs`) — ~10-12 tests
- Update existing booking tests that assert on old daisyUI markup

### Explicitly out of scope (deferred)

- `:auth`, `:vehicle`, `:address` step rewrites → **Plan 3b-2** (sub-flow heavy)
- `:photos`, `:review` step rewrites → **Plan 3b-3**
- Mobile sticky CTA pattern — Plan 3b-2 or 3b-3 (consistent across all steps)
- Stripe Elements visual styling — Plan 3b-3
- `BookingStateMachine` logic changes — never (pure markup refactor)
- Event handler changes — never
- New steps or step removal — out of scope for the entire Plan 3b series
- Standalone `/book/success` page — **Plan 3c**

---

## File architecture

| Action | Path | Notes |
|---|---|---|
| Modify | `lib/mobile_car_wash_web/live/components/booking_components.ex` | Refresh all 6 components; preserve public attrs/slots; add `:available_dates` opt attr to `block_window_picker` |
| Modify | `lib/mobile_car_wash_web/live/booking_live.ex` | Rewrite `:select_service`, `:schedule`, `:confirmed` step blocks in `render/1`; everything else untouched |
| New (or modify if exists) | `test/mobile_car_wash_web/live/components/booking_components_test.exs` | ~10-12 component tests |
| Modify (if needed) | existing booking-related test files that assert on old `steps` markup or service_card classes | Discovered during implementation |

### Constraints honored

- All ~1039 tests stay green (some assertion updates expected for changed markup)
- All event handlers, state machine, `mount/3`, `handle_params/3` preserved
- Component public API (attrs, slots) preserved; one new optional attr added (`:available_dates`)
- No new components — refresh existing ones in place

---

## Locked design decisions

| Question | Choice |
|---|---|
| Step indicator | Progress bar + "Step X of 8 — Label" + "Next: …" hint |
| Service card on booking | Refresh existing as a selectable card (radio-like, full-card click, cyan ring + ✓) |
| Schedule step layout | Horizontal date strip + block list (no date input field) |

---

## Component refresh details

### `step_indicator/1`

**API stays:** `attr :current_step, :atom, required: true`.

**Render replaces** the daisyUI `<ul class="steps">` with:

```heex
<div class="mb-8">
  <div class="flex items-baseline justify-between mb-2">
    <div class="text-sm font-semibold text-base-content">
      Step {@step_number} of {@total_steps} — {@current_label}
    </div>
    <div class="text-xs text-base-content/60">{@progress_percent}% complete</div>
  </div>
  <div class="h-1.5 bg-base-200 rounded-full overflow-hidden">
    <div class="h-full bg-cyan-500 rounded-full transition-all"
         style={"width: #{@progress_percent}%"} />
  </div>
  <div :if={@next_label} class="text-xs text-base-content/60 mt-1.5">
    Next: {@next_label}
  </div>
</div>
```

Computed inside the function:
- `step_number` = index of `current_step` in `@steps` + 1
- `total_steps` = `length(@steps)` (8)
- `progress_percent` = `round((step_number / total_steps) * 100)`
- `current_label` = lookup from `step_labels()`
- `next_label` = label of next step, or `nil` if on the last step

### `service_card/1`

**API stays:** `attr :service, :map; attr :selected, :boolean, default: false`. Click handler `phx-click="select_service" phx-value-slug={@service.slug}` preserved.

**Visual refresh:**
- Card: `bg-base-100 border border-base-300 rounded-box`
- Selected: `border-2 border-cyan-500` + small cyan-filled `✓` badge top-right (24×24 rounded square)
- Price: 28px Inter 700, `font-mono tabular-nums`
- Duration: 12px slate-500 line below price
- Description: 14px `text-base-content/80`
- Hover: `shadow-md`
- Whole card clickable

### `block_window_picker/1`

**API:**
```elixir
attr :date, :any, required: true
attr :blocks, :list, required: true
attr :selected_block, :any, default: nil
attr :available_dates, :list, default: nil  # NEW: nil = component generates next 7 days
```

**Behavior:**
- Date strip: 7 chip buttons. Each shows day-of-week (`Tue`) + day-of-month (`28`) stacked. Today is leftmost. Tapping fires the existing `select_date` event with the chip's date.
- Selected date chip: `bg-cyan-500 text-white border-cyan-500`. Available unselected: `bg-base-100 border border-base-300`. Unavailable (no blocks for that date — discovered via the existing block-fetch logic): dimmed + disabled.
- Block list below: refresh button styling. Selected block: `bg-cyan-500 text-white`. Unselected: `bg-base-100 border border-base-300 hover:border-cyan-500`. Format: time range left ("9:00 – 11:00 AM"), capacity hint right ("2 slots").

If `:available_dates` is nil, the component generates `Date.utc_today()` through `+6` days as default.

### `time_slot_picker/1`

**API stays.** Visual refresh: chips in a grid (3-4/row desktop, 2/row mobile). Cyan-500 fill on selected; unavailable disabled+dimmed.

### `booking_summary/1`

**API stays.** Visual refresh: layout matching `<.service_tier_card>` typography (mono prices, label-uppercase tracking). Used in `:review` step (Plan 3b-3 hook).

### `confirmation_card/1`

**API stays.** Visual refresh:
- Big cyan check icon top (Heroicon `hero-check-circle` size-12, `text-cyan-500`)
- Headline: "Booking confirmed!" Inter 700 / 24px
- Key-value details list (date, time, service, address, total) — slate-500 keys, base-content values
- (CTA is rendered by the consuming step template, not the card itself)

### Component tests

`test/mobile_car_wash_web/live/components/booking_components_test.exs` — 1 describe block per component, 10-12 tests:

- `step_indicator/1`:
  - renders correct step number, total, label, progress %
  - on last step, omits "Next: …" line
- `service_card/1`:
  - selected state shows ✓ badge + cyan border
  - unselected state shows neither
  - click emits `phx-click="select_service"` with the slug value
- `block_window_picker/1`:
  - renders 7 date chips with today highlighted when no `:available_dates` passed
  - when a date is selected, shows the block list
  - selected block has cyan styling
- `confirmation_card/1`:
  - renders all booking detail fields (date, time, service, address, total)
- `time_slot_picker/1`:
  - selected slot shows cyan
  - unavailable slot disabled

---

## Step template rewrites in `booking_live.ex`

### `:select_service`

```heex
<div :if={@current_step == :select_service}>
  <div class="text-center mb-6">
    <h1 class="text-2xl font-bold text-base-content tracking-tight">
      Pick your service
    </h1>
    <p class="text-sm text-base-content/60 mt-1">
      Two tiers. No hidden fees.
    </p>
  </div>

  <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mb-6">
    <.service_card
      :for={service <- @services}
      service={service}
      selected={@selected_service && @selected_service.slug == service.slug}
    />
  </div>

  <div class="flex justify-end">
    <button
      class="btn btn-primary"
      phx-click="next_step"
      disabled={is_nil(@selected_service)}
    >
      Continue
    </button>
  </div>
</div>
```

### `:schedule`

```heex
<div :if={@current_step == :schedule}>
  <div class="mb-6">
    <h1 class="text-2xl font-bold text-base-content tracking-tight">
      Pick a time
    </h1>
    <p class="text-sm text-base-content/60 mt-1">
      We'll confirm your exact arrival time by midnight the day before.
    </p>
  </div>

  <.block_window_picker
    date={@selected_date}
    blocks={@available_blocks}
    selected_block={@selected_block}
  />

  <div class="flex justify-end mt-6">
    <button
      class="btn btn-primary"
      phx-click="next_step"
      disabled={is_nil(@selected_block)}
    >
      Continue
    </button>
  </div>
</div>
```

### `:confirmed`

```heex
<div :if={@current_step == :confirmed && @appointment}>
  <.confirmation_card appointment={@appointment} />

  <div class="flex justify-center mt-6">
    <.link navigate={~p"/book/success?id=#{@appointment.id}"} class="btn btn-primary">
      Track your appointment →
    </.link>
  </div>
</div>
```

### What stays in `booking_live.ex`

- `mount/3`, `handle_params/3`, all `handle_event/3` callbacks
- `BookingStateMachine` and its module
- `load_step_data/2` private helper
- `track_step_completion` event tracking
- The 5 OTHER step blocks in `render/1` (`:auth`, `:vehicle`, `:address`, `:photos`, `:review`) — deferred to 3b-2 / 3b-3
- The shared "Back" button (`<div :if={@current_step not in [:select_service, :confirmed]}>`)
- The wrapping `<.step_indicator current_step={@current_step} />` at top of `render/1`

---

## Mobile behavior

| Region | Mobile rule |
|---|---|
| `step_indicator` | Already minimal — progress bar full-width, label line wraps if needed |
| `service_card` (`:select_service`) | 2-col grid → 1-col stack at `sm`; cards full-width |
| `block_window_picker` date strip | Horizontal scroll on all widths; today sticky-left; chips ≥56×56px touch targets |
| `block_window_picker` block list | Already vertical buttons; refresh visual only |
| `confirmation_card` | Centers; details stack naturally |
| Continue button | Right-aligned desktop; full-width at bottom on `sm` and below |

**Touch targets:** all primary actions ≥44×44px. Date strip chips ≥56px both dimensions.

**Sticky CTA:** **not in this plan.** Continues to scroll with content. The sticky-CTA pattern (consistent across all 8 steps) is deferred to 3b-2/3b-3.

---

## Risks

1. **Existing booking tests** may assert on daisyUI `steps` markup or old service_card classes. Implementer should grep for `class="steps` and `service_card` in test files; update assertions inline as part of this plan.
2. **`@selected_service` assign** — verify the existing `mount/3` / `load_step_data` actually sets this assign. If the codebase uses a different name (e.g., `@service_slug`), adapt the template. Implementer must check before assuming.
3. **`:available_dates` is a new attr** with safe nil-default fallback (next 7 days from today).
4. **Date strip with no available blocks for some days** — chip dimmed + disabled; click does nothing. Existing block-fetch logic in `select_date` event handler returns the block list per date.
5. **Disabled Continue button is a UX change** — minor; improves UX, easy to revert.
6. **`hero-check-circle` icon** — confirmed available via Plan 1's heroicon plugin.
7. **`/book/success?id=...` route** referenced in `:confirmed` step — verify route exists with `id` param. If it doesn't accept `id`, drop the param and let the success page detect the latest appointment from session.
8. **The standalone `/book/success` page** is still on the OLD design until Plan 3c lands. The link works but the destination is unrefreshed.

---

## Open questions / TBDs

1. **Existing assign name for selected service** — verify in `mount/3` / `load_step_data` at implementation time.
2. **Date strip behavior with no future availability for any of the 7 days** — for Plan 3b-1, accept that the strip just shows dimmed chips; future polish (e.g., a "no availability this week, look further out" CTA) is a separate spec.
3. **Confirmation_card detail fields** — keep existing field set; visual-only refresh.

---

## Effort estimate

| Block | Estimate |
|---|---|
| Refresh 6 booking components | 0.5 day |
| Component tests | 0.25 day |
| 3 step template rewrites | 0.25 day |
| Bug fixing + existing-test updates | 0.25 day |
| **Total** | **~1.25 days** |
