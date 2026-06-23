# Handoff — Subscriber Dashboard, Cycle 2

**Date:** 2026-06-22
**Branch:** `main` (Cycle 1 merged; no Cycle-2 branch started yet)
**For:** the next agent picking up the subscriber-dashboard add-services + payment work

## TL;DR

Cycle 1 (the dashboard shell: gate + subscription summary + recurring edit + read-only
upcoming washes) is **DONE and merged to local `main`**. Cycle 2 adds à-la-carte
**add-services + off-session payment** to the dashboard. The next step is the
**writing-plans** skill → a Cycle-2 implementation plan → execute via
**subagent-driven-development** → **finishing-a-development-branch**. No Cycle-2
code exists yet; nothing is on a branch.

- **Spec (source of truth, covers BOTH cycles):**
  `docs/superpowers/specs/2026-06-21-subscriber-dashboard-design.md` — READ THIS FIRST.
- **Cycle 1 plan (reference for patterns/conventions):**
  `docs/superpowers/plans/2026-06-21-subscriber-dashboard-cycle1.md`
- **Brainstorming is complete.** All product decisions are locked (see below). Do NOT
  re-brainstorm. Confirm the two open prerequisites below with the user, then go
  straight to writing-plans.

## What Cycle 1 already shipped (merged, do NOT rebuild)

Merge commit `f1f7e6d` on local `main` (NOT pushed — origin is intentionally behind).

