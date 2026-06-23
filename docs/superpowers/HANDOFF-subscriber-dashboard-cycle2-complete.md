# Handoff — Subscriber Dashboard, Cycle 2 COMPLETE

**Date:** 2026-06-23
**Branch:** `main` (Cycle 2 merged; nothing on a feature branch)
**For:** the next agent picking up subscriber-dashboard follow-ups or the deferred on-site payment work

## TL;DR

Cycle 2 (à-la-carte **add-services + off-session payment**) is **DONE and merged to local `main`**
(merge commit `2510624`, `--no-ff`, **NOT pushed** — origin is intentionally behind; the user pushes
manually). Full suite green: **1324 tests, 0 failures**. Both cycles of the subscriber dashboard are now
complete. The only remaining work is optional polish follow-ups (below) and the spec-deferred **on-site
embedded payment** feature.

- **Spec (source of truth, covers BOTH cycles):**
  `docs/superpowers/specs/2026-06-21-subscriber-dashboard-design.md`
- **Cycle 2 plan (what was built, with the exact code):**
  `docs/superpowers/plans/2026-06-22-subscriber-dashboard-cycle2.md`
- **Cycle 1 handoff (the shell this built on):**
  `docs/superpowers/HANDOFF-subscriber-dashboard-cycle2.md` (named for "cycle2" but it's the
  pre-Cycle-2 handoff; the dashboard shell it describes is all merged)
- **SDD ledger (per-task record + reviews + merge):** `.superpowers/sdd/progress.md`
  (search "SUBSCRIBER DASHBOARD CYCLE 2: COMPLETE")

## What Cycle 2 shipped (merged, do NOT rebuild)

Ten commits on the merge (`2c912e5`..`e6b8755`), 9 implementation tasks. Each task was TDD
(RED→GREEN), two-stage reviewed (spec + quality), and the whole branch got a final opus review
(verdict: **ready to merge**). All six money/integration risks were verified clean (no
double-charge/double-attach; consistent integer-cents `Pricing` math at all three call sites;
server-side ownership + 12h editability; preserved webhook arms; safe default-PM degradation;
additive-only migration).

### Backend
- **`MobileCarWash.Scheduling.AppointmentServices`** (`lib/mobile_car_wash/scheduling/appointment_services.ex`)
  — the cohesive add-on module:
  - `add/2` — **shared, charge-free attach core**. Loads active add-ons, creates size-scaled
    `AppointmentAddOn` rows (`Pricing.calculate/2`), bumps `appointment.price_cents` by the delta.
    Reused by ALL three entry points. Returns `{:ok, appointment}`.
  - `request_add_services/2` — interactive one-off orchestration. Validates `editable?/1`
    (status in `[:pending, :confirmed]` AND starts **>12h** out) → computes delta
    (`Pricing.addons_total_cents/2`) → `StripeClient.charge_off_session/3`. **Success:** `add/2` +
    succeeded `Payment` + receipt; returns `{:ok, :charged}`. **Failure:** pending `Payment` + hosted
    Checkout session (metadata `kind: "appointment_addons"`); returns `{:ok, checkout_url}` (binary) and
    attaches NOTHING. **Caller enforces ownership**; this fn enforces the editable guard.
  - `complete_addon_checkout/1` — webhook completion: attaches add-ons + marks the pending `Payment`
    succeeded (looked up `by_checkout_session`). Dual-keyed metadata reads (`["k"] || [:k]`).
  - `replace_schedule_add_ons/2`, `schedule_add_on_ids/1`, `schedule_add_ons/1` — recurring-schedule
    add-on set management (delete-then-create the active set).
- **`RecurringScheduleAddOn`** join resource (`.../scheduling/recurring_schedule_add_on.ex`) +
  `has_many` on `RecurringSchedule` + registered in the `Scheduling` domain. Migration
  `priv/repo/migrations/20260623035724_add_recurring_schedule_add_ons.exs` (additive; one table).
- **`StripeClient.charge_off_session/3`** (`lib/mobile_car_wash/billing/stripe_client.ex`) — reads the
  customer's default PM from Stripe (`customer_module().retrieve/1` →
  `invoice_settings.default_payment_method`), confirms an off-session PaymentIntent. `{:ok, intent}` only
  on `"succeeded"`; else `{:error, reason}` (`:no_payment_method`, `:card_declined`,
  `{:unexpected_status, _}`). `nil` customer id short-circuits without calling Stripe.
- **`StripeClient.create_addon_checkout/5`** — hosted Checkout for the add-on delta (fallback path).
- **Subscription checkout** now sets
  `subscription_data: %{payment_settings: %{save_default_payment_method: "on_subscription"}}` so the
  default PM is reliably saved for off-session reuse (this was the user's "add SetupIntent now"
  decision, implemented with the subscription-mode-correct primitive — a standalone SetupIntent is
  redundant in subscription mode).
- **Webhook** (`stripe_webhook_controller.ex`) — `checkout.session.completed` now branches via `cond`:
  `kind == "appointment_addons"` first → `complete_addon_checkout`; then `mode == "subscription"`
  (unchanged); else `Booking.complete_payment` (unchanged).
