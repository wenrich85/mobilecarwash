# Admin: Manual Appointments & Blocks Calendar — Design

**Date:** 2026-07-07
**Status:** Approved (design), pending spec review
**Author:** brainstorming session

## Problem

The admin (solo operator) needs two capabilities that don't exist today:

1. **Quickly add and delete appointment blocks** (the bookable time windows).
   Blocks exist as an Ash resource and are managed through an API controller +
   a bare `/admin/blocks` LiveView, but there's no fast visual way to open and
   remove availability.
2. **Manually create appointments and bypass payment for certain clients while
   still recording the transaction.** There is no admin "create appointment
   directly" path today, and when an appointment is $0 the system skips creating
   a `Payment` row entirely — so a comped booking currently leaves **no
   financial record**.

## Decisions (from brainstorming)

- **Comp record shape:** record the **full service price** as the transaction
  value, with **$0 collected**, flagged as comped. Lets us report "value given
  away."
- **Comp trigger:** decided **per-appointment** (a "waive payment" choice at
  creation time, with a reason). No persistent client flag.
- **Manual scheduling:** **standalone at any date/time**, optional technician,
  **admin override** on capacity/availability (not tied to a block).
- **Client details:** pick an **existing client OR create a new one inline**
  (name / phone / email). Handles walk-ups and phone bookings.
- **Blocks UX:** a **week calendar**; click a slot to create, click a block to
  delete.
- **Delete rule:** **empty blocks delete instantly; blocks with appointments
  are protected** — must move/cancel their appointments first.
- **Notifications:** **toggle per booking**, defaulting to **on** (send the
  normal confirmation + reminders).
- **Defaults locked at approval:** manual bookings still require picking or
  quick-adding an **address + vehicle** (schema requires them and the tech's
  route needs the location); manual appointments go **straight to
  `:confirmed`**; v1 calendar is **click-to-create with a default duration**,
  drag-to-extend deferred.

## Architecture (Approach A)

Two focused admin surfaces backed by one new orchestrator, plus a small schema
addition. Reuses existing resources, actions, and the existing block
create/cancel logic. Each piece is independently testable and shippable.

### 1. Data model — `Payment` comp tracking

One migration adds three fields to `payments`:

| Field | Type | Notes |
|-------|------|-------|
| `collected_cents` | integer | What was actually taken in. Backfill/default = `amount_cents` for existing/normal rows. |
| `comped` | boolean | Default `false`. |
| `comp_reason` | string, nullable | Required (validated) when `comped == true`. |

`amount_cents` remains the **full service value**. A comp is:

```
amount_cents: <full price>, collected_cents: 0, comped: true,
comp_reason: "<reason>", status: :succeeded, paid_at: now
```

Reporting: "value given away" = `sum(amount_cents - collected_cents) where comped`.

The cash-flow ledger records **`collected_cents`** (so a comp deposits $0 — no
phantom cash). New Payment action(s) as needed:

- `create :record_manual` — accepts `amount_cents`, `collected_cents`, `comped`,
  `comp_reason`, `customer_id`, `appointment_id`; sets `status: :succeeded`,
  `paid_at: now`. Validates `comp_reason` present when `comped`. (May be
  implemented as a create + `:complete`, but a single action keeps the comp
  invariants in one place.)

### 2. `Booking.admin_create_booking/1` — new orchestrator

Sibling to `create_booking/1`, transactional. Input (from the admin form):
client (existing id OR new-client fields), vehicle (existing id OR quick-add),
address (existing id OR quick-add), `service_type_id`, `scheduled_at`,
`price_cents`, optional `technician_id`, `waive_payment?` + `comp_reason`,
`collected_cents` (when not waived), `notify_client?`.

Steps:

1. **Resolve client** — if an existing id is given, load it; otherwise create a
   `:customer` from name/phone/email (dedupe on email/phone if one matches).
2. **Ensure vehicle + address** — use the selected existing records, or
   inline-create them for that client.
3. **Create appointment** via a new `:admin_book` action:
   - `appointment_block_id: nil` (standalone).
   - admin-set `scheduled_at` — **no future-date validation, no capacity check**
     (admin override).
   - optional `technician_id`.
   - `status` set straight to **`:confirmed`**.
   - `price_cents` = full service price; `duration_minutes` from service type.
