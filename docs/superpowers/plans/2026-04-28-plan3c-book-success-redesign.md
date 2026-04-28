# Plan 3c: `/book/success` Page Redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild `BookingSuccessLive` as a calm, brand-aligned confirmation page with operational utility (calendar/directions) and soft conversion (subscription upsell + referral CTA), while fixing the in-app `id`-vs-`session_id` mount bug.

**Architecture:** Full rewrite of `lib/mobile_car_wash_web/live/booking_success_live.ex`. Mount accepts both `session_id` (Stripe Checkout return) and `id` (in-app `:confirmed` step nav) params. New `BookingCalendarController` serves an `.ics` file at `/book/:id/calendar.ics`. Subscription banner gated on existing `Subscription.read :active_for_customer` Ash action. Referral card gated on `customer.referral_code` presence. Deep links to Google Calendar / Outlook Web / Google Maps directions are rendered inline via URL helpers — no third-party libs.

**Tech Stack:** Phoenix LiveView, HEEx, Tailwind v4 + daisyUI, Heroicons via vendor plugin, Ash Framework (existing `Billing.Subscription`, `Scheduling.Appointment`, `Scheduling.ServiceType`, `Accounts.Customer`, `Fleet.Address`).

**Spec:** `docs/superpowers/specs/2026-04-28-plan3c-book-success-redesign-design.md`

---

## File Structure

**Rewritten:**
- `lib/mobile_car_wash_web/live/booking_success_live.ex` — full redesign

**New:**
- `lib/mobile_car_wash_web/controllers/booking_calendar_controller.ex` — serves `.ics`
- `test/mobile_car_wash_web/live/booking_success_live_test.exs`
- `test/mobile_car_wash_web/controllers/booking_calendar_controller_test.exs`

**Modified:**
- `lib/mobile_car_wash_web/router.ex` — adds `GET /book/:id/calendar.ics`
- `assets/js/app.js` — adds tiny `ClipboardCopy` JS hook (5–10 lines)

**Untouched but related:**
- `lib/mobile_car_wash_web/live/booking_live.ex:649` — existing link `~p"/book/success?id=#{@appointment.id}"` stays; the bug fix is delivered by the new mount clause accepting `id`.

---

## Conventions Used Throughout This Plan

**Existing test data pattern** (from `test/mobile_car_wash_web/live/appointment_status_live_test.exs`):
- Each test builds fixtures with `Ash.Changeset.for_create/3` + `Ash.create/1`
- Customer with `:register_with_password` action
- Sign-in via `post "/auth/customer/password/sign_in"` + `recycle()`
- `Ash.Changeset.force_change_attribute/3` for relationship FK assignment when needed

**Existing Ash query for active subscription** (already in `lib/mobile_car_wash/billing/subscription.ex`):
```elixir
read :active_for_customer do
  argument(:customer_id, :uuid, allow_nil?: false)
  filter(expr(customer_id == ^arg(:customer_id) and status in [:active, :paused, :past_due]))
end
```
Use directly — no new helper needed.

**Mount assigns shape (consistent across all happy-path branches):**
```elixir
%{
  page_title: "Booking Confirmed",
  appointment: appointment,        # %Scheduling.Appointment{}
  service: service_type,           # %Scheduling.ServiceType{}
  address: address,                # %Fleet.Address{} (or nil if missing)
  customer: customer,              # %Accounts.Customer{} | nil
  payment: payment,                # %Billing.Payment{} | nil
  active_subscription: sub_or_nil  # %Billing.Subscription{} | nil
}
```

**Date/time format:** `Calendar.strftime(scheduled_at, "%A, %B %-d at %-I:%M %p")` → `"Saturday, May 3 at 10:00 AM"`.

**Fixture-attribute caveat:** Several test fixtures below assume the create-action attribute names of resources like `Payment`, `Subscription`, `SubscriptionPlan`, and `Customer`. Before running fixture code, the implementer should `grep -n "actions\|action :create\|attribute :" lib/mobile_car_wash/billing/payment.ex` (and the relevant resource file) to verify the names match. If a name differs, **adjust the fixture**, not the production code.

---

## Task 0: Worktree setup

**Files:** none yet (workspace setup)

- [ ] **Step 1: Create worktree**

```bash
cd /Volumes/mac_external/Development/Business/MobileCarWash
git worktree add .claude/worktrees/plan3c-book-success -b claude/plan3c-book-success
cd .claude/worktrees/plan3c-book-success
```

- [ ] **Step 2: Install deps + assets baseline**

Run from worktree root:
```bash
mix deps.get
mix assets.build
```

- [ ] **Step 3: Verify clean test baseline**

Run: `mix test`
Expected: 1060 tests, 0 failures (or whatever current count is — must be 0 failures).

If failures: STOP, report to controller, do not proceed.

---

## Task 1: Mount accepts `id` param (bug fix, TDD)

**Files:**
- Test: `test/mobile_car_wash_web/live/booking_success_live_test.exs` (CREATE)
- Modify: `lib/mobile_car_wash_web/live/booking_success_live.ex`

**Context:** Currently `mount/3` only matches `%{"session_id" => session_id}`. The link in `booking_live.ex:649` (`~p"/book/success?id=#{@appointment.id}"`) lands on the `_params` clause and shows "Missing session information." This task adds an `id`-arrival mount clause. We rewrite render minimally to render the appointment heading; later tasks expand the markup.

- [ ] **Step 1: Write the failing test (file creation)**

Create `test/mobile_car_wash_web/live/booking_success_live_test.exs`:

