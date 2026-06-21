# Handoff — Subscriber Dashboard

**Date:** 2026-06-21
**Branch:** `main` (no feature branch started yet)
**For:** the next agent picking up the subscriber-dashboard feature

## TL;DR

A design spec for a **subscriber dashboard** is written and committed. The next
step is the **writing-plans** skill → an implementation plan → execute via
**subagent-driven-development** → **finishing-a-development-branch**. No code has
been written for this feature yet; nothing is on a branch.

- **Spec (approved, committed `04476d1`):**
  `docs/superpowers/specs/2026-06-21-subscriber-dashboard-design.md` — READ THIS FIRST. It is the source of truth for scope and decisions.
- **Brainstorming is complete.** All product decisions are locked (see the spec's "Decisions (locked)" section). Do NOT re-brainstorm; go straight to writing-plans after the user confirms any open questions below.

## What the feature is

A subscriber-gated `/dashboard` home that consolidates existing scattered pages
and adds two new capabilities:

1. **Unified dashboard** (`MobileCarWashWeb.DashboardLive`, new route under the
   existing `:authenticated` live_session) with three panels:
   - A: subscription summary (read-only + links to `/account/subscription`)
   - B: recurring wash-days — inline edit of frequency/day/time + manage add-ons
   - C: upcoming washes — one-off "add services" on still-editable appointments
2. **Add à-la-carte services** in two places:
   - on a **recurring schedule** (applies to FUTURE auto-generated occurrences only)
   - on a **single upcoming appointment** (one-off)
3. **Payment:** off-session PaymentIntent on the subscriber's saved card, with a
   **hosted Stripe Checkout fallback** on failure. (On-site embedded payment is a
   noted DEFERRED feature — not in this build.)

## Locked decisions (do not relitigate)

1. Unified `/dashboard`; existing `/account/subscription`, `/account/recurring`, `/appointments` stay and are reused, not duplicated.
2. Add-ons on both recurring schedule (ongoing) and one upcoming wash (one-off).
3. Off-session charge on saved card → fallback to hosted checkout on failure.
4. Recurring add-on changes affect FUTURE occurrences only.
5. One-off edit cutoff: appointment editable only while `status in [:pending, :confirmed]` AND starts > 12h out.
6. Recurring per-occurrence charge failure: book base wash WITHOUT add-ons + notify customer (no interactive fallback in the 6am worker).

## OPEN QUESTIONS to confirm with the user before/while planning

1. **Subscriber-gate destination** — spec redirects non-subscribers from `/dashboard` to `/account/subscription`. Confirm that's right vs. a plans/pricing page.
2. **`Customer.stripe_customer_id` prerequisite** — the off-session charge assumes subscribers have a Stripe customer + default payment method stored from their subscription. VERIFY this field is actually populated for subscribers (grep `stripe_customer_id` on the Customer resource + how subscription checkout links it). If not reliably populated, the off-session path always falls back to checkout — which works, but tell the user.
3. **Scope split (optional)** — sizable (~12–15 TDD tasks). User is OK as one plan but offered to split (dashboard + recurring edit first; add-services + payment second) if preferred.

## New backend units the plan must cover (details in the spec)

- `RecurringSchedule.:update_preferences` (edit frequency/day/time)
- `RecurringScheduleAddOn` join resource + migration (`mix ash.codegen add_recurring_schedule_add_ons`) + `has_many` on RecurringSchedule + replace-set semantics
- `Scheduling.AppointmentServices` — `add/2` (pure attach: size-scaled `AppointmentAddOn` rows + bump `price_cents`, shared by all callers) and `request_add_services/2` (interactive orchestration: validate editable → charge off-session → success attach / failure checkout fallback)
- `StripeClient.charge_off_session/3` (PaymentIntent `customer`+`payment_method`+`off_session: true`+`confirm: true`; default PM from Stripe customer invoice settings)
- Webhook extension in `stripe_webhook_controller.ex`: `checkout.session.completed` with `metadata.kind == "appointment_addons"` → `AppointmentServices.add/2` + mark Payment
- `recurring_appointment_scheduler.ex` `create_appointment/2` integration: charge off-session for schedule add-ons; success attach / failure base-wash-only + notify
- `DashboardLive` + route + subscription gate + ownership checks + tests

## Key existing code map (verified this session)

- Subscription: `lib/mobile_car_wash/billing/subscription.ex` (`:active_for_customer/1`), `subscription_plan.ex` (allowances), `subscription_usage.ex` (usage per period)
- Recurring: `lib/mobile_car_wash/scheduling/recurring_schedule.ex` (frequency/preferred_day/preferred_time/active; `:create`/`:activate`/`:deactivate`/`:for_customer`), `recurring_appointment_scheduler.ex` (daily 6am Oban worker, `create_appointment/2`)
- Appointments: `appointment.ex` (`:book`, `:upcoming/1`, `:for_customer/1`, statuses, nullable `recurring_schedule_id`), `appointment_add_on.ex`, `add_on.ex`
- Add-on attach pattern: `create_appointment_add_ons/3` in `scheduling/booking.ex`; size-scaled via `Pricing.calculate/2`
- Pricing: `billing/pricing.ex` (`addons_total_cents/2`, `addon_lines/2`, `breakdown/1`)
- Auth: `router.ex` `:authenticated` live_session, `on_mount {MobileCarWashWeb.LiveAuth, :require_customer}`, `current_customer` assign
- Reference customer LiveViews: `subscription_manage_live.ex`, `recurring_schedule_manage_live.ex`, `appointments_live.ex`
- Payments/Stripe: `billing/payment.ex`, `billing/stripe_client.ex` (`create_payment_intent/3`, `create_checkout_session/3`), `stripe_webhook_controller.ex` (raw-body sig verify)
- LiveView test convention: `ConnCase`, `register_with_password`, POST sign-in, `recycle(conn)`, then `live(conn, path)` (see `recurring_schedule_manage_live_test.exs`)

## Project conventions (IMPORTANT — match prior sessions)

- **Branch:** create `feature/subscriber-dashboard` from `main` before any implementation. Don't implement on `main`.
- **Convention files** `config/dev.exs`, `AGENTS.md`, `docs/customer-flows.html` are long-standing uncommitted working-tree edits — **stash them (`git stash push -u <files>`) around branch switches/merges and pop after**. Do not commit them.
- **Gate:** `mix precommit` (compile --warnings-as-errors, deps.unlock --unused, format, test) must pass. Full suite is currently ~1297 tests / 0 failures.
- **Migrations:** Ash — `mix ash.codegen <name>` then `mix ecto.migrate`.
- **Merge:** `--no-ff` into local `main`, **do NOT push** (origin is intentionally behind — user pushes manually).
- **Ledger:** `.superpowers/sdd/progress.md` — append a new plan section; record each task `complete (commit, review clean)`; trust it + `git log` after compaction.
- **SDD scripts:** `~/.claude/plugins/cache/claude-plugins-official/superpowers/6.0.3/skills/subagent-driven-development/scripts/{task-brief,review-package}`.
- **Stripe is in TEST mode locally.** `.env.dev.local` (gitignored) holds `sk_test`. `config/dev.exs` (uncommitted) points base_url→4010. Test config wires Stripe mocks (`:stripe_payment_intent_module` = `StripePaymentIntentMock`, etc. in `config/test.exs` + `test/support/`). Extend the payment-intent mock to simulate off-session success AND decline for the new charge path.

## Dev server

Run on port 4010 with the env sourced:
```bash
set -a; source .env.dev.local 2>/dev/null; set +a
PORT=4010 mix phx.server
```
(Restarted at handoff time; verify with `curl -s -o /dev/null -w "%{http_code}" http://localhost:4010/`.)

## Recently completed this session (context)

- **Booking process hardening** merged to local main (`--no-ff`, merge commit `775c817`, NOT pushed). 12 tasks: out-of-area waitlist + server nil-zone guard, geocoder failure surfacing, guest sign-in affordance, email block-scheduled parity, add-on vehicle-size multiplier (charge+hero parity), discount/pricing/mobile-payment tests. Full review + precommit green. See `.superpowers/sdd/progress.md` and `docs/superpowers/{specs,plans}/2026-06-21-booking-process-hardening*`.

## Next action for you

1. Read the spec. Confirm the three open questions with the user.
2. Create `feature/subscriber-dashboard` from main (stash convention files first).
3. Invoke **writing-plans** to produce `docs/superpowers/plans/2026-06-21-subscriber-dashboard.md`.
4. Execute via **subagent-driven-development** (implementer + task-reviewer per task, final whole-branch review).
5. `mix precommit` → **finishing-a-development-branch** (merge --no-ff, no push).
