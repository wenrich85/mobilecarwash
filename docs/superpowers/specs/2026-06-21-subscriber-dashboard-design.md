# Subscriber Dashboard — Design Spec

**Date:** 2026-06-21
**Status:** Approved for planning
**Scope:** A subscriber-gated `/dashboard` home that consolidates subscription status, recurring wash-day management (with inline edit), and upcoming washes — plus the ability to add à-la-carte services both to a recurring schedule (ongoing) and to a single upcoming wash (one-off), charged off-session with a hosted-checkout fallback.

## Background

Much of the infrastructure already exists and is reused, not rebuilt:

- **Subscriptions** — `lib/mobile_car_wash/billing/subscription.ex` (`:active_for_customer/1`, `:pause/:resume/:cancel`), `subscription_plan.ex` (allowances: `basic_washes_per_month`, `deep_cleans_per_month`, `deep_clean_discount_percent`), `subscription_usage.ex` (`basic_washes_used`, `deep_cleans_used` per period). Managed today at `/account/subscription` (`SubscriptionManageLive`).
- **Recurring wash-days** — `lib/mobile_car_wash/scheduling/recurring_schedule.ex` (`frequency` :weekly/:biweekly/:monthly, `preferred_day` 1–7, `preferred_time`, `active`, `last_scheduled_date`; relationships customer/vehicle/address/service_type/subscription; actions `:create`, `:activate`, `:deactivate`, `:mark_scheduled`, `:for_customer/1`). A daily Oban worker `recurring_appointment_scheduler.ex` auto-books occurrences 7 days ahead. Managed today at `/account/recurring` (`RecurringScheduleManageLive`).
- **Appointments** — `appointment.ex` (`:book`, `:upcoming/1`, `:for_customer/1`; statuses `:pending`, `:confirmed`, `:en_route`, `:on_site`, `:in_progress`, `:completed`, `:cancelled`; nullable `recurring_schedule_id`). Add-ons attach via `appointment_add_on.ex` + `create_appointment_add_ons/3` in `scheduling/booking.ex`, size-scaled by `Pricing.calculate/2`.
- **Pricing** — `billing/pricing.ex` (`calculate/2`, `addons_total_cents/2`, `addon_lines/2`, `breakdown/1`). Add-ons are never covered by subscription — always an extra charge.
- **Auth** — `:authenticated` live_session in `router.ex` with `on_mount {MobileCarWashWeb.LiveAuth, :require_customer}`, exposing `current_customer`.
- **Payments / Stripe** — `billing/payment.ex` (`:create`, `:complete`, `:fail`, `:by_checkout_session`), `billing/stripe_client.ex` (`create_payment_intent/3`, `create_checkout_session/3`), `stripe_webhook_controller.ex` (raw-body signature verification; `checkout.session.completed` → `Booking.complete_payment`).

What is **absent** and built here: a unified dashboard home, editing recurring preferences, attaching add-ons to a recurring schedule and to an existing appointment, off-session charging, and the webhook path for add-on top-ups.

## Decisions (locked)

1. **Unified dashboard home** at `/dashboard`; existing `/account/subscription`, `/account/recurring`, `/appointments` routes remain and are reused (their domain calls), not duplicated.
2. **Add services in two places:** ongoing on a recurring schedule, and one-off on a single upcoming wash.
3. **Payment:** off-session PaymentIntent on the subscriber's saved card, **falling back to a hosted Stripe Checkout link** on failure.
4. **Recurring add-on changes apply to future auto-generated occurrences only** — already-booked washes are edited via the one-off flow.
5. **One-off edit cutoff:** an appointment is editable only while `status in [:pending, :confirmed]` **and** it starts more than **12 hours** from now.
6. **Recurring per-occurrence charge failure:** book the base wash **without** the add-ons and enqueue a customer notification (no interactive fallback exists in the 6am worker context).

## Architecture

A new `MobileCarWashWeb.DashboardLive` mounted under the existing `:authenticated` live_session, with an additional **subscription gate**: if `Subscription.active_for_customer/1` returns none, redirect to `/account/subscription` with a flash. It composes three panels from existing domain calls plus the new capabilities below.

New backend work is isolated into focused units (one responsibility each), with charging deliberately separated from add-on attachment so all entry points share one attach path.