```elixir
defmodule MobileCarWashWeb.BookingSuccessLiveTest do
  @moduledoc """
  Tests for the redesigned post-booking success page. Covers both arrival
  paths (Stripe `?session_id=...` and in-app `?id=...`), conditional UI
  (subscription upsell, referral card, technician line), calendar/maps
  deep links, and error states.
  """
  use MobileCarWashWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Billing.Payment
  alias MobileCarWash.Fleet.{Address, Vehicle}
  alias MobileCarWash.Scheduling.{Appointment, ServiceType}

  defp register_customer(opts \\ []) do
    referral = Keyword.get(opts, :referral_code, nil)

    {:ok, customer} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "success-live-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Success Live",
        phone: "+15125559000"
      })
      |> Ash.create()

    if referral do
      customer
      |> Ash.Changeset.for_update(:update, %{referral_code: referral})
      |> Ash.update!()
    else
      customer
    end
  end

  defp create_appointment(customer) do
    {:ok, service} =
      ServiceType
      |> Ash.Changeset.for_create(:create, %{
        name: "Premium Detail",
        slug: "premium-detail-#{System.unique_integer([:positive])}",
        base_price_cents: 8_900,
        duration_minutes: 90
      })
      |> Ash.create()

    {:ok, vehicle} =
      Vehicle
      |> Ash.Changeset.for_create(:create, %{make: "Tesla", model: "Model 3"})
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create()

    {:ok, address} =
      Address
      |> Ash.Changeset.for_create(:create, %{
        street: "1717 Success Lane",
        city: "San Antonio",
        state: "TX",
        zip: "78261"
      })
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create()

    {:ok, appt} =
      Appointment
      |> Ash.Changeset.for_create(:book, %{
        customer_id: customer.id,
        vehicle_id: vehicle.id,
        address_id: address.id,
        service_type_id: service.id,
        scheduled_at: DateTime.add(DateTime.utc_now(), 2 * 86_400, :second),
        price_cents: 8_900,
        duration_minutes: 90
      })
      |> Ash.create()

    {appt, service, address}
  end

  describe "mount with `id` param (in-app arrival)" do
    test "renders booking confirmed for valid id", %{conn: conn} do
      customer = register_customer()
      {appt, service, _address} = create_appointment(customer)

      {:ok, _view, html} = live(conn, ~p"/book/success?id=#{appt.id}")

      assert html =~ "Booking confirmed"
      assert html =~ service.name
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/mobile_car_wash_web/live/booking_success_live_test.exs`

Expected: FAIL — current mount has no `id` clause; test should fall through to error state and assertion `html =~ "Booking confirmed"` should fail.

- [ ] **Step 3: Replace `BookingSuccessLive` with the minimal redesigned shell**

Rewrite `lib/mobile_car_wash_web/live/booking_success_live.ex` to:

```elixir
defmodule MobileCarWashWeb.BookingSuccessLive do
  @moduledoc """
  Shown after a customer books — supports both Stripe Checkout return
  (?session_id=...) and in-app navigation from the :confirmed step
  (?id=<appointment_uuid>).
  """
  use MobileCarWashWeb, :live_view

  alias MobileCarWash.Billing.{Payment, Subscription}
  alias MobileCarWash.Scheduling.{Appointment, ServiceType}
  alias MobileCarWash.Fleet.Address
  alias MobileCarWash.Accounts.Customer

  @impl true
  def mount(%{"session_id" => session_id}, _session, socket) do
    case lookup_by_session(session_id) do
      {:ok, data} -> {:ok, assign_loaded(socket, data)}
      :error -> {:ok, assign_error(socket)}
    end
  end

  def mount(%{"id" => appointment_id}, _session, socket) do
    case lookup_by_appointment_id(appointment_id) do
      {:ok, data} -> {:ok, assign_loaded(socket, data)}
      :error -> {:ok, assign_error(socket)}
    end
  end

  def mount(_params, _session, socket) do
    {:ok, assign_error(socket)}
  end

  # === Private helpers ===

  defp lookup_by_session(session_id) do
    payments =
      Ash.read!(Payment,
        action: :by_checkout_session,
        arguments: %{session_id: session_id}
      )

    case payments do
      [payment] ->
        appointment = Ash.get!(Appointment, payment.appointment_id)
        build_loaded(appointment, payment)

      _ ->
        :error
    end
  rescue
    _ -> :error
  end

  defp lookup_by_appointment_id(appointment_id) do
    appointment = Ash.get!(Appointment, appointment_id)
    build_loaded(appointment, nil)
  rescue
    _ -> :error
  end

  defp build_loaded(appointment, payment) do
    service = Ash.get!(ServiceType, appointment.service_type_id)

    address =
      case appointment.address_id do
        nil -> nil
        addr_id -> Ash.get!(Address, addr_id)
      end

    customer =
      case appointment.customer_id do
        nil -> nil
        cust_id -> Ash.get!(Customer, cust_id)
      end

    active_subscription =
      case customer do
        nil ->
          nil

        c ->
          case Ash.read!(Subscription,
                 action: :active_for_customer,
                 arguments: %{customer_id: c.id}
               ) do
            [sub | _] -> sub
            [] -> nil
          end
      end

    {:ok,
     %{
       appointment: appointment,
       service: service,
       address: address,
       customer: customer,
       payment: payment,
       active_subscription: active_subscription
     }}
  end

  defp assign_loaded(socket, %{
         appointment: appt,
         service: service,
         address: address,
         customer: customer,
         payment: payment,
         active_subscription: sub
       }) do
    assign(socket,
      page_title: "Booking Confirmed",
      appointment: appt,
      service: service,
      address: address,
      customer: customer,
      payment: payment,
      active_subscription: sub,
      not_found: false
    )
  end

  defp assign_error(socket) do
    assign(socket,
      page_title: "Booking",
      appointment: nil,
      service: nil,
      address: nil,
      customer: nil,
      payment: nil,
      active_subscription: nil,
      not_found: true
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-3xl mx-auto px-4 py-10 sm:py-14">
      <div :if={!@not_found}>
        <%!-- Confirmation strip --%>
        <div class="flex items-center gap-2 mb-6">
          <.icon name="hero-check-circle-solid" class="h-5 w-5 text-cyan-500" />
          <span class="text-xs font-semibold uppercase tracking-wide text-base-content/70">
            Booking confirmed
          </span>
        </div>

        <%!-- Appointment summary card (placeholder content; expanded in Task 2) --%>
        <div class="rounded-2xl border-t-4 border-cyan-500 bg-base-100 shadow-sm p-6 sm:p-8">
          <h1 class="text-2xl sm:text-3xl font-bold text-base-content">
            {Calendar.strftime(@appointment.scheduled_at, "%A, %B %-d at %-I:%M %p")}
          </h1>
          <p class="mt-2 text-base-content/70">{@service.name}</p>
        </div>
      </div>

      <div :if={@not_found}>
        <h1 class="text-2xl font-bold mb-4">We couldn't find that booking.</h1>
        <p class="text-base-content/70 mb-6">
          If you completed payment, contact us and we'll sort it out — we have your details.
        </p>
        <.link navigate={~p"/"} class="btn btn-ghost">← Back to home</.link>
      </div>
    </div>
    """
  end
end
```