4. **Always create a `Payment` row** via `record_manual`:
   - Waived → `amount_cents: full`, `collected_cents: 0`, `comped: true`,
     `comp_reason`.
   - Not waived → `collected_cents:` the amount entered, `comped: false`.
5. **Cash flow** — record `collected_cents` in the ledger.
6. **Notifications** — enqueue the same confirmation + reminders as a normal
   booking **only if `notify_client?`** (default true).

### 3. Blocks calendar — `/admin/blocks` LiveView

Upgrade the existing LiveView into a **week calendar**:

- Loads existing blocks for the visible week; each block shows
  booked-count / capacity and tech.
- **Click an empty slot** → quick "add block" form prefilled with that
  day/time. Fields: end time (default duration applied), technician, capacity,
  service type. Reuses existing block-create logic. (Drag-to-extend duration is
  a deferred nice-to-have.)
- **Click an existing block** → detail popover with a delete control:
  - **Empty block** (appointment_count == 0) → hard `:destroy`, instant.
  - **Booked block** → delete disabled, message: "Move or cancel its
    appointments first."
- Week navigation (prev/next/today).

Add a guarded `:destroy` action (or a destroy path that refuses when
`appointment_count > 0`) to `AppointmentBlock`.

### 4. Manual-appointment UI

A **"New appointment" modal** launched from the Dispatch LiveView and from the
calendar. Sections:

1. **Client** — search existing (email/phone/name) or "add new" (name, phone,
   email).
2. **Vehicle + address** — pick the client's existing default, or quick-add.
3. **Service + schedule** — service type, date/time, optional technician.
4. **Payment** — "waive payment" checkbox (reveals required reason) OR a
   collected-amount field defaulting to the service price.
5. **Notify client** toggle (default on).

Submits to `Booking.admin_create_booking/1`; on success closes and refreshes the
dispatch/calendar view.

## Components & boundaries

| Unit | Responsibility | Depends on |
|------|----------------|------------|
| `Payment` (+ migration, `record_manual`) | Persist the money record incl. comp fields | Ash / Postgres |
| `Appointment.:admin_book` | Create a confirmed standalone appointment, admin override | Appointment resource |
| `AppointmentBlock.:destroy` (guarded) | Delete an empty block, refuse if booked | AppointmentBlock, appointment_count aggregate |
| `Booking.admin_create_booking/1` | Orchestrate client/vehicle/address → appointment → payment → cashflow → notifications | the above + Accounts, Fleet, CashFlow, notification workers |
| Blocks calendar LiveView | Visual week grid; create/delete blocks | block create logic, `:destroy` |
| New-appointment modal | Collect input, call orchestrator | `admin_create_booking/1` |

## Error handling

- Orchestrator is transactional — any failure rolls back appointment + payment
  together (no half-created comp).
- `comp_reason` required when waiving — validated at the Payment action and the
  form.
- Deleting a booked block is refused at the action layer, not just the UI.
- Client dedupe: if a new-client email/phone matches an existing customer, use
  the existing record rather than creating a duplicate.

## Testing (TDD)

- **Orchestrator:** comped booking records full `amount_cents` + `collected_cents: 0`
  + `comped: true`; non-waived records entered `collected_cents`; new-vs-existing
  client resolution; notify on vs off (assert workers enqueued or not);
  transaction row always created; standalone appointment is `:confirmed` with
  `appointment_block_id: nil`.
- **Payment:** `record_manual` validations (comp_reason required when comped);
  cash flow records `collected_cents`.
- **`:admin_book`:** bypasses future-date/capacity checks; sets `:confirmed`.
- **Block `:destroy`:** empty block destroys; booked block refuses.
- **Calendar LiveView:** renders week blocks; click-create adds a block;
  delete-empty removes; delete-booked is disabled.

## Out of scope (v1)

- Drag-to-set-duration on the calendar (click-to-create with default duration
  only).
- Persistent "VIP/comped" client flag (per-appointment decision only).
- Recurring block templates.
- Editing an appointment's payment after creation (refunds/adjustments).

## Notes for implementation

- Three files are uncommitted by project convention (`config/dev.exs`,
  `AGENTS.md`, `docs/customer-flows.html`) — stash around branch operations; do
  not commit them.
- Dev server runs on **port 4010**.
- `Dispatch.assign_technician/2` uses raw Ecto (bypasses Ash) — reuse it for
  optional tech assignment rather than adding a new path.
