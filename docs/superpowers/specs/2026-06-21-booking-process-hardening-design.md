# Booking Process Hardening — Design Spec

**Date:** 2026-06-21
**Status:** Approved for planning
**Scope:** Eight booking-flow fixes/features surfaced by a code analysis of the single-page booking flow, plus two opt-in extras.

## Background

The customer-facing booking flow is a single-page progressive-reveal LiveView
(`lib/mobile_car_wash_web/live/booking_live.ex`) with section-gating logic in
`lib/mobile_car_wash/booking/booking_sections.ex` and a transactional submit path
in `lib/mobile_car_wash/scheduling/booking.ex`. An analysis of the flow surfaced
four behavioral concerns, one pricing-design question, four test gaps, and two
lower-priority enhancements.

Reading the code corrected two of the original findings:

- **Guest email collision** is already handled — `ensure_customer/1`
  (`booking_live.ex:1305-1307`) returns
  `"An account with this email already exists. Please sign in instead."` as
  `guest_error`. Remaining work is a sign-in affordance, not a bugfix.
- **Confirmed-time notification** is mostly built — `BlockOptimizer.close_and_optimize/1`
  (`lib/mobile_car_wash/scheduling/block_optimizer.ex:119-129`) already enqueues
  **SMS + push** "block scheduled" notifications, fired both on full-block close
  (`booking.ex:97-106`) and the midnight cron (`CloseExpiredBlocksWorker`).
  Remaining work is email parity only.

## Work Items

### A. Out-of-area address → waitlist capture *(new behavior)*

**Problem:** An address whose ZIP is outside the service area resolves to
`zone: nil`. Today the flow shows a yellow warning but still lets the customer
pay — taking money for a job the route optimizer cannot place (proximity
validation in `booking.ex` requires populated coordinates and an in-zone cluster).

**Decision:** Waitlist / contact-me. Block payment; capture the lead.

**Design:**

- New Ash resource `MobileCarWash.Marketing.Waitlist` in the existing `marketing`
  domain (alongside `referrals.ex`). Attributes:
  - `email` (string, required)
  - `name` (string, nullable)
  - `phone` (string, nullable)
  - `address_text` (string) — the address the customer entered
  - `zip` (string)
  - `latitude` / `longitude` (float, nullable)
  - `requested_service_slug` (string, nullable)
  - timestamps
  - Action `:join` (create). Public action; `authorize?: false` is acceptable
    since this is an unauthenticated lead-capture write — mirror how guest
    customer creation already bypasses authorization.
- In `booking_live.ex`: when the selected/entered address has `zone == nil`,
  the Review & Pay section renders a "We're not in your area yet — get notified"
  panel instead of the Pay button. It reuses the email already entered (guest
  form or signed-in customer) and the address fields, and submits a
  `join_waitlist` event that creates the `Waitlist` row and shows a confirmation
  flash ("Thanks — we'll let you know when we reach your area.").
- **Server-side guard:** the `confirm_booking` handler must reject a booking
  whose address zone is `nil`, independent of the client UI (defense in depth,
  matching the existing server-side `payable?` guard pattern). On a nil-zone
  attempt it returns an error rather than creating an appointment/payment.

**Out of scope:** admin UI for viewing/managing the waitlist; automated
"you're now in range" outreach. The row is captured for later manual use.

### B. Geocoder failure surfacing *(bugfix)*

**Problem:** `handle_async(:geocode_suggest, {:ok, {:error, _}}, ...)` and the
`{:exit, _}` clause (`booking_live.ex:1274-1280`) collapse failures into an empty
suggestion list with no user-facing message. When both geocoder backends are
down, the typeahead silently shows nothing.

**Design:**

- Add a `geocoder_error` assign (boolean or message string), default cleared.
- On `{:error, _}` / `{:exit, _}`, set `geocoder_error` and clear
  `loading_suggestions`.
- Clear `geocoder_error` on the next successful suggest and on a new query.
- Render an inline message near the address search: "Address lookup is having
  trouble right now — please enter your address manually below," and expand /
  surface the existing manual-entry form.

### C. Guest-email sign-in affordance *(UX polish)*

**Problem:** When a guest enters an email that already belongs to a registered
account, `ensure_customer/1` correctly refuses but only surfaces a flat error
string with no path forward.

**Design:**

- When `confirm_booking` receives the existing-account error from
  `ensure_customer`, render a sign-in call-to-action (link to the sign-in page)
  alongside the message, rather than a bare flash.