- [ ] **Step 4: Run the failing test — now expect PASS**

Run: `mix test test/mobile_car_wash_web/live/booking_success_live_test.exs`

Expected: PASS (1 test).

- [ ] **Step 5: Commit**

```bash
git add lib/mobile_car_wash_web/live/booking_success_live.ex test/mobile_car_wash_web/live/booking_success_live_test.exs
git commit -m "booking_success: support ?id= arrival path (bug fix) + minimal redesigned shell"
```

---

## Task 2: Appointment summary card (full content + tests)

**Files:**
- Test: `test/mobile_car_wash_web/live/booking_success_live_test.exs` (modify — add cases)
- Modify: `lib/mobile_car_wash_web/live/booking_success_live.ex` (expand the summary card)

**Context:** The card currently has heading + service name. Spec wants service+price chips, address line (street + city/state/zip), and a conditional technician line.

- [ ] **Step 1: Add tests for the expanded card**

Append inside the existing `describe "mount with `id` param (in-app arrival)" do` block in the test file (or open a new `describe`):

```elixir
describe "appointment summary card content" do
  test "renders price chip from payment when present", %{conn: conn} do
    customer = register_customer()
    {appt, _service, _address} = create_appointment(customer)

    # Seed a payment row associated with this appointment
    {:ok, _payment} =
      Payment
      |> Ash.Changeset.for_create(:create, %{
        appointment_id: appt.id,
        amount_cents: 8_900,
        status: :succeeded,
        stripe_checkout_session_id: "cs_test_#{System.unique_integer([:positive])}"
      })
      |> Ash.create()

    {:ok, _view, html} = live(conn, ~p"/book/success?id=#{appt.id}")

    assert html =~ "$89"
  end

  test "renders price chip from service when payment is nil", %{conn: conn} do
    customer = register_customer()
    {appt, _service, _address} = create_appointment(customer)

    {:ok, _view, html} = live(conn, ~p"/book/success?id=#{appt.id}")

    # No payment seeded → fall back to service.base_price_cents (8_900)
    assert html =~ "$89"
  end

  test "renders the service name as a chip", %{conn: conn} do
    customer = register_customer()
    {appt, service, _address} = create_appointment(customer)

    {:ok, _view, html} = live(conn, ~p"/book/success?id=#{appt.id}")

    assert html =~ service.name
  end

  test "renders the full address", %{conn: conn} do
    customer = register_customer()
    {appt, _service, address} = create_appointment(customer)

    {:ok, _view, html} = live(conn, ~p"/book/success?id=#{appt.id}")

    assert html =~ address.street
    assert html =~ address.city
    assert html =~ address.zip
  end

  test "renders the muted technician line when none is assigned", %{conn: conn} do
    customer = register_customer()
    {appt, _service, _address} = create_appointment(customer)

    {:ok, _view, html} = live(conn, ~p"/book/success?id=#{appt.id}")

    assert appt.technician_id == nil
    assert html =~ "We&#39;ll let you know once a technician is assigned."
  end
end
```

> **Note for the implementer:** HEEx HTML-escapes apostrophes — that's why the assertion uses `&#39;`. Do not "fix" this in the assertion.

- [ ] **Step 2: Run test to verify failures**

Run: `mix test test/mobile_car_wash_web/live/booking_success_live_test.exs`

Expected: FAIL on the new cases (price chips, address, technician line) — none rendered yet.

- [ ] **Step 3: Implement the expanded card markup**

Replace the entire summary-card `<div class="rounded-2xl border-t-4 ...">` block in `booking_success_live.ex` with:

```heex
<%!-- Appointment summary card --%>
<div class="rounded-2xl border-t-4 border-cyan-500 bg-base-100 shadow-sm p-6 sm:p-8">
  <h1 class="text-2xl sm:text-3xl font-bold text-base-content">
    {Calendar.strftime(@appointment.scheduled_at, "%A, %B %-d at %-I:%M %p")}
  </h1>

  <%!-- Service + price chips --%>
  <div class="mt-4 flex flex-wrap items-center gap-2">
    <span class="inline-flex items-center px-3 py-1 rounded-full bg-base-200 text-sm font-medium text-base-content">
      {@service.name}
    </span>
    <span class="inline-flex items-center px-3 py-1 rounded-full bg-base-200 text-sm font-mono">
      ${div(price_cents(@payment, @service), 100)}
    </span>
  </div>

  <%!-- Address line --%>
  <div :if={@address} class="mt-5 flex items-start gap-2 text-base-content/80">
    <.icon name="hero-map-pin" class="h-5 w-5 shrink-0 mt-0.5 text-cyan-500" />
    <div class="text-sm leading-relaxed">
      <div>{@address.street}</div>
      <div>{@address.city}, {@address.state} {@address.zip}</div>
    </div>
  </div>

  <%!-- Technician line (conditional) --%>
  <p :if={@appointment.technician_id == nil} class="mt-5 text-sm text-base-content/60">
    We'll let you know once a technician is assigned.
  </p>
</div>
```

Add this private helper at the bottom of the module (above the final `end`):

```elixir
defp price_cents(nil, service), do: service.base_price_cents
defp price_cents(payment, _service), do: payment.amount_cents
```

- [ ] **Step 4: Run tests — expect PASS**

