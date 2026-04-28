# Plan 3c: `/book/success` Page Redesign — Design

**Date:** 2026-04-28
**Status:** Approved, ready for implementation plan
**Predecessor:** Plan 3b-3 (booking `:photos` + `:review` rewrites + mobile sticky CTA)
**Successor:** Plan 4 (cash flow page redesign)

---

## Goal

Replace the bare-bones post-payment confirmation page (`BookingSuccessLive`) with a calm, brand-aligned success page that doubles as an operational utility (calendar / directions) and a soft conversion moment (subscription upsell + referral CTA), while fixing a real param-mismatch bug between in-app navigation and the existing LiveView mount.

## Non-Goals

- Wallaby end-to-end coverage — reserved for Plan 5.
- Live review-collection UI — only the deferred "we'll text you" note ships in this plan.
- Static map embeds — no Maps API key plumbed; deep links only.
- Aggressive subscription-tier-comparison block — single generic banner, not a price grid.
- Changes to the Stripe Checkout flow itself (success_url stays as-is).

---

## Bug Fixed By This Plan

`lib/mobile_car_wash_web/live/booking_live.ex:649` navigates the user to `/book/success?id=<appointment_uuid>` after the in-app `:confirmed` step (free / non-Stripe path). The current `BookingSuccessLive.mount/3` only matches `%{"session_id" => session_id}` — so the in-app link falls into the `_params` clause and renders "Missing session information." This plan supports both arrival paths in `mount/3`.

---

## Routing & Data Flow

### Route (unchanged)

```elixir
# lib/mobile_car_wash_web/router.ex
live "/book/success", BookingSuccessLive
```

### Mount handles both arrival paths

```elixir
# Stripe Checkout return
def mount(%{"session_id" => session_id}, _session, socket) do
  # 1. Look up Payment by checkout session
  # 2. Load Appointment + ServiceType + Address from Payment.appointment_id
  # 3. Load Customer + active Subscription (for upsell gate)
  # 4. Assign all + render
end

# In-app navigation from :confirmed step
def mount(%{"id" => appointment_id}, _session, socket) do
  # 1. Load Appointment by id
  # 2. Load related ServiceType, Address, Customer, Subscription
  # 3. payment is nil for non-Stripe (free) bookings — handle gracefully
end

# Neither param present, OR id/session_id doesn't resolve
def mount(_params, _session, socket) do
  # Render error state
end
```

Both happy-path branches assign the same shape to the socket so the render function does not need to distinguish:

```elixir
%{
  page_title: "Booking Confirmed",
  appointment: appointment,        # Scheduling.Appointment
  service: service_type,           # Scheduling.ServiceType
  address: address,                # may be embedded on appointment, or loaded
  customer: customer,              # Accounts.Customer (may be nil for guest checkout)
  payment: payment,                # Billing.Payment | nil
  active_subscription: sub_or_nil  # Billing.Subscription | nil
}
```

### New controller for `.ics` download

```elixir
# lib/mobile_car_wash_web/controllers/booking_calendar_controller.ex
defmodule MobileCarWashWeb.BookingCalendarController do
  use MobileCarWashWeb, :controller
  # GET /book/:id/calendar.ics
  def show(conn, %{"id" => appointment_id}) do
    # 1. Load Appointment + ServiceType + Address
    # 2. Generate VCALENDAR/VEVENT body
    # 3. Send with Content-Type: text/calendar; charset=utf-8
    #    and Content-Disposition: attachment; filename="booking-<id>.ics"
  end
end
```

Route:
```elixir
# Inside the same scope as the existing /book routes
get "/book/:id/calendar.ics", BookingCalendarController, :show
```

### Subscription detection helper

If `MobileCarWash.Billing` does not already expose a single-call helper to load a customer's active subscription, the plan adds:

```elixir
# lib/mobile_car_wash/billing/billing.ex
def active_subscription_for(customer_id) when is_binary(customer_id) do
  # Ash.read with filter on customer_id and status in [:active, :trialing]
  # Return single subscription or nil
end
```

If a one-liner already exists, use it; do not duplicate.

### Layout

Marketing layout (`MobileCarWashWeb.Layouts.app/1` or whichever is currently used by other public-facing LiveViews like `BookingLive`). Post-Stripe customers may not be logged in; the layout must render correctly without an authenticated session.

---

