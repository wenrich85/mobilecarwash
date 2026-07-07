# Handoff — Admin Manual-Appointments & Blocks-Calendar Follow-ups

**Date:** 2026-07-07
**For:** the next agent picking up the four follow-up Work Contracts
**Repo:** MobileCarWash (Elixir / Phoenix LiveView / Ash / AshPostgres)
**Prereq shipped:** the admin manual-appointment + blocks-calendar feature is merged to `main` (merge commit `e6cf4bc`) and pushed to `origin/main`. `mix precommit` was green (1345 tests, 0 failures). The feature branch is deleted.

---

## What already shipped (the ground you're building on)

Two admin surfaces plus one orchestrator, all live on `main`:

- **Blocks week-calendar** — `lib/mobile_car_wash_web/live/admin/blocks_live.ex` at `/admin/blocks`. Click a day → add block; click an empty block → delete; booked blocks show a "Locked" marker; an "Optimize Now" button exists on booked-open blocks. Guarded delete via `MobileCarWash.Scheduling.Blocks.delete_block/1` (`:ok | {:error, :block_has_appointments} | {:error, :block_not_found}`).
- **Manual-appointment form** — `lib/mobile_car_wash_web/live/admin/manual_appointment_live.ex` at `/admin/appointments/new` (linked from Dispatch). Existing/new client toggle, inline vehicle+address, service+time, optional tech, "waive payment" (comp) with required reason, "notify client" toggle (default on).
- **Orchestrator** — `MobileCarWash.Scheduling.Booking.admin_create_booking/1` (in `lib/mobile_car_wash/scheduling/booking.ex`). Transactional; resolves existing-or-new client (dedupe by email), vehicle, address; creates a confirmed standalone appointment via `Appointment` action `:admin_book`; always records a `Payment` via `:record_manual` (full `amount_cents`, `collected_cents` = 0 when waived else collected; `comped` + `comp_reason`); records cash flow for `collected_cents` only; enqueues notifications only when `notify_client?`.
- **Payment comp fields** — `collected_cents`, `comped`, `comp_reason` on `MobileCarWash.Billing.Payment` (migration `20260707160418`).

Design + plan for the above: `docs/superpowers/specs/2026-07-07-admin-manual-appointments-and-blocks-calendar-design.md` and `docs/superpowers/plans/2026-07-07-admin-manual-appointments-and-blocks-calendar.md`.

---

## The four Work Contracts to do

These live on the **wingineer.com** production board, project **Mobile Car Wash** (`proj_5e4d65db-1fbc-4f72-848a-2dcc60e48098`), currently in `draft`. The contract itself is the source of truth for goal / items / acceptance criteria — pull it with `wing task show <id>`.

| # | ID | Prio | Title |
|---|----|------|-------|
| 1 | `wc_cdcae7c5-c107-4d19-ac42-65bd1138cd21` | p2 | Reuse existing vehicle & address in admin manual-appointment form |
| 2 | `wc_ffbc7448-8444-42c9-bc38-97c3a826a92c` | p3 | Support partial "amount collected" on non-waived manual bookings |
| 3 | `wc_8114abc4-3d4e-4133-b961-cfad32a3eb03` | p2 | Restore block-cancel action on the admin blocks calendar |
| 4 | `wc_8dba7ac8-ed8f-4794-bb58-b3f9af190bea` | p2 | Guard admin-booking reminders to future-dated appointments only |

**Suggested order:** 3 → 4 → 1 → 2. (3 and 4 are self-contained; 1 and 2 both touch the manual-appointment form and can share a session.)

### 1 — Reuse existing vehicle & address (`wc_cdcae7c5`)
The manual form always inserts a NEW `Vehicle` + `Address` for the client, even an existing one, because it renders no picker and `build_params`/`put_vehicle`/`put_address` always fall through to the new-record clauses. The orchestrator's `resolve_vehicle`/`resolve_address` already honor `:vehicle_id`/`:address_id` fast-paths — you only need UI + wiring.
- Files: `lib/mobile_car_wash_web/live/admin/manual_appointment_live.ex`, `lib/mobile_car_wash/scheduling/booking.ex`.
- Validate: `mix test test/mobile_car_wash_web/live/admin/manual_appointment_live_test.exs`.

### 2 — Partial "amount collected" (`wc_ffbc7448`)
Non-waived manual bookings default `collected_cents` to full price; add an editable "amount collected" field (visible when not waiving), parse to integer cents, pass `:collected_cents`. Orchestrator already accepts it.
- Files: same two as #1.
- Validate: `mix test test/mobile_car_wash/scheduling/admin_create_booking_test.exs test/mobile_car_wash_web/live/admin/manual_appointment_live_test.exs`.

### 3 — Restore block-cancel on calendar (`wc_8114abc4`)
The calendar rewrite dropped the old list view's "Cancel block" action; booked blocks now have no admin action (only "Locked"). Add a Cancel control on `status == :open` blocks that have appointments; a `cancel_block` handler that sets `status: :cancelled` (block `:update` already supports it). Cancel preserves appointments (unlike delete, which stays empty-only).
- Files: `lib/mobile_car_wash_web/live/admin/blocks_live.ex`, `lib/mobile_car_wash/scheduling/appointment_block.ex`.
- Validate: `mix test test/mobile_car_wash_web/live/admin/blocks_live_calendar_test.exs`.