Run: `mix test test/mobile_car_wash_web/live/booking_success_live_test.exs`

Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/mobile_car_wash_web/live/booking_success_live.ex test/mobile_car_wash_web/live/booking_success_live_test.exs
git commit -m "booking_success: expand appointment summary card (chips + address + tech line)"
```

---

## Task 3: Next steps grid — calendar + directions + email

**Files:**
- Test: `test/mobile_car_wash_web/live/booking_success_live_test.exs` (modify)
- Modify: `lib/mobile_car_wash_web/live/booking_success_live.ex`

**Context:** The grid contains three cells. The `.ics` button targets a route we'll add in Task 7. The Google Calendar / Outlook Web / Google Maps URLs are built inline by helper functions and tested by URL-pattern asserts.

- [ ] **Step 1: Add tests for the grid**

Append a new `describe` block to the test file:

```elixir
describe "next steps grid" do
  test "renders Download .ics button targeting /book/:id/calendar.ics", %{conn: conn} do
    customer = register_customer()
    {appt, _service, _address} = create_appointment(customer)

    {:ok, _view, html} = live(conn, ~p"/book/success?id=#{appt.id}")

    assert html =~ "Download .ics"
    assert html =~ "/book/#{appt.id}/calendar.ics"
  end

  test "renders Google Calendar deep link", %{conn: conn} do
    customer = register_customer()
    {appt, service, _address} = create_appointment(customer)

    {:ok, _view, html} = live(conn, ~p"/book/success?id=#{appt.id}")

    assert html =~ "calendar.google.com/calendar/render"
    assert html =~ URI.encode_www_form(service.name)
  end

  test "renders Outlook Web deep link", %{conn: conn} do
    customer = register_customer()
    {appt, _service, _address} = create_appointment(customer)

    {:ok, _view, html} = live(conn, ~p"/book/success?id=#{appt.id}")

    assert html =~ "outlook.live.com/calendar/0/deeplink/compose"
  end

  test "renders Get directions link to Google Maps with encoded address", %{conn: conn} do
    customer = register_customer()
    {appt, _service, address} = create_appointment(customer)

    {:ok, _view, html} = live(conn, ~p"/book/success?id=#{appt.id}")

    assert html =~ "maps/dir/?api=1"
    assert html =~ URI.encode_www_form("#{address.street}, #{address.city}, #{address.state} #{address.zip}")
  end

  test "renders confirmation email status with customer email", %{conn: conn} do
    customer = register_customer()
    {appt, _service, _address} = create_appointment(customer)

    {:ok, _view, html} = live(conn, ~p"/book/success?id=#{appt.id}")

    assert html =~ "Sent to"
    assert html =~ to_string(customer.email) |> String.split("@") |> hd()
  end
end
```

- [ ] **Step 2: Run tests to verify failure**

Run: `mix test test/mobile_car_wash_web/live/booking_success_live_test.exs --only describe:"next steps grid"`

Expected: FAIL — none of the grid markup exists yet.

- [ ] **Step 3: Add the grid markup + URL helpers**

In `booking_success_live.ex`, append the grid block AFTER the appointment summary card, BEFORE the `<div :if={@not_found}>` block:

```heex
<%!-- Next steps grid --%>
<div class="mt-8 grid grid-cols-1 sm:grid-cols-3 gap-4">
  <%!-- Add to calendar --%>
  <div class="rounded-xl bg-base-100 ring-1 ring-base-300 p-5 flex flex-col">
    <.icon name="hero-calendar-days" class="h-6 w-6 text-cyan-500" />
    <h3 class="mt-3 font-semibold text-base-content">Add to calendar</h3>
    <a
      href={~p"/book/#{@appointment.id}/calendar.ics"}
      class="btn btn-primary btn-sm mt-3 w-full"
    >
      Download .ics
    </a>
    <a
      href={google_calendar_url(@appointment, @service, @address)}
      target="_blank"
      rel="noopener"
      class="text-xs text-cyan-600 hover:underline mt-2"
    >
      Google Calendar
    </a>
    <a
      href={outlook_calendar_url(@appointment, @service, @address)}
      target="_blank"
      rel="noopener"
      class="text-xs text-cyan-600 hover:underline mt-1"
    >
      Outlook Web
    </a>
  </div>

  <%!-- Get directions --%>
  <div class="rounded-xl bg-base-100 ring-1 ring-base-300 p-5 flex flex-col">
    <.icon name="hero-map-pin" class="h-6 w-6 text-cyan-500" />
    <h3 class="mt-3 font-semibold text-base-content">Get directions</h3>
    <a
      :if={@address}
      href={directions_url(@address)}
      target="_blank"
      rel="noopener"
      class="btn btn-outline btn-sm mt-3 w-full"
    >
      Open in Google Maps
    </a>
    <p :if={!@address} class="text-sm text-base-content/60 mt-3">
      Address not available.
    </p>
  </div>

  <%!-- Confirmation email --%>
  <div class="rounded-xl bg-base-100 ring-1 ring-base-300 p-5 flex flex-col">
    <.icon name="hero-envelope" class="h-6 w-6 text-cyan-500" />
    <h3 class="mt-3 font-semibold text-base-content">Confirmation email</h3>
    <p :if={@customer} class="mt-3 text-sm text-base-content/70">
      Sent to {mask_email(to_string(@customer.email))}
    </p>
    <p :if={!@customer} class="mt-3 text-sm text-base-content/70">
      Check your email for confirmation.
    </p>
  </div>
</div>
```

Append these private helpers at the bottom of the module:

```elixir
# === URL builders ===

defp google_calendar_url(appointment, service, address) do
  start_at = format_ical_basic(appointment.scheduled_at)
  end_at = format_ical_basic(end_time(appointment))

  query =
    URI.encode_query(%{
      "action" => "TEMPLATE",
      "text" => service.name,
      "dates" => "#{start_at}/#{end_at}",
      "details" => "Booking ID: #{appointment.id}",
      "location" => format_address(address)
    })

  "https://calendar.google.com/calendar/render?#{query}"
end

defp outlook_calendar_url(appointment, service, address) do
  query =
    URI.encode_query(%{
      "path" => "/calendar/action/compose",
      "rru" => "addevent",
      "subject" => service.name,
      "body" => "Booking ID: #{appointment.id}",
      "location" => format_address(address),
      "startdt" => DateTime.to_iso8601(appointment.scheduled_at),
      "enddt" => DateTime.to_iso8601(end_time(appointment))
    })

  "https://outlook.live.com/calendar/0/deeplink/compose?#{query}"
end

defp directions_url(nil), do: "#"

defp directions_url(address) do
  "https://www.google.com/maps/dir/?api=1&destination=" <>
    URI.encode_www_form(format_address(address))
end

defp end_time(appointment) do
  duration = appointment.duration_minutes || 90
  DateTime.add(appointment.scheduled_at, duration * 60, :second)
end

# YYYYMMDDTHHMMSSZ for iCal/Google Calendar
defp format_ical_basic(%DateTime{} = dt) do
  dt
  |> DateTime.shift_zone!("Etc/UTC")
  |> Calendar.strftime("%Y%m%dT%H%M%SZ")