- Booking state is already preserved across navigation by `SessionCache`
  (Postgres-backed, CSRF-derived session id), so a round-trip to sign in and
  back restores the in-progress booking. Verify this restoration path works;
  no new persistence mechanism is introduced.

### D. Email block-scheduled parity *(feature)*

**Problem:** When the optimizer assigns a confirmed arrival time, customers get
SMS + push but no email.

**Design:**

- Add `MobileCarWash.Notifications.EmailBlockScheduledWorker`, modeled on
  `booking_confirmation_worker.ex` (the email confirmation worker) and the
  data-loading shape of `push_block_scheduled_worker.ex`
  (load appointment / service type / address with `authorize?: false`).
- Reuse / add an email template consistent with the existing block-scheduled
  push/SMS content ("your wash is confirmed for <time>").
- Enqueue it alongside SMS + push in
  `BlockOptimizer.enqueue_notifications/1` (`block_optimizer.ex:119-129`).

### E. Add-on vehicle-size multiplier *(behavior change)*

**Problem:** Add-ons are charged flat regardless of vehicle size
(`booking.ex:67-68` via `Pricing.addons_total_cents/1`), while the base wash
scales with size. **Decision:** apply the size multiplier to all add-ons (no
per-add-on opt-out flag).

**Design:**

- `Pricing`: introduce size-aware add-on totaling so the per-add-on amount is
  multiplied by the vehicle-size multiplier (`Pricing.multiplier/1`). Update
  `breakdown/1` so the receipt line items and `addons_total_cents` reflect the
  sized amounts, keeping the hero consistent with the charge.
- `booking.ex` (`create_booking/1`, lines ~66-68): compute the add-on total using
  the same size-aware path so the persisted/charged price matches the hero.
- Keep the existing rule that subscription discount is computed off the *base*
  price only (documented in `pricing.ex:90-98`); the add-on multiplier is
  independent of discounts.
- Both the live hero (`Pricing.breakdown/1`) and the server charge path
  (`booking.ex`) MUST produce identical totals — this parity is the acceptance
  criterion.

### F–I. Test gaps *(tests)*

Existing logic is implemented but uncovered. Add tests:

- **F. Vehicle-size pricing through the LiveView** — selecting an SUV/pickup
  updates the price hero by the correct multiplier end-to-end (not just the
  pure `Pricing` unit, but the LiveView path).
- **G. Add-on summation with the size multiplier** — locks in item E: add-ons on
  a sized vehicle total correctly in both `Pricing.breakdown/1` and the persisted
  appointment price. Write this *after* E.
- **H. Loyalty toggle** — redeeming loyalty zeros a covered basic wash / applies
  the deep-clean percentage, and `Loyalty.redeem` is invoked at payment time.
- **I. Referral application + mutual exclusivity** — a valid referral code applies
  the discount; loyalty and referral cannot both apply (UI hides referral when
  loyalty is active — assert the exclusivity, not just the happy path).

### J. Capacity hint *(extra, opted in)*

**Design:** In the schedule/block picker, surface remaining capacity using the
existing `:appointment_count` aggregate against `capacity` (e.g. "Only X spots
left"). Display-only; no change to booking logic. Show only when remaining is low
(threshold to be set in the plan, e.g. ≤ 3).

### K. Mobile PaymentIntent path test *(extra, opted in)*

**Design:** Add coverage for the `payment_flow: :mobile` branch of
`create_payment_and_checkout` (currently exercised only implicitly). Use the
existing Stripe mock (`config :mobile_car_wash, :stripe_module`) to assert a
PaymentIntent is created and the correct result shape (client secret) is returned.

## Sequencing & Dependencies

- **A** depends on the new `Waitlist` resource existing first.
- **E** must land before **G** (the test locks in the new multiplier behavior).
- All other items are independent and can be done in any order.
- Risk order: behavior changes (A, E) are highest-risk; their tests (G, plus A's
  server-guard test) lock them down. B, C, D, J, K are lower-risk and isolated.

## Testing Strategy

- TDD per item where logic changes (A guard, B failure branch, E multiplier,
  F–I, K). UI-polish items (C, J) get LiveView render assertions.
- The E parity check (hero total == charged total) is the single most important
  assertion and should exist at both the `Pricing` unit level and the
  `booking_live` / `Booking.create_booking` integration level.
- Full booking + billing suites must stay green; no new compiler warnings
  (per `mix precommit`).

## Out of Scope

- Admin UI for the waitlist.
- Automated "now in range" customer outreach.
- Per-add-on multiplier opt-out flags.
- Reworking the subscription/loyalty/referral stacking rules (only adding tests).
- Hard-blocking (vs waitlisting) out-of-area addresses.