- **Recurring scheduler** (`recurring_appointment_scheduler.ex`) — `create_appointment/2` (now `def`)
  charges + attaches the schedule's add-ons per occurrence. On decline: keeps the base wash, enqueues
  `AddOnChargeFailedWorker` (new) → `Email.addon_charge_failed/2` (new, subject
  "Action needed: card declined for add-ons").

### Frontend (`lib/mobile_car_wash_web/live/dashboard_live.ex`)
- **Panel B — "Manage add-ons":** per-schedule checkbox form → `replace_schedule_add_ons/2`
  (ownership-gated), plus a per-wash size-scaled cost line.
- **Panel C — "Add services":** picker on editable upcoming appointments → `request_add_services/2`;
  `{:ok, :charged}` re-renders, `{:ok, url}` redirects to hosted Checkout. Non-editable appts show a
  "Too late to modify" note. Ownership + editability enforced server-side.

### Test mocks / config
- `test/support/stripe_customer_mock.ex` (new) — `retrieve/1` with **id-encoded scenarios**:
  `"cus_nopm…"` → no default PM; `"cus_decline…"` → `"pm_decline"` (declines); anything else →
  `"pm_test_default"` (succeeds). **This is how tests pick the off-session branch — set the customer's
  `stripe_customer_id` accordingly.** No global mutable state.
- `test/support/stripe_payment_intent_mock.ex` (extended) — off-session success/decline clauses; the
  ORIGINAL non-off-session behavior is preserved as the fallback clause (booking/mobile flows).
- `config/test.exs` — registers `:stripe_customer_module`.

## Project conventions (unchanged — match prior cycles)

- **Convention files** `config/dev.exs`, `AGENTS.md`, `docs/customer-flows.html` are long-standing
  uncommitted working-tree edits — **never commit them**; `git stash push -u <files>` around any
  branch switch/merge and pop after. (They were stashed/popped around the Cycle-2 merge.)
- **Gate:** `mix precommit` (compile `--warnings-as-errors`, `deps.unlock --unused`, format, full test)
  must pass pristine. **New baseline: 1324 tests / 0 failures.**
- **Known flaky test (NOT a regression):** `admin_blocks_controller_test.exs:40`
  ("generates upcoming blocks for a technician") intermittently fails under full-suite parallel load
  with a DBConnection sandbox-ownership race (Oban block-gen `Task.Supervised` `bulk_create` vs the
  Ecto sandbox). It passes 6/6 in isolation and is unrelated to the subscriber dashboard. If a
  precommit run shows exactly this one failure, **re-run** — it clears. Cycle 2's clean run was the
  re-run.
- **Migrations:** Ash — `mix ash.codegen <name>` then `mix ecto.migrate`.
- **Merge:** `--no-ff` into local `main`, **do NOT push** (user pushes manually).
- **Dev server:** `set -a; source .env.dev.local 2>/dev/null; set +a; PORT=4010 mix phx.server`
  (verify `curl -s -o /dev/null -w "%{http_code}" http://localhost:4010/`).

## Follow-ups (optional polish — none block; all surfaced by the final review)

1. **`complete_addon_checkout/1` nil-guard.** A malformed webhook with `kind=appointment_addons` but a
   nil/absent `appointment_id` would `Ash.get(Appointment, nil)` → raise → 500 → Stripe retries.
   Our own `create_addon_checkout` always sets a valid id, so this is defensive only. Add a nil/parse
   guard that returns `{:error, _}` instead of raising. (`appointment_services.ex`, the
   `complete_addon_checkout/1` head.)
2. **Unique identity on `recurring_schedule_add_ons` `(recurring_schedule_id, add_on_id)`.** The only
   writer (`replace_schedule_add_ons/2`) de-dups, so no duplicates arise today; an Ash `identity` +
   DB unique index would harden against future writers.
3. **Money displays → `Pricing.format_cents/1`.** The dashboard uses `${div(cents, 100)}` (truncates
   cents) in several spots, matching the Cycle-1 whole-dollar convention. `Pricing.format_cents/1`
   already exists and renders cents correctly — switch the add-on/price displays to it.
4. **Negative-ownership tests** for `save_addons` and `add_services` (the handlers ARE gated with the
   same proven `with`-chain as the tested `save_preferences`; these would just lock the gate in).
5. **N+1 in `load_schedules`/`load_upcoming`** (per-row `Ash.get!` + per-schedule add-on reads). Fine
   at per-customer scale; revisit if dashboards grow (preload/bulk).

## Deferred feature (separate future slice — see spec §Deferred)

- **On-site embedded payment:** replace the hosted Stripe Checkout fallback with embedded payment
  (Stripe Elements / Payment Element / embedded Checkout) so customers never leave the site on an
  off-session decline. This build redirects to hosted Checkout; the embedded flow is the follow-up.
  Everything else in the design spec is now implemented.

## Next action for you

There is **no pending dashboard work** — both cycles are merged and green. If picking up the deferred
on-site payment, start from the spec §Deferred, brainstorm the embedded-payment UX, then writing-plans
→ subagent-driven-development → finishing-a-development-branch (merge `--no-ff`, no push), exactly as
Cycles 1–2 were run. If picking up a polish follow-up above, each is a small isolated change with a
clear test.