end

defp format_address(nil), do: ""

defp format_address(address) do
  "#{address.street}, #{address.city}, #{address.state} #{address.zip}"
end

# === Email masking ===

defp mask_email(email) when is_binary(email) do
  case String.split(email, "@") do
    [local, domain] when byte_size(local) > 2 ->
      first_two = String.slice(local, 0, 2)
      first_two <> "***@" <> domain

    [local, domain] ->
      local <> "***@" <> domain

    _ ->
      email
  end
end
```

- [ ] **Step 4: Run tests — expect PASS**

Run: `mix test test/mobile_car_wash_web/live/booking_success_live_test.exs`

Expected: PASS on all current tests (10 total so far).

- [ ] **Step 5: Commit**

```bash
git add lib/mobile_car_wash_web/live/booking_success_live.ex test/mobile_car_wash_web/live/booking_success_live_test.exs
git commit -m "booking_success: add next-steps grid (calendar + directions + email)"
```

---

## Task 4: Subscription upsell card

**Files:**
- Test: `test/mobile_car_wash_web/live/booking_success_live_test.exs` (modify)
- Modify: `lib/mobile_car_wash_web/live/booking_success_live.ex`

**Context:** Card shows for non-subscribers, hides for active subscribers. Active-sub detection uses the existing `Subscription.read :active_for_customer` action (already wired in mount via `lookup_by_appointment_id` / `lookup_by_session`).

- [ ] **Step 1: Add tests**

Append to the test file:

```elixir
describe "subscription upsell card" do
  test "renders for customer with no active subscription", %{conn: conn} do
    customer = register_customer()
    {appt, _service, _address} = create_appointment(customer)

    {:ok, _view, html} = live(conn, ~p"/book/success?id=#{appt.id}")

    assert html =~ "Save 15% on every wash"
    assert html =~ ~p"/pricing"
  end

  test "hides for customer with active subscription", %{conn: conn} do
    alias MobileCarWash.Billing.{Subscription, SubscriptionPlan}

    customer = register_customer()
    {appt, _service, _address} = create_appointment(customer)

    {:ok, plan} =
      SubscriptionPlan
      |> Ash.Changeset.for_create(:create, %{
        name: "Test Monthly",
        slug: "test-monthly-#{System.unique_integer([:positive])}",
        price_cents: 4_900,
        interval: :month,
        washes_per_period: 2
      })
      |> Ash.create()

    {:ok, _sub} =
      Subscription
      |> Ash.Changeset.for_create(:create, %{
        customer_id: customer.id,
        subscription_plan_id: plan.id,
        status: :active,
        stripe_subscription_id: "sub_#{System.unique_integer([:positive])}"
      })
      |> Ash.create()

    {:ok, _view, html} = live(conn, ~p"/book/success?id=#{appt.id}")

    refute html =~ "Save 15% on every wash"
  end
end
```

> **Implementer note:** Inspect `lib/mobile_car_wash/billing/subscription_plan.ex` and `lib/mobile_car_wash/billing/subscription.ex` first to verify the create-action attribute names (`name`, `slug`, `price_cents`, `interval`, `washes_per_period`, `status`, `stripe_subscription_id`). If any name differs, adjust the test fixture accordingly. Do NOT change the production code to match the test — fix the test.

- [ ] **Step 2: Run tests — expect FAIL on the upsell card**

Run: `mix test test/mobile_car_wash_web/live/booking_success_live_test.exs`

Expected: FAIL — upsell card markup not present.

- [ ] **Step 3: Add upsell card markup**

In `booking_success_live.ex`, AFTER the next-steps grid `<div class="mt-8 grid ...">` block and BEFORE the closing `</div>` of `<div :if={!@not_found}>`:

```heex
<%!-- Subscription upsell --%>
<div
  :if={@active_subscription == nil}
  class="mt-6 rounded-xl bg-cyan-500/5 ring-1 ring-cyan-500/20 p-5 sm:p-6"
>
  <h3 class="text-lg font-semibold text-base-content">Save 15% on every wash.</h3>
  <p class="mt-1 text-sm text-base-content/70">
    A monthly plan covers two washes a month and locks in your spot.
  </p>
  <.link navigate={~p"/pricing"} class="btn btn-primary btn-sm mt-4">
    See plans →
  </.link>
</div>
```

- [ ] **Step 4: Run tests — expect PASS**

Run: `mix test test/mobile_car_wash_web/live/booking_success_live_test.exs`

Expected: PASS on all tests.

- [ ] **Step 5: Commit**

```bash
git add lib/mobile_car_wash_web/live/booking_success_live.ex test/mobile_car_wash_web/live/booking_success_live_test.exs
git commit -m "booking_success: add subscription upsell card (gated on active sub)"
```

---

## Task 5: Referral card + ClipboardCopy hook

**Files:**
- Test: `test/mobile_car_wash_web/live/booking_success_live_test.exs` (modify)
- Modify: `lib/mobile_car_wash_web/live/booking_success_live.ex`
- Modify: `assets/js/app.js` (add ClipboardCopy hook)

**Context:** Card renders only when `customer.referral_code` is set. Copy button uses a tiny `phx-hook` to avoid inline JS (CSP-friendly).

- [ ] **Step 1: Add tests**

Append:

```elixir
describe "referral card" do
  test "renders when customer has a referral code", %{conn: conn} do
    customer = register_customer(referral_code: "FRIEND123")
    {appt, _service, _address} = create_appointment(customer)

    {:ok, _view, html} = live(conn, ~p"/book/success?id=#{appt.id}")

    assert html =~ "Give a friend $10 off"
    assert html =~ "FRIEND123"
  end

  test "hides when customer has no referral code", %{conn: conn} do
    customer = register_customer()
    {appt, _service, _address} = create_appointment(customer)

    refute customer.referral_code
    {:ok, _view, html} = live(conn, ~p"/book/success?id=#{appt.id}")

    refute html =~ "Give a friend $10 off"
  end
