# Plan 3b-3 — Booking Page :photos + :review Step Rewrites + Mobile Sticky CTA

**Date:** 2026-04-27
**Status:** Draft (pending user review)
**Parent spec:** [2026-04-26-phase1-redesign-and-wallaby-design.md](2026-04-26-phase1-redesign-and-wallaby-design.md) — see "Customer-facing redesigns" section
**Sibling specs:** [Plan 3b-1](2026-04-27-plan3b1-booking-components-simple-steps-design.md), [Plan 3b-2](2026-04-27-plan3b2-booking-auth-vehicle-address-design.md)
**Author:** Brainstormed with Claude

---

## TL;DR

Final of three Plan-3b sub-plans. Refreshes the `:photos` step block + minor `PhotoUploader` internal tokens, rewrites the `:review` step (subscription/loyalty/referral alerts + booking_summary call + Confirm button area), and adds a mobile sticky CTA on `:review` only.

**Stripe Elements styling is N/A** — payment uses Stripe Checkout (hosted page redirect), not inline Elements. Stripe Dashboard branding is already in Plan 2's deployment checklist.

State machine, all event handlers, mount/3 / handle_params/3 / load_step_data — **untouched**. Only template markup + sticky-CTA mobile layout change.

---

## Scope

### In scope

- **Refresh `:photos` step block** in `booking_live.ex` — heading typography, subhead copy, skip/continue button row (mobile flex-col-reverse so primary action sits closer to thumb)
- **Refresh `MobileCarWashWeb.PhotoUploader` internals** — surgical token swaps (mainly `hover:border-primary` → `hover:border-cyan-500` for hover-state consistency with rest of booking)
- **Rewrite `:review` step block**:
  - 3 separate alert blocks (subscription, loyalty, referral) — refresh tokens (`alert alert-success` → `bg-success/10 border border-success/30 text-success`)
  - Booking summary uses existing `<.booking_summary>` (already refreshed in Plan 3b-1)
  - Desktop button row + new **mobile sticky CTA** at the bottom of viewport (Confirm + price)
- Update existing tests if any assert on old markup

### Explicitly out of scope (deferred or never)

- The 6 other step blocks — already done in 3b-1 / 3b-2 OR not in scope (`:confirmed` already done in 3b-1)
- **Stripe Elements styling — N/A** (this app uses Stripe Checkout; styling via Dashboard per Plan 2)
- Standalone `/book/success` page → **Plan 3c**
- Combining the 3 alert blocks into a single "Applied discounts" card — deferred (Q1 locked = keep separate)
- Sticky CTA on the other 7 step blocks — `:review` only (Q2 locked)
- BookingStateMachine logic, event handlers, mount/3 — never
- New steps or step removal — never

---

## File architecture

| Action | Path | Notes |
|---|---|---|
| Modify | `lib/mobile_car_wash_web/components/photo_uploader.ex` | Surgical token swaps (~2-3 line edits) |
| Modify | `lib/mobile_car_wash_web/live/booking_live.ex` | Rewrite `:photos` and `:review` step blocks; add mobile sticky CTA wrapper |
| Modify (if needed) | existing tests asserting on old markup | Discovered during implementation |

### Constraints honored

- All ~1060 tests stay green
- All event handlers, state machine, mount/3 / handle_params/3 / load_step_data preserved
- All `phx-click`, `phx-submit`, `phx-value-id` wiring preserved
- All socket assigns preserved (`@uploaded_photos`, `@selected_car_part`, `@show_all_parts`, `@photo_caption`, `@active_subscription`, `@loyalty_card`, `@redeem_loyalty`, `@referral_code`, `@referral_error`, `@referral_discount`, `@selected_service`, `@selected_vehicle`, `@selected_slot`, `@selected_address`)
- The 6 OTHER step blocks (`:select_service`, `:auth`, `:vehicle`, `:address`, `:schedule`, `:confirmed`) untouched

---

## Locked design decisions

| Question | Choice |
|---|---|
| `:review` alerts | Keep 3 separate, refresh tokens (no combining) |
| Mobile sticky CTA scope | Only on `:review` step (not the other 7) |
| `:photos` step refresh | Refresh both step block AND PhotoUploader internals |

---

## `:photos` step rewrite

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

Changes:
- Heading: tighter typography (`tracking-tight`), refreshed copy
- Subhead: 14px slate-500
- Skip button: removed `btn-sm` (full-size for thumb-friendliness)
- Button row: `flex-col-reverse sm:flex-row` — Continue above Skip on mobile

## PhotoUploader internal refresh