## Page Layout (Top to Bottom)

Single column on mobile. Multi-column subsections start at `sm:` breakpoint.

### 1. Confirmation strip

Small inline cluster, top of page:
- Cyan check icon (Heroicon `check-circle` solid, `text-cyan-500`, ~20 px)
- Text: "Booking confirmed" — `text-xs uppercase tracking-wide font-semibold text-base-content/70`

### 2. Appointment summary card

Primary visual focal point. White card with cyan top border accent (`border-t-4 border-cyan-500`), interior padding `p-6 sm:p-8`, rounded `2xl`, soft shadow.

- **2xl heading** leading with the commitment date/time, formatted from `appointment.scheduled_at`:
  - Format: `"Saturday, May 3 at 10:00 AM"`
  - Use `Calendar.strftime(scheduled_at, "%A, %B %-d at %-I:%M %p")` (the existing app's pattern).
- **Service + price chips** — small inline row:
  - Service chip: navy text on `bg-base-200` pill — service name only.
  - Price chip: monospace dollar amount (Inter for the dollar sign, JetBrains Mono for the digits — matches existing financial-figure convention) on `bg-base-200`.
  - Price source: `payment.amount_cents` if `payment` is present, else fall back to `service.price_cents` (must exist on `ServiceType`).
- **Address line** — small map-pin icon + the full street address on one line, city/state/zip on the next.
- **Technician line, conditional**:
  - If `appointment.technician_id` is set and the technician record loads: "Your technician: **<name>**" in a muted line.
  - If unset: muted line "We'll let you know once a technician is assigned." — no broken state, no `nil` access.

### 3. Next steps grid

Three cells. 1-column on mobile (`grid-cols-1`), 3-column from `sm:` up (`sm:grid-cols-3`). Each cell is a small card with an icon, label, and primary action.

#### 3a. Add to calendar
- Heroicon `calendar-days` outline at top.
- Label: "Add to calendar"
- Primary button: "Download .ics" — `<a href={~p"/book/#{appointment.id}/calendar.ics"}>` — opens / downloads.
- Two text links below the primary button:
  - "Google Calendar" → `https://calendar.google.com/calendar/render?action=TEMPLATE&text=<service>&dates=<start>/<end>&details=<details>&location=<address>` (URL-encoded). Open in new tab (`target="_blank" rel="noopener"`).
  - "Outlook Web" → `https://outlook.live.com/calendar/0/deeplink/compose?path=/calendar/action/compose&rru=addevent&subject=<service>&body=<details>&location=<address>&startdt=<iso>&enddt=<iso>` (URL-encoded). Open in new tab.
- Both deep-link URLs use a 90-minute default duration if no explicit `duration_minutes` exists on the appointment.

#### 3b. Get directions
- Heroicon `map-pin` outline at top.
- Label: "Get directions"
- Single button: "Open in Google Maps" → `https://www.google.com/maps/dir/?api=1&destination=<URI.encode_www_form(full_address)>` — opens in new tab.

#### 3c. Confirmation email
- Heroicon `envelope` outline at top.
- Label: "Confirmation email"
- Read-only status line: "Sent to {masked_email}" where masked_email is the customer's email lightly masked if a helper exists, otherwise the raw email. (E.g., `we***@gmail.com`.) If no `customer` (guest Stripe checkout edge case), show "Check your email for confirmation." instead.

### 4. Subscription upsell card

Full-width tinted band:
- Background `bg-cyan-500/5`, ring `ring-1 ring-cyan-500/20`, rounded `xl`, padding `p-5 sm:p-6`.
- Headline: "Save 15% on every wash."
- One sentence: "A monthly plan covers two washes a month and locks in your spot."
- CTA button: "See plans →" → `~p"/pricing"`.
- **Hidden** when `@active_subscription` is non-nil. No empty wrapper, no layout shift.

### 5. Referral card

Full-width tinted band:
- Background `bg-base-200`, rounded `xl`, padding `p-5 sm:p-6`.
- Headline: "Give a friend $10 off."
- Subline: "Share your code — they save, you save next time."
- Referral code rendered in a monospace pill: `<code class="font-mono px-3 py-1 bg-base-100 rounded">{customer.referral_code}</code>`
- "Copy code" button right of the pill — uses an inline `phx-hook="ClipboardCopy"` hook. If a clipboard JS hook already exists in `assets/js/app.js`, use that; otherwise add a small inline hook (a few lines).
- **Hidden silently** when `customer == nil` OR `customer.referral_code` is `nil`. No broken UI.

### 6. Footer area

Two muted lines, then the back link:
- Line 1: "After your appointment, we'll text you a link to leave a review."
- Line 2: "Booking ID: `<uuid>`" — uuid in `font-mono text-xs`.
- Tertiary link: "← Back to home" → `~p"/"`.

### 7. Error state

When neither `session_id` nor `id` resolves a real appointment:
- Same outer container.
- Heading (2xl): "We couldn't find that booking."
- Body: "If you completed payment, contact us and we'll sort it out — we have your details."
- Two contact rows (icons + text):
  - `<a href="mailto:hello@drivewaydetailcosa.com">hello@drivewaydetailcosa.com</a>` — pull from existing site config / business contact module if one exists; otherwise use this hardcoded fallback.
  - `<a href="tel:+12105550100">(210) 555-0100</a>` — same: pulled from existing config when present, hardcoded fallback otherwise.
- Tertiary link: "← Back to home".

The plan instructs the implementer to grep for existing business-contact config (`lib/mobile_car_wash/marketing/`, `config/runtime.exs`) before falling back to hardcoded values. If a config helper exists (e.g., `Marketing.support_email/0`), use it.

---

## Componentization

Render inline first. If the LiveView's `render/1` body grows past ~150 LOC, pull these named function components into a new module:

```
lib/mobile_car_wash_web/components/booking_success_components.ex
```

Candidates:
- `appointment_summary_card/1`
- `next_steps_grid/1` (or three smaller cells: `calendar_cell/1`, `directions_cell/1`, `email_cell/1`)
- `subscription_upsell_card/1`
- `referral_card/1`

Implementer makes the call mid-implementation. If extracted, components live in the new module and are imported by the LiveView's quoted-import block.

---

## Calendar Generation Details

### `.ics` body shape (controller-generated)

```
BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Driveway Detail Co//Booking//EN
CALSCALE:GREGORIAN
METHOD:PUBLISH
BEGIN:VEVENT
UID:<appointment.id>@drivewaydetailcosa.com
DTSTAMP:<now in YYYYMMDDTHHMMSSZ format, UTC>
DTSTART:<scheduled_at in YYYYMMDDTHHMMSSZ, UTC>
DTEND:<scheduled_at + 90min, YYYYMMDDTHHMMSSZ, UTC>
SUMMARY:<service.name>
DESCRIPTION:Booking ID: <appointment.id>\nService: <service.name>\nWe'll text you 30 minutes before arrival.
LOCATION:<full address, comma-separated>
STATUS:CONFIRMED
END:VEVENT
END:VCALENDAR
```

Line endings must be CRLF (`\r\n`) per RFC 5545. Implement as a small private function in the controller, not a separate library — fewer than 30 LOC.

### Google Calendar URL params

```
text=<URI.encode_www_form(service.name)>
dates=<start>/<end>     # both in YYYYMMDDTHHMMSSZ form
details=<URI.encode_www_form(description text)>
location=<URI.encode_www_form(full address)>
```

### Outlook Web URL params

```
subject=<URI.encode_www_form(service.name)>
body=<URI.encode_www_form(description text)>
location=<URI.encode_www_form(full address)>
startdt=<scheduled_at ISO 8601 with Z>
enddt=<scheduled_at + 90min, ISO 8601 with Z>
```

A small private helper module `BookingSuccessLive.CalendarLinks` (or similar) builds both URLs from a single appointment input. Lives at the bottom of `booking_success_live.ex` initially; promoted to its own file only if it grows.

---

## Tests

### `test/mobile_car_wash_web/live/booking_success_live_test.exs` (new)

Use ExUnit + LiveViewTest. Build setup with `Ash.Seed.seed!/1` (or whatever fixture pattern the suite already uses — check `test/support/fixtures.ex` first).

Cases:

1. **Mount with valid `session_id`** renders the appointment summary heading containing the formatted date/time and the service name.
2. **Mount with valid `id`** (covers the bug fix) renders the same content; LiveView mounts cleanly without `session_id` present.
3. **Mount with neither param** renders the error state: heading "We couldn't find that booking." plus the contact lines.
4. **Mount with unknown `session_id`** renders the error state.
5. **Mount with unknown `id`** renders the error state.
6. **Subscription upsell card renders** when `customer` has no active subscription.
7. **Subscription upsell card hidden** when `customer` has an active subscription (seed a `:active` `Billing.Subscription` for the test customer).
8. **Referral card renders** when `customer.referral_code` is set; hidden when `nil`.
9. **"Add to calendar" buttons** render with the expected `href` patterns:
   - `.ics` href contains `/book/<id>/calendar.ics`
   - Google href contains `calendar.google.com/calendar/render` and the URL-encoded service name
   - Outlook href contains `outlook.live.com/calendar/0/deeplink/compose`
10. **"Get directions" link** href contains the URL-encoded full address and `maps/dir/`.

Pattern test, not exact-string match — use `=~` against the rendered HTML.

### `test/mobile_car_wash_web/controllers/booking_calendar_controller_test.exs` (new)

Cases:

1. `GET /book/<id>/calendar.ics` returns 200 with `content-type: text/calendar; charset=utf-8`.
2. Response body contains `BEGIN:VCALENDAR`, `END:VCALENDAR`, the service name as `SUMMARY:`, and the correctly UTC-formatted `DTSTART:` line for the seeded appointment.
3. Response body contains the full address as `LOCATION:`.
4. `Content-Disposition` header includes `attachment; filename="booking-<id>.ics"`.
5. `GET /book/<unknown_uuid>/calendar.ics` returns 404 (or whatever the app's standard not-found behavior is — match `BookingLive`'s pattern).

---

## Acceptance Criteria

A reviewer should be able to verify:

1. Visiting `/book/success?session_id=<valid>` after Stripe Checkout renders the redesigned page with appointment date/time, address, calendar buttons, directions, subscription upsell, referral card, and footer note.
2. Visiting `/book/success?id=<appointment_uuid>` from the in-app `:confirmed` step renders the same page (bug fix verified).
3. Subscription banner is hidden for an active subscriber.
4. Referral card is hidden when the customer has no referral code.
5. Clicking "Download .ics" downloads a valid iCalendar file that opens cleanly in Apple Calendar.
6. Google Calendar and Outlook Web links open the respective web composer prefilled with the appointment.
7. "Get directions" opens Google Maps with the correct destination.
8. Visiting `/book/success` with no params (or invalid params) renders the "We couldn't find that booking" error state with contact info, not a crash.
9. Full test suite green: `mix test` passes with the new tests.
10. No regressions in existing booking flow tests.

---

## Files Touched (Estimate)

**Rewritten:**
- `lib/mobile_car_wash_web/live/booking_success_live.ex`

**New:**
- `lib/mobile_car_wash_web/controllers/booking_calendar_controller.ex`
- `lib/mobile_car_wash_web/components/booking_success_components.ex` (only if extracted)
- `test/mobile_car_wash_web/live/booking_success_live_test.exs`
- `test/mobile_car_wash_web/controllers/booking_calendar_controller_test.exs`

**Modified:**
- `lib/mobile_car_wash_web/router.ex` — add `.ics` GET route
- `lib/mobile_car_wash/billing/billing.ex` — add `active_subscription_for/1` helper *only if one doesn't already exist*

**Untouched but relevant:**
- `lib/mobile_car_wash_web/live/booking_live.ex:649` — the existing link to `/book/success?id=...` stays; the bug fix is delivered by `BookingSuccessLive.mount/3` accepting the `id` param.

---

## Out of Scope (Explicitly)

- Wallaby end-to-end coverage (Plan 5).
- Any change to Stripe Checkout `success_url` or webhook handlers.
- Live review collection UI — only the deferred "we'll text you" note.
- Static map images / Maps API integration.
- Subscription tier comparison grid — only a single generic banner.
- SMS reminder system changes.
- Mobile push notifications.

---

## Approval & Implementation Path

1. User reviews this spec → approves.
2. `superpowers:writing-plans` creates the bite-sized task plan at `docs/superpowers/plans/2026-04-28-plan3c-book-success-redesign.md`.
3. `superpowers:using-git-worktrees` sets up `.claude/worktrees/plan3c-book-success`.
4. `superpowers:subagent-driven-development` executes the plan task-by-task.
5. `superpowers:finishing-a-development-branch` merges back to main when green.