## Components

### Dashboard LiveView — `lib/mobile_car_wash_web/live/dashboard_live.ex`

Route: `live "/dashboard", DashboardLive` inside the `:authenticated` live_session.

`mount/3` loads: active subscription + plan + current-period usage; `RecurringSchedule.for_customer/1` (with loaded add-ons); `Appointment.upcoming/1`; all active `AddOn`s for the pickers. Subscription gate runs first.

**Panel A — Subscription summary (read-only + links).** Plan name, status badge, current period end, washes-remaining (plan allowance − usage for basic washes and deep cleans). Links to `/account/subscription` for pause/resume/cancel/billing (not duplicated).

**Panel B — Recurring wash-days.** One row per schedule (vehicle · service · human cadence e.g. "Every other Tuesday at 9:00 AM"). Per row:
- Inline edit of `frequency` / `preferred_day` / `preferred_time` → `RecurringSchedule.:update_preferences`.
- Activate / deactivate / delete (existing actions).
- "Manage add-ons" toggles → replace the schedule's add-on set; a line shows the per-wash add-on cost (size-scaled) so the customer knows each future occurrence is charged off-session.
- Affordance to create a new recurring wash (reuse existing create flow).

**Panel C — Upcoming washes.** Next N from `Appointment.upcoming/1`: date/time/window, service, vehicle, current add-ons, price. If editable (decision 5), an "Add services" picker → `Appointment.:add_services` orchestration. If not editable, add-ons render read-only with a "too late to modify" note.

Empty states: no schedules → prompt to create; no upcoming washes → note that recurring will auto-book, or book now.

Ownership: every per-row/per-appointment action verifies the record's `customer_id == current_customer.id`.

### `RecurringSchedule.:update_preferences` — `recurring_schedule.ex`

Update action accepting `frequency`, `preferred_day`, `preferred_time`. No payment. Ownership enforced at the call site.

### `RecurringScheduleAddOn` — `lib/mobile_car_wash/scheduling/recurring_schedule_add_on.ex` (new) + migration

Join resource: `belongs_to :recurring_schedule`, `belongs_to :add_on`. `has_many :recurring_schedule_add_ons` added to `RecurringSchedule`. A "replace add-ons for schedule" operation (delete existing rows for the schedule, create the new set) backs the Panel-B toggles. Migration creates `recurring_schedule_add_ons` (additive). Generated via `mix ash.codegen add_recurring_schedule_add_ons`.

### `Scheduling.AppointmentServices.add/2` — `lib/mobile_car_wash/scheduling/appointment_services.ex` (new — shared core)

`add(appointment, add_on_ids)`: loads active add-ons by id, creates `AppointmentAddOn` rows with size-scaled prices (`Pricing.calculate(add_on.price_cents, vehicle.size)` — identical to the booking path), and bumps `appointment.price_cents` by the add-on delta. **Attachment only; no charging.** Reused by the interactive success path, the webhook path, and the recurring scheduler.

### `StripeClient.charge_off_session/3` — `billing/stripe_client.ex`

Creates a PaymentIntent with `customer: <stripe_customer_id>, payment_method: <default PM>, off_session: true, confirm: true`. Returns `{:ok, intent}` when status is `succeeded`, else `{:error, reason}` (`:requires_action`, `:card_declined`, `:no_payment_method`, …). Default payment method is read from the Stripe customer's invoice settings (the card the subscription bills).

**Prerequisite to verify in the plan:** `Customer.stripe_customer_id` is populated for subscribers. If it is absent or no default PM exists, `charge_off_session` returns `{:error, :no_payment_method}` and callers take the fallback path.

### One-off orchestration — `AppointmentServices.request_add_services/2` (same module as `add/2`)

`request_add_services(appointment, add_on_ids)` orchestrates the interactive one-off flow and delegates the pure attachment to `add/2`. Distinct responsibilities in one cohesive module: `add/2` attaches (no payment); `request_add_services/2` validates + charges + falls back.