end
```

> **Implementer note:** `register_customer(referral_code: "FRIEND123")` already supports the option via the helper in Task 1 (it does an `:update` after create). If the `Customer` resource's `:update` action does not accept `referral_code` — check `lib/mobile_car_wash/accounts/customer.ex` — adjust the helper to use `Ash.Changeset.force_change_attribute/3` instead. Do NOT modify production code.

- [ ] **Step 2: Add the JS hook**

Open `assets/js/app.js`. Find the existing `Hooks` object (search for `let Hooks = {}` or similar). Add this hook:

```javascript
Hooks.ClipboardCopy = {
  mounted() {
    this.el.addEventListener("click", () => {
      const text = this.el.dataset.copyText
      if (text && navigator.clipboard) {
        navigator.clipboard.writeText(text).then(() => {
          const original = this.el.textContent
          this.el.textContent = "Copied!"
          setTimeout(() => { this.el.textContent = original }, 1500)
        })
      }
    })
  }
}
```

If `app.js` has no `Hooks` object yet (unlikely but possible), follow this pattern: declare `let Hooks = {}` before `LiveSocket` instantiation, register it on the socket via `new LiveSocket(..., {hooks: Hooks, ...})`. Verify the existing socket config first; do not duplicate.

- [ ] **Step 3: Add referral card markup**

In `booking_success_live.ex`, after the subscription upsell `<div :if={@active_subscription == nil}...>` block:

```heex
<%!-- Referral card --%>
<div
  :if={@customer && @customer.referral_code}
  class="mt-4 rounded-xl bg-base-200 p-5 sm:p-6"
>
  <h3 class="text-lg font-semibold text-base-content">Give a friend $10 off.</h3>
  <p class="mt-1 text-sm text-base-content/70">
    Share your code — they save, you save next time.
  </p>
  <div class="mt-4 flex items-center gap-2">
    <code class="font-mono px-3 py-1 bg-base-100 rounded text-sm">
      {@customer.referral_code}
    </code>
    <button
      type="button"
      phx-hook="ClipboardCopy"
      id={"copy-referral-#{@customer.id}"}
      data-copy-text={@customer.referral_code}
      class="btn btn-ghost btn-xs"
    >
      Copy
    </button>
  </div>
</div>
```

- [ ] **Step 4: Run tests — expect PASS**

Run: `mix test test/mobile_car_wash_web/live/booking_success_live_test.exs`

Expected: PASS on all tests.

- [ ] **Step 5: Commit**

```bash
git add lib/mobile_car_wash_web/live/booking_success_live.ex test/mobile_car_wash_web/live/booking_success_live_test.exs assets/js/app.js
git commit -m "booking_success: add referral card with ClipboardCopy hook"
```

---

## Task 6: Footer + error state contact lines

**Files:**
- Test: `test/mobile_car_wash_web/live/booking_success_live_test.exs` (modify)
- Modify: `lib/mobile_car_wash_web/live/booking_success_live.ex`

**Context:** Footer adds the review note + booking ID + back-to-home link. Error state needs contact rows. Plan instructs: grep for existing business-contact config (`lib/mobile_car_wash/marketing/`, `config/runtime.exs`, anywhere obvious) before falling back to hardcoded values.

- [ ] **Step 1: Look for existing contact config**

Run from worktree root:
```bash
grep -rn "support_email\|support_phone\|hello@drivewaydetailcosa\|business_email\|business_phone" lib/mobile_car_wash/ config/ 2>/dev/null | head -20
```

If a helper like `Marketing.support_email/0` exists, use it. Otherwise the spec authorizes a hardcoded fallback:
- Email: `hello@drivewaydetailcosa.com`
- Phone: `(210) 555-0100`

Note in the commit message which path you took.

- [ ] **Step 2: Add tests**

Append:

```elixir
describe "footer area (happy path)" do
  test "renders review note + booking ID + back-to-home link", %{conn: conn} do
    customer = register_customer()
    {appt, _service, _address} = create_appointment(customer)

    {:ok, _view, html} = live(conn, ~p"/book/success?id=#{appt.id}")

    assert html =~ "we&#39;ll text you a link to leave a review"
    assert html =~ "Booking ID:"
    assert html =~ to_string(appt.id)
    assert html =~ "← Back to home"
  end
end

describe "error state" do
  test "renders friendly heading + contact info when params are missing", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/book/success")

    assert html =~ "We couldn&#39;t find that booking."
    assert html =~ "If you completed payment, contact us"
    assert html =~ "mailto:"
    assert html =~ "tel:"
  end

  test "renders error state when id does not resolve", %{conn: conn} do
    bogus_id = Ecto.UUID.generate()

    {:ok, _view, html} = live(conn, ~p"/book/success?id=#{bogus_id}")

    assert html =~ "We couldn&#39;t find that booking."
  end

  test "renders error state when session_id does not resolve", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/book/success?session_id=cs_test_doesnotexist")

    assert html =~ "We couldn&#39;t find that booking."
  end
end
```

- [ ] **Step 3: Run tests — expect FAIL**

Run: `mix test test/mobile_car_wash_web/live/booking_success_live_test.exs`

Expected: FAIL on the new cases.

- [ ] **Step 4: Add footer markup (happy path)**

In `booking_success_live.ex`, AFTER the referral card block, BEFORE closing `</div>` of `<div :if={!@not_found}>`:

```heex
<%!-- Footer --%>
<div class="mt-8 space-y-2 text-sm text-base-content/60">
  <p>After your appointment, we'll text you a link to leave a review.</p>
  <p>Booking ID: <span class="font-mono text-xs">{@appointment.id}</span></p>
</div>
<div class="mt-6">
  <.link navigate={~p"/"} class="btn btn-ghost btn-sm">← Back to home</.link>
</div>
```

- [ ] **Step 5: Update error state markup with contact lines**

Replace the existing `<div :if={@not_found}>` block in `booking_success_live.ex` with:

```heex
<div :if={@not_found}>
  <h1 class="text-2xl font-bold mb-4">We couldn't find that booking.</h1>
  <p class="text-base-content/70 mb-6">
    If you completed payment, contact us and we'll sort it out — we have your details.
  </p>
  <ul class="space-y-2 mb-6 text-sm">
    <li class="flex items-center gap-2">
      <.icon name="hero-envelope" class="h-4 w-4 text-cyan-500" />
      <a href="mailto:hello@drivewaydetailcosa.com" class="text-cyan-600 hover:underline">
        hello@drivewaydetailcosa.com
      </a>
    </li>
    <li class="flex items-center gap-2">
      <.icon name="hero-phone" class="h-4 w-4 text-cyan-500" />
      <a href="tel:+12105550100" class="text-cyan-600 hover:underline">(210) 555-0100</a>
    </li>
  </ul>
  <.link navigate={~p"/"} class="btn btn-ghost btn-sm">← Back to home</.link>