- `MobileCarWashWeb.DashboardLive` (`lib/mobile_car_wash_web/live/dashboard_live.ex`) —
  route `live "/dashboard", DashboardLive` in the `:authenticated` live_session.
  Subscription gate redirects non-subscribers to `~p"/subscribe"` (this CORRECTED the
  spec's `/account/subscription`). Three panels:
  - **A** subscription summary (read-only + link to `/account/subscription`)
  - **B** recurring wash-days: inline edit of frequency/day/time, activate/deactivate/delete,
    all ownership-gated; "Add" links to existing `/account/recurring`
  - **C** upcoming washes: **READ-ONLY** (service/date-time/vehicle/price/status + add-on COUNT)
- `RecurringSchedule.:update_preferences` update action (accepts
  `frequency`/`preferred_day`/`preferred_time`).
- Tests: `test/mobile_car_wash_web/live/dashboard_live_test.exs` (10 tests),
  `test/mobile_car_wash/scheduling/recurring_schedule_preferences_test.exs` (2 tests).
- Full suite green at merge: **1307 tests, 0 failures.**

**Existing structures in DashboardLive Cycle 2 will extend:** `mount/3` (gate +
`load_subscription/1` + `load_schedules/2` + `load_upcoming/2`), the ownership `with`-chain
pattern on every mutating handler, the per-row display maps, and the format helpers
(`format_frequency/1`, `format_day/1`, `format_time/1`, `format_status/1`, `parse_time/1`).
The Panel B/C display maps will need new keys for add-on data.

## What Cycle 2 builds (the add-services + payment slice)

1. **Add à-la-carte add-ons in two places:**
   - on a **recurring schedule** (applies to FUTURE auto-generated occurrences only) — Panel B "Manage add-ons"
   - on a **single upcoming appointment** (one-off) — Panel C "Add services"
2. **Off-session payment** on the subscriber's saved card, with a **hosted Stripe
   Checkout fallback** on failure. (On-site embedded payment stays DEFERRED — see spec.)

## Locked decisions (do NOT relitigate)

1. Add-ons on both a recurring schedule (ongoing) and one upcoming wash (one-off).
2. Off-session charge on saved card → fallback to hosted Checkout on failure.
3. Recurring add-on changes affect **FUTURE occurrences only** (already-booked washes are
   edited via the one-off flow).
4. One-off edit cutoff: an appointment is editable only while
   `status in [:pending, :confirmed]` **AND** it starts **> 12h** from now.
5. Recurring per-occurrence charge failure (6am worker): book the base wash **WITHOUT**
   the add-ons and enqueue a customer notification (no interactive fallback in the worker).
6. Charging is separated from attachment: a shared `AppointmentServices.add/2` pure-attach
   core is reused by the interactive success path, the webhook path, AND the recurring scheduler.

## OPEN PREREQUISITES to confirm with the user before/while planning

1. **Default payment method for off-session charging (VERIFY, then decide).** Verified in
   Cycle 1 prep: `Customer.stripe_customer_id` **IS reliably populated** for active
   subscribers (set in the `checkout.session.completed` webhook —
   `subscription_orchestrator.ex:212-215`). BUT the subscription-mode Checkout flow
   (`stripe_client.ex:58-80`) does **NOT** explicitly set `setup_future_usage` or
   `invoice_settings.default_payment_method`. Stripe *implicitly* attaches the card used in
   subscription-mode checkout as the customer default, so `charge_off_session/3` must
   **retrieve the customer's default PM from Stripe** (invoice settings / list PMs) before
   confirming the PaymentIntent. The locked design handles the worst case gracefully: if no
   usable default PM exists, the charge fails → **hosted Checkout fallback** → still works.
   **Action:** tell the user the off-session path may fall back to Checkout for some
   subscribers until a SetupIntent is added, and confirm that's acceptable for this build
   (it is, per the spec).
2. **Stripe is in TEST mode locally** (`.env.dev.local`, gitignored, holds `sk_test`;
   `config/dev.exs` points base_url→4010). Test config wires Stripe mocks. **The
   payment-intent mock must be extended** to simulate BOTH off-session success AND a decline
   so both branches are tested. Confirm the user is fine with that mock extension (it's
   expected — the spec's testing strategy calls for it).

## New backend units the Cycle-2 plan must cover (details in the spec §Components)

- **`RecurringScheduleAddOn`** join resource —
  `lib/mobile_car_wash/scheduling/recurring_schedule_add_on.ex` (new) +
  `has_many :recurring_schedule_add_ons` on `RecurringSchedule` + a "replace add-ons for
  schedule" op (delete existing rows, create new set). Migration via
  `mix ash.codegen add_recurring_schedule_add_ons` then `mix ecto.migrate`. Register the
  resource in the `MobileCarWash.Scheduling` domain.
- **`Scheduling.AppointmentServices`** —
  `lib/mobile_car_wash/scheduling/appointment_services.ex` (new), two functions:
  - `add/2` (pure attach, NO payment): `add(appointment, add_on_ids)` loads active add-ons,
    creates size-scaled `AppointmentAddOn` rows via `Pricing.calculate(add_on.price_cents,
    vehicle.size)`, bumps `appointment.price_cents` by the delta. Shared by ALL callers.
  - `request_add_services/2` (interactive orchestration): validate editable (owned +
    `status in [:pending,:confirmed]` + starts >12h) → compute delta via
    `Pricing.addons_total_cents/2` → `charge_off_session` → success: `add/2` + succeeded
    `Payment` + receipt; failure: create Checkout session with metadata
    `%{kind: "appointment_addons", appointment_id: id, add_on_ids: "id1,id2"}` and return
    `{:ok, checkout_url}` (attach NOTHING until the webhook confirms).
- **`StripeClient.charge_off_session/3`** — `lib/mobile_car_wash/billing/stripe_client.ex`.
  PaymentIntent with `customer` + `payment_method: <default PM>` + `off_session: true` +
  `confirm: true`. `{:ok, intent}` when `succeeded`, else `{:error, reason}`
  (`:requires_action`, `:card_declined`, `:no_payment_method`, …). Reads default PM from the
  Stripe customer.
- **Webhook extension** — `stripe_webhook_controller.ex`: in the existing
  `checkout.session.completed` handler, branch on `metadata.kind == "appointment_addons"` →
  parse `appointment_id` + `add_on_ids` → `AppointmentServices.add/2` + mark the `Payment`
  succeeded. Existing booking-checkout sessions unaffected (different/absent `kind`). Reuses
  the existing raw-body/signature pipeline (confirmed present).
- **Recurring scheduler integration** — `recurring_appointment_scheduler.ex`
  `create_appointment/2`: after the base wash is booked, if the schedule has add-ons →
  `charge_off_session` → success `add/2` / failure leave base wash + enqueue a "card declined
  for add-ons" customer notification. **NOTE the existing gap (mem 10111):**
  `RecurringAppointmentScheduler` bypasses the `Booking` orchestrator, so it has NO
  vehicle-size pricing today — the add-on attach must use the size-scaled `add/2` path
  explicitly.
- **DashboardLive UI** — Panel B "Manage add-ons" (toggle/replace the schedule's add-on set;
  show per-wash size-scaled add-on cost so the customer knows each future occurrence is
  charged) and Panel C "Add services" picker on editable appointments (drives
  `request_add_services/2`; on `{:ok, checkout_url}` redirect to it; non-editable appts
  render add-ons read-only with a "too late to modify" note). Ownership + the 12h/status
  editable guard enforced **server-side** (defense in depth — do not trust the client).

## Key existing code map (verified; paths current as of merge)

- Add-on attach reference: `create_appointment_add_ons/3` in `scheduling/booking.ex`;
  size-scaled via `Pricing.calculate/2`. `appointment_add_on.ex` (`:create` accepts
  `appointment_id`/`add_on_id`/`price_cents`), `add_on.ex`.
- Pricing: `billing/pricing.ex` — `calculate/2`, `addons_total_cents/2` (vehicle_size arg,
  added in booking-hardening), `addon_lines/2`, `breakdown/1`. Add-ons are NEVER covered by a
  subscription — always an extra charge.
- Recurring: `scheduling/recurring_schedule.ex` (now has `:update_preferences`),
  `recurring_appointment_scheduler.ex` (daily 6am Oban worker, `create_appointment/2`).
- Appointments: `scheduling/appointment.ex` — `:upcoming` (status in [:pending,:confirmed]
  and `scheduled_at > now`), `:for_customer`, statuses, nullable `recurring_schedule_id`,
  `has_many :appointment_add_ons`.
- Payments/Stripe: `billing/payment.ex` (`:create`/`:complete`/`:fail`/`:by_checkout_session`),
  `billing/stripe_client.ex` (`create_payment_intent/3`, `create_checkout_session/3`,
  `create_subscription_checkout/3`, `create_billing_portal_session/2`),
  `stripe_webhook_controller.ex` (raw-body sig verify; `checkout.session.completed` →
  `Booking.complete_payment`).
- Subscription gate read: `Subscription.:active_for_customer` (customer_id arg; status in
  [:active,:paused,:past_due]).
- Test fixtures pattern (Stripe-mocked): `SubscriptionPlan.:create` triggers
  `SyncStripeCatalog` but it's mocked in test env (`stripe_price_mock`/`stripe_product_mock`).
  See `test/mobile_car_wash_web/live/booking_subscription_price_test.exs` and the Cycle-1
  `dashboard_live_test.exs` helpers (`register_and_sign_in/1`, `create_plan/0`,
  `create_active_subscription/2`, `create_schedule/1`, `create_upcoming_appointment/1`) —
  copy/extend these.
- LiveView test convention: `ConnCase`, `register_with_password`, POST
  `/auth/customer/password/sign_in`, `recycle(conn)`, then `live(conn, path)`.

## Project conventions (IMPORTANT — match prior cycles)

- **Branch:** create `feature/subscriber-dashboard-cycle2` from `main` BEFORE any
  implementation. Don't implement on `main`.
- **Convention files** `config/dev.exs`, `AGENTS.md`, `docs/customer-flows.html` are
  long-standing uncommitted working-tree edits — **stash them
  (`git stash push -u <files>`) around branch switches/merges and pop after.** Never commit them.
- **Gate:** `mix precommit` (compile `--warnings-as-errors`, `deps.unlock --unused`, format,
  full test) must pass. Baseline is **1307 tests / 0 failures**. Output must be pristine.
- **Migrations:** Ash — `mix ash.codegen <name>` then `mix ecto.migrate`. (Cycle 2 adds ONE
  migration: `recurring_schedule_add_ons`. Verify it's additive / no unintended drift.)
- **Merge:** `--no-ff` into local `main`, **do NOT push** (origin is intentionally behind;
  user pushes manually).
- **Ledger:** `.superpowers/sdd/progress.md` — append a new "Cycle 2" plan section; record
  each task `complete (commit, review clean)`; trust it + `git log` after compaction. The
  Cycle-1 section is already there (search "SUBSCRIBER DASHBOARD CYCLE 1: COMPLETE").
- **SDD scripts:**
  `~/.claude/plugins/cache/claude-plugins-official/superpowers/6.0.3/skills/subagent-driven-development/scripts/{task-brief,review-package}`.
- **Stripe TEST mode:** extend the payment-intent mock to simulate off-session SUCCESS and
  DECLINE (the spec's testing strategy requires both branches exercised).

## Dev server

Run on port 4010 with the env sourced:
```bash
set -a; source .env.dev.local 2>/dev/null; set +a
PORT=4010 mix phx.server
```
Verify: `curl -s -o /dev/null -w "%{http_code}" http://localhost:4010/`.

## Next action for you

1. Read the spec (§Components / §Data Flow / §Error Handling / §Testing Strategy) and skim
   the Cycle-1 plan for the established patterns.
2. Confirm the two open prerequisites above with the user (default-PM/fallback behavior;
   payment-intent mock extension).
3. Create `feature/subscriber-dashboard-cycle2` from main (stash convention files first).
4. Invoke **writing-plans** → `docs/superpowers/plans/2026-06-22-subscriber-dashboard-cycle2.md`.
   Suggested task order: (a) `AppointmentServices.add/2` + tests; (b) `RecurringScheduleAddOn`
   join + migration + replace-set; (c) `StripeClient.charge_off_session/3` + mock extension;
   (d) `request_add_services/2` orchestration (editable guard + charge + fallback);
   (e) webhook `appointment_addons` branch; (f) recurring scheduler add-on charging;
   (g) Panel B "manage add-ons" UI; (h) Panel C "add services" UI + editable guard.
5. Execute via **subagent-driven-development** (implementer + task-reviewer per task, final
   whole-branch review on opus).
6. `mix precommit` → **finishing-a-development-branch** (merge --no-ff, no push).