Interactive one-off flow:
1. Validate: owned by customer, `status in [:pending, :confirmed]`, starts > 12h out. Otherwise `{:error, :not_editable}`.
2. Compute add-on delta via `Pricing.addons_total_cents(add_ons, vehicle.size)`.
3. `StripeClient.charge_off_session`:
   - **success** → `AppointmentServices.add/2` + create a succeeded `Payment` linked to the appointment + enqueue receipt.
   - **failure** → create a Stripe Checkout session for the delta with metadata `%{kind: "appointment_addons", appointment_id: id, add_on_ids: "id1,id2"}`; return `{:ok, checkout_url}`. Add-ons are **not** attached until the webhook confirms payment.

### Webhook extension — `stripe_webhook_controller.ex`

In the existing `checkout.session.completed` handler, branch on `metadata.kind == "appointment_addons"` → parse `appointment_id` + `add_on_ids` → `AppointmentServices.add/2` + mark the `Payment` succeeded. Existing booking-checkout sessions are unaffected (different/absent `kind`). Reuses the existing raw-body/signature pipeline.

### Recurring scheduler integration — `recurring_appointment_scheduler.ex`

In `create_appointment/2`, after the base wash is booked, if the schedule has add-ons: compute the add-on total and call `StripeClient.charge_off_session`.
- **success** → `AppointmentServices.add/2`.
- **failure** → leave the wash with no add-ons and enqueue a notification to the customer that the saved card was declined for the add-ons (with a link to update billing). The base wash still happens.

## Data Flow

- **Edit recurring preference:** DashboardLive event → ownership check → `RecurringSchedule.:update_preferences` → re-render.
- **Recurring add-ons changed:** DashboardLive event → replace `RecurringScheduleAddOn` set → re-render (affects only future occurrences).
- **One-off add services (card OK):** DashboardLive event → `:add_services` → `charge_off_session` succeeds → `AppointmentServices.add` + `Payment` → re-render with updated price.
- **One-off add services (card fails):** `:add_services` → `charge_off_session` fails → Checkout session created → LiveView redirects to `checkout_url` → customer pays → webhook `appointment_addons` → `AppointmentServices.add` + `Payment` succeeded.
- **Recurring occurrence with add-ons:** 6am worker books wash → `charge_off_session` → success attaches add-ons / failure books base wash + notifies.

## Error Handling

- Subscription gate: no active subscription → redirect + flash.
- Ownership mismatch on any action → `{:error, :unauthorized}`, generic flash, no mutation.
- Not-editable appointment (status/cutoff) → disabled UI + server-side `{:error, :not_editable}` guard (defense in depth — do not trust the client).
- Off-session decline (interactive) → checkout fallback as above; (recurring) → base wash + notification.
- `charge_off_session` with no Stripe customer / PM → treated as failure → same fallbacks.

## Testing Strategy

- **TDD** for every backend unit. Use the existing Stripe mocks (`:stripe_payment_intent_module`, `:stripe_checkout_module`) — extend the payment-intent mock to simulate both off-session success and a decline so both branches are exercised.
- `RecurringSchedule.:update_preferences` — updates fields; rejects another customer's schedule.
- `RecurringScheduleAddOn` — replace-set semantics; scheduler attaches them to generated occurrences; change affects only future occurrences (not already-booked ones).
- `AppointmentServices.add/2` — size-scaled prices match the booking path; appointment price bumps by exactly the delta.
- `:add_services` — editable-guard (status + 12h cutoff + ownership); card-success path attaches + charges; card-failure path returns a checkout_url and attaches nothing until the webhook.
- Webhook `appointment_addons` — attaches add-ons + marks Payment on completion; ignores non-add-on sessions.
- Recurring scheduler — occurrence with add-ons: success attaches; failure books base wash + enqueues notification.
- DashboardLive — subscription gate redirect; panels render; ownership enforced; not-editable appointment shows read-only.
- Full `mix precommit` green; no new compiler warnings.

## Deferred / Out of Scope

- **On-site payment (deferred feature):** replace the hosted Stripe Checkout fallback with embedded payment (Stripe Elements / Payment Element / embedded Checkout) so customers never leave the site. This build redirects to hosted Checkout on off-session failure; the on-site flow is a follow-up.
- Propagating recurring add-on changes to already-booked appointments (excluded by decision 4).
- Restyling/replacing the existing `/account/*` and `/appointments` pages (dashboard links to them as-is).
- Self-service payment-method management (handled via the existing Stripe billing portal link).