</div>
```

> **If a contact-config helper was found in Step 1**, replace the hardcoded email/phone with the helper calls. Update the test assertion at the same time so the test stays meaningful.

- [ ] **Step 6: Run tests — expect PASS**

Run: `mix test test/mobile_car_wash_web/live/booking_success_live_test.exs`

Expected: PASS on all tests.

- [ ] **Step 7: Commit**

```bash
git add lib/mobile_car_wash_web/live/booking_success_live.ex test/mobile_car_wash_web/live/booking_success_live_test.exs
git commit -m "booking_success: add footer (review note + booking ID) and error-state contact lines"
```

---

## Task 7: BookingCalendarController + `.ics` route

**Files:**
- Create: `lib/mobile_car_wash_web/controllers/booking_calendar_controller.ex`
- Create: `test/mobile_car_wash_web/controllers/booking_calendar_controller_test.exs`
- Modify: `lib/mobile_car_wash_web/router.ex`

**Context:** Backs the "Download .ics" button. Generates a minimal RFC 5545–compliant VCALENDAR/VEVENT and serves it with the right headers.

- [ ] **Step 1: Write the controller test (file creation)**

Create `test/mobile_car_wash_web/controllers/booking_calendar_controller_test.exs`:

```elixir
defmodule MobileCarWashWeb.BookingCalendarControllerTest do
  @moduledoc """
  Verifies the GET /book/:id/calendar.ics endpoint that backs the
  "Download .ics" button on the booking success page.
  """
  use MobileCarWashWeb.ConnCase, async: false

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Fleet.{Address, Vehicle}
  alias MobileCarWash.Scheduling.{Appointment, ServiceType}

  defp setup_appointment do
    {:ok, customer} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "ics-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "ICS Test",
        phone: "+15125558700"
      })
      |> Ash.create()

    {:ok, service} =
      ServiceType
      |> Ash.Changeset.for_create(:create, %{
        name: "Premium Detail",
        slug: "ics-svc-#{System.unique_integer([:positive])}",
        base_price_cents: 8_900,
        duration_minutes: 90
      })
      |> Ash.create()

    {:ok, vehicle} =
      Vehicle
      |> Ash.Changeset.for_create(:create, %{make: "BMW", model: "M3"})
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create()

    {:ok, address} =
      Address
      |> Ash.Changeset.for_create(:create, %{
        street: "1717 ICS Lane",
        city: "San Antonio",
        state: "TX",
        zip: "78261"
      })
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create()

    {:ok, appt} =
      Appointment
      |> Ash.Changeset.for_create(:book, %{
        customer_id: customer.id,
        vehicle_id: vehicle.id,
        address_id: address.id,
        service_type_id: service.id,
        scheduled_at: DateTime.add(DateTime.utc_now(), 3 * 86_400, :second),
        price_cents: 8_900,
        duration_minutes: 90
      })
      |> Ash.create()

    {appt, service, address}
  end

  describe "GET /book/:id/calendar.ics" do
    test "returns 200 with text/calendar content type", %{conn: conn} do
      {appt, _service, _address} = setup_appointment()

      conn = get(conn, ~p"/book/#{appt.id}/calendar.ics")

      assert conn.status == 200

      content_type =
        conn
        |> Plug.Conn.get_resp_header("content-type")
        |> List.first()

      assert content_type =~ "text/calendar"
    end

    test "body contains VCALENDAR scaffolding + service name + UTC DTSTART", %{conn: conn} do
      {appt, service, _address} = setup_appointment()

      conn = get(conn, ~p"/book/#{appt.id}/calendar.ics")
      body = conn.resp_body

      assert body =~ "BEGIN:VCALENDAR"
      assert body =~ "END:VCALENDAR"
      assert body =~ "BEGIN:VEVENT"
      assert body =~ "END:VEVENT"
      assert body =~ "SUMMARY:#{service.name}"

      expected_dtstart =
        appt.scheduled_at
        |> DateTime.shift_zone!("Etc/UTC")
        |> Calendar.strftime("%Y%m%dT%H%M%SZ")

      assert body =~ "DTSTART:#{expected_dtstart}"
    end

    test "body contains the full address as LOCATION", %{conn: conn} do
      {appt, _service, address} = setup_appointment()

      conn = get(conn, ~p"/book/#{appt.id}/calendar.ics")
      body = conn.resp_body

      assert body =~ "LOCATION:#{address.street}"
      assert body =~ address.city
      assert body =~ address.zip
    end

    test "Content-Disposition is attachment with booking-<id>.ics filename", %{conn: conn} do
      {appt, _service, _address} = setup_appointment()

      conn = get(conn, ~p"/book/#{appt.id}/calendar.ics")

      disposition =
        conn
        |> Plug.Conn.get_resp_header("content-disposition")
        |> List.first()

      assert disposition =~ "attachment"
      assert disposition =~ "booking-#{appt.id}.ics"
    end

    test "returns 404 for unknown id", %{conn: conn} do
      bogus_id = Ecto.UUID.generate()

      conn = get(conn, ~p"/book/#{bogus_id}/calendar.ics")

      assert conn.status == 404
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/mobile_car_wash_web/controllers/booking_calendar_controller_test.exs`

Expected: FAIL — route doesn't exist (404 from Phoenix's no-match handler, or compile error if helper sigil can't find the route).

If `~p"/book/.../calendar.ics"` raises a verified-routes compile warning that prevents the suite from running: temporarily change to a string literal `"/book/#{appt.id}/calendar.ics"` until the route is added. Restore the `~p` form after Step 4.

- [ ] **Step 3: Create the controller**

Create `lib/mobile_car_wash_web/controllers/booking_calendar_controller.ex`:

```elixir
defmodule MobileCarWashWeb.BookingCalendarController do
  @moduledoc """
  Serves an iCalendar (.ics) file for a booked appointment so the customer
  can drop it into Apple Calendar / any RFC 5545–capable client. Linked
  from the BookingSuccessLive "Download .ics" button.
  """
  use MobileCarWashWeb, :controller

  alias MobileCarWash.Scheduling.{Appointment, ServiceType}
  alias MobileCarWash.Fleet.Address

  def show(conn, %{"id" => appointment_id}) do
    case load_appointment(appointment_id) do
      {:ok, appointment, service, address} ->
        body = build_ics(appointment, service, address)

        conn
        |> put_resp_header("content-type", "text/calendar; charset=utf-8")
        |> put_resp_header(
          "content-disposition",
          ~s|attachment; filename="booking-#{appointment.id}.ics"|
        )
        |> send_resp(200, body)

      :error ->
        conn
        |> put_status(:not_found)
        |> text("Booking not found.")
    end
  end

  # === Private helpers ===

  defp load_appointment(appointment_id) do
    appointment = Ash.get!(Appointment, appointment_id)
    service = Ash.get!(ServiceType, appointment.service_type_id)

    address =
      case appointment.address_id do
        nil -> nil
        addr_id -> Ash.get!(Address, addr_id)
      end

    {:ok, appointment, service, address}
  rescue
    _ -> :error
  end

  defp build_ics(appointment, service, address) do
    duration = appointment.duration_minutes || 90

    dtstart =
      appointment.scheduled_at
      |> DateTime.shift_zone!("Etc/UTC")
      |> Calendar.strftime("%Y%m%dT%H%M%SZ")

    dtend =
      appointment.scheduled_at
      |> DateTime.add(duration * 60, :second)
      |> DateTime.shift_zone!("Etc/UTC")
      |> Calendar.strftime("%Y%m%dT%H%M%SZ")

    dtstamp =
      DateTime.utc_now()
      |> Calendar.strftime("%Y%m%dT%H%M%SZ")

    location = format_address(address)

    [
      "BEGIN:VCALENDAR",
      "VERSION:2.0",
      "PRODID:-//Driveway Detail Co//Booking//EN",
      "CALSCALE:GREGORIAN",
      "METHOD:PUBLISH",
      "BEGIN:VEVENT",
      "UID:#{appointment.id}@drivewaydetailcosa.com",
      "DTSTAMP:#{dtstamp}",
      "DTSTART:#{dtstart}",
      "DTEND:#{dtend}",
      "SUMMARY:#{service.name}",
      "DESCRIPTION:Booking ID: #{appointment.id}\\nService: #{service.name}\\nWe'll text you 30 minutes before arrival.",
      "LOCATION:#{location}",
      "STATUS:CONFIRMED",
      "END:VEVENT",
      "END:VCALENDAR"
    ]
    |> Enum.join("\r\n")
    |> Kernel.<>("\r\n")
  end

  defp format_address(nil), do: ""

  defp format_address(address) do
    "#{address.street}, #{address.city}, #{address.state} #{address.zip}"
  end