### 4 — Guard reminders to future-only (`wc_8dba7ac8`)
`:admin_book` deliberately allows past dates. But `Booking.admin_create_booking`'s notify path enqueues reminders at `scheduled_at - 24h`; for a past date that's already past and fires immediately. Only enqueue the 24h reminders (`enqueue_appointment_reminder` / `enqueue_sms_reminder` / `enqueue_push_reminder`) when the reminder time is in the future. Do NOT touch the past-date allowance on `:admin_book`.
- Files: `lib/mobile_car_wash/scheduling/booking.ex` (`maybe_notify_admin_booking`).
- Validate: `mix test test/mobile_car_wash/scheduling/admin_create_booking_test.exs`.

---

## How to pull / claim / complete a contract (wing)

The `wing` CLI is in the wingineer repo at `/Volumes/mac_external/Development/Business/wingineer/wingineer-platform`. Build once: `go build -o /tmp/wingbin ./services/wing`.

Auth: a valid production session is stored in `~/.config/wing/config.yaml` (`wing login` as `wenrich85@gmail.com`, `url: https://wingineer.com/api`). **The `wak_…` key in the repo's `.mcp.json` is local-dev only (401 on prod) — do not use it against production.** Set the project per command:

```bash
export WING_PROJECT=proj_5e4d65db-1fbc-4f72-848a-2dcc60e48098
/tmp/wingbin task list                       # see the board
/tmp/wingbin task show  wc_8114abc4-...       # full contract (goal/items/criteria)
/tmp/wingbin task ready wc_8114abc4-...       # draft -> ready
/tmp/wingbin task claim wc_8114abc4-...       # claim it
/tmp/wingbin task start wc_8114abc4-...       # start work
/tmp/wingbin task prompt wc_8114abc4-...      # generate an implementation prompt
# ...do the work in the MobileCarWash repo...
/tmp/wingbin task evidence wc_8114abc4-... ... # attach evidence (test output)
/tmp/wingbin task review wc_8114abc4-...      # submit for review (in_review)
```

Agents can take a contract to `in_review`; marking `done` is owner-only. Alternatively, MCP-compatible agents can use the `workmcp` adapter tools (`get_next_task`, `get_work_contract`, `claim_task`, `start_task`, `generate_prompt`, `submit_evidence`, `report_blocked`, `submit_for_review`) — set `WING_URL`, `WING_API_KEY` (a real prod key), `WING_PROJECT_ID`.

---

## MobileCarWash working conventions (read before coding)

- **Process:** use the superpowers workflow — TDD (write the failing test first), `superpowers:requesting-code-review` before finishing. Each contract is small; a branch per contract off `main` is fine.
- **Green gate:** `mix precommit` must pass — it runs `compile --warnings-as-errors`, `deps.unlock --unused`, `format`, and the full test suite. CI (`.github/workflows/ci.yml`) runs the same. Do not leave compiler warnings (e.g. never put `@doc` inside an Ash action DSL block — use `description(...)`).
- **Never commit these convention files:** `config/dev.exs`, `AGENTS.md`, `docs/customer-flows.html`. Use explicit `git add <paths>` only — never `git add -A`/`.`.
- **Dev server:** runs on **port 4010** (not 4000).
- **Money:** integer cents everywhere. `amount_cents` = full value, `collected_cents` = actually collected.

### Session-learned gotchas that WILL bite you (from building the base feature)

- **Oban runs `testing: :inline` in tests** — jobs execute on insert, so `assert_enqueued`/`refute_enqueued` are trivially empty and give false greens. Wrap enqueue-assertion tests in `Oban.Testing.with_testing_mode(:manual, fn -> ... end)`. Directly relevant to **#4** (and #2 if you assert notifications).
- **Cash-flow accounts must be seeded** in any test that calls `admin_create_booking` with a non-zero collected amount (`CashFlow.Engine.record_deposit` does `Ash.get!` on an expense account and raises if unseeded). Copy the account-seeding `setup` from `test/mobile_car_wash_web/live/admin/cash_flow_live_test.exs`. Relevant to **#2**.
- **Admin LiveView test auth:** there is no shared helper — copy the `create_admin/0` + `sign_in/2` pattern from `test/mobile_car_wash_web/live/admin/dispatch_live_command_center_test.exs`. Relevant to **#1, #3**.
- **Blocks-calendar test dates must land in the visible (current) week** — the calendar mounts on the current Mon–Sun and tests don't navigate. Use a Thursday-of-this-week slot (see `this_week_slot/0` in `test/mobile_car_wash_web/live/admin/blocks_live_calendar_test.exs`), not `now + N days` (weekend-flaky). Relevant to **#3**.
- **Creating a `Vehicle`/`Address` for a customer** needs `Ash.Changeset.force_change_attribute(:customer_id, id)` — `customer_id` is not in their create `accept` lists. Relevant to **#1**.
- **`:admin_book` intentionally allows past dates and has no capacity/availability check** — that's the admin override; don't "fix" it. Relevant to **#4**.
- Post-commit side effects in `admin_create_booking` are wrapped in `try/rescue` + `Logger` so a ledger failure can't turn a committed booking into a false error — keep that property if you touch that block.

---

## Definition of done (per contract)

Each contract's own **Acceptance Criteria** (via `wing task show`) govern. In all cases: new/updated tests are green, `mix precommit` passes, only the intended files are committed (no convention files), and the contract is moved to `in_review` with the test output as evidence.