Surgical token swaps. The module is largely on new tokens already (uses `bg-base-200`, `border-base-300`, `btn-primary`, `text-base-content`, `progress-primary`).

Required edits:
1. `drop_zone/1`: change `hover:border-primary` → `hover:border-cyan-500` (line ~147)
2. `drop_zone_only/1`: same swap if present
3. Any other inline `hover:border-primary` references in the module — grep + swap

If implementer finds additional old tokens (`primary-700`, `secondary-50`, `tertiary-`, `ring-primary`), apply same swap pattern. Preserve everything else.

Existing test file (`test/.../photo_uploader_test.exs`) likely already passes — re-run after changes.

---

## `:review` step rewrite

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

### Changes from current

- Subscription banner: `alert alert-success` → `bg-success/10 border border-success/30` utility tokens; tighter typography
- Loyalty banner: refreshed; conditional success/info color depending on `@redeem_loyalty`
- Referral: now in a base card; smaller form with `h-10` input matching `btn-sm`
- Confirm button: copy refresh ("Confirm booking" / "Confirm — free wash!")
- **NEW: mobile sticky CTA** at bottom of viewport (`fixed bottom-0 inset-x-0 z-40`)
- 80px spacer (`h-20`) on mobile to prevent last booking-summary content being hidden under the sticky bar

### Sticky CTA notes

- `position: fixed; bottom: 0` keeps the bar visible at the bottom of the viewport on mobile
- `z-40` puts it above page content but below modals (`z-50`)
- Mobile button shows shortened total (`Confirm · $50`) for at-a-glance pricing
- Back button reduced to `btn-ghost btn-sm` so it doesn't compete with primary action

---

## What stays

- All `phx-click="confirm_booking"`, `phx-click="prev_step"`, `phx-click="toggle_loyalty"`, `phx-click="clear_referral"`, `phx-submit="apply_referral"` event handlers preserved
- All socket assigns referenced — preserved
- `Pricing.calculate/2`, `Loyalty.available_free_washes/1` calls preserved
- The 6 OTHER step blocks untouched
- PhotoUploader public API (attrs) preserved; only internal classes change

---

## Mobile behavior

| Region | Mobile rule |
|---|---|
| `:photos` heading + subhead | Single-column |
| `:photos` skip/continue buttons | `flex-col-reverse sm:flex-row` — Continue above Skip on mobile |
| `:review` 3 alert blocks | Stack vertically full-width |
| `:review` loyalty/referral inner row | `flex-wrap` — wraps to 2 lines on narrow phones |
| `:review` booking summary | Already mobile-friendly (Plan 3b-1) |
| `:review` desktop button row | Hidden below `sm` |
| `:review` mobile sticky CTA | Visible only below `sm`; 80px spacer above it |

**Touch targets:** all primary actions ≥44×44px. Mobile sticky bar ~56px tall.

---

## Risks

1. **Sticky CTA z-index conflict with modals** — bar uses `z-40`; Plan 1 `<.modal>` uses `z-50`. Modals correctly overlay. Grep for any other `z-40+` on this page to confirm no conflicts.
2. **80px spacer hardcoded** — if the sticky bar grows (extra discount line, etc.), spacer becomes too short. Mitigation: visual review at PR; bump if needed. Acceptable for v1.
3. **PhotoUploader token references** — spec says ~2-3 edits but might find more. If 10+ instances, escalate scope.
4. **Conditional class lists** — loyalty banner has nested ternaries. Trade-off vs verbose `:if` blocks. Acceptable.
5. **Mobile sticky bar always visible on review step** — pushy for some users. Trade — it's the LAST step, conversion-focus appropriate.
6. **`Confirm · $50` mobile button text uses `div(_, 100)` integer division** — truncates cents. Premium tier ($199.99) would render as `$199`. Implementer verifies whether `Pricing.calculate/2` produces non-round amounts; if yes, format properly.

---

## Open questions / TBDs

1. **Sticky CTA height tuning** — visual review at PR; bump spacer to `h-24` if cramped.
2. **Mobile button price formatting** — verify `Pricing.calculate/2` output; format cents properly if needed.

---

## Effort estimate

| Block | Estimate |
|---|---|
| `:photos` step block rewrite | 0.15 day |
| PhotoUploader internal token refresh | 0.1 day |
| `:review` step block rewrite (3 alerts + summary + buttons + sticky) | 0.4 day |
| Mobile sticky CTA + spacer | 0.1 day |
| Bug fixing + existing-test updates | 0.25 day |
| **Total** | **~1 day** of focused work |