end
```

- [ ] **Step 4: Add the route**

Open `lib/mobile_car_wash_web/router.ex`. Find the scope that contains `live "/book/success", BookingSuccessLive` (around line 142). Inside the SAME `scope "/", MobileCarWashWeb do ... pipe_through ... end` block, add ABOVE or BELOW the `live` declaration:

```elixir
get "/book/:id/calendar.ics", BookingCalendarController, :show
```

Make sure it's inside a scope that uses the `:browser` pipeline (so session/headers work) — the same scope that contains the existing `live "/book/success", BookingSuccessLive` is correct.

- [ ] **Step 5: Run tests — expect PASS**

Run: `mix test test/mobile_car_wash_web/controllers/booking_calendar_controller_test.exs`

Expected: PASS (5 tests).

- [ ] **Step 6: Run the full LiveView test file too — make sure nothing regressed**

Run: `mix test test/mobile_car_wash_web/live/booking_success_live_test.exs`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/mobile_car_wash_web/controllers/booking_calendar_controller.ex test/mobile_car_wash_web/controllers/booking_calendar_controller_test.exs lib/mobile_car_wash_web/router.ex
git commit -m "booking_success: add BookingCalendarController + /book/:id/calendar.ics route"
```

---

## Task 8: Final verification + manual smoke check

**Files:** none

- [ ] **Step 1: Run the full test suite**

Run from worktree root: `mix test`

Expected: all tests pass, 0 failures, no warnings about unused vars / undefined routes / unmatched function clauses.

- [ ] **Step 2: Run `mix precommit` if it exists**

```bash
mix precommit 2>/dev/null || echo "no precommit alias"
```

If it runs: must pass clean. If failures: fix before continuing.

- [ ] **Step 3: Manual smoke check (browser)**

Start the dev server: `mix phx.server`

Open in browser:
- `http://localhost:4000/book/success` → should show error state with contact info (no crash)
- `http://localhost:4000/book/success?id=<a real appointment uuid from your dev DB>` → should show full redesigned page

If you don't have a dev appointment, skip this and rely on the test suite — production verification will happen post-merge.

- [ ] **Step 4: No commit needed for verification step.**

---

## Acceptance Checklist (verify before handoff)

- [ ] `/book/success?session_id=cs_test_…` renders the redesigned page after Stripe Checkout (covered by Task 1 + Task 7's session-id branch via existing mount).
- [ ] `/book/success?id=<uuid>` renders the same page (Task 1 — bug fix).
- [ ] Subscription banner hidden for active subscribers (Task 4).
- [ ] Referral card hidden when no `referral_code` (Task 5).
- [ ] Calendar buttons present with correct hrefs (Task 3 + Task 7).
- [ ] Get directions link points at Google Maps with the encoded address (Task 3).
- [ ] Error state shows contact lines, not a crash (Task 6).
- [ ] `.ics` file downloads cleanly with valid VCALENDAR body (Task 7).
- [ ] Full test suite green (Task 8).
- [ ] No regressions in existing booking flow tests (Task 8).

---

## Out of Scope (do NOT include)

- Wallaby end-to-end coverage — Plan 5.
- Changes to Stripe Checkout `success_url` or webhook handlers.
- Live review collection UI — only the deferred "we'll text you" note ships.
- Static map images / Maps API key wiring.
- Subscription tier comparison grid.
- SMS reminder system changes.
- Mobile push notifications.
