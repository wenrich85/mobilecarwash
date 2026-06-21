# Booking Process Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close eight booking-flow gaps surfaced by a flow analysis — out-of-area waitlist capture, geocoder-failure surfacing, guest-email sign-in affordance, email block-scheduled parity, add-on vehicle-size pricing, four discount/pricing test gaps, plus a low-stock hint and mobile-payment test coverage.

**Architecture:** The booking flow is a single-page LiveView (`booking_live.ex`) gated by `booking_sections.ex`, submitting through the transactional `Scheduling.Booking.create_booking/1`. Pricing is centralized in the pure `Billing.Pricing` module (consumed by both the live hero and the server charge path). Confirmed-arrival notifications already fan out from `Scheduling.BlockOptimizer`. This plan extends those existing seams rather than adding new ones, plus one new Ash resource (`Marketing.Waitlist`).

**Tech Stack:** Elixir, Phoenix LiveView, Ash + AshPostgres, Oban, Swoosh (email), Stripe (mocked in test), ExUnit.

## Global Constraints

- `mix precommit` must pass: `compile --warnings-as-errors`, `deps.unlock --unused`, `format`, `test` (mix.exs:133). No compiler warnings.
- Ash migrations are generated with `mix ash.codegen <name>` then applied with `mix ecto.migrate` (mix.exs:121).
- Pricing money is integer **cents** throughout. Vehicle-size multipliers live only in `Billing.Pricing` (`car: 1.0, suv_van: 1.2, pickup: 1.5`).
- The live price hero total MUST equal the server-charged `appointment.price_cents` for the same inputs — this parity is non-negotiable.
- Unauthenticated/guest writes use `authorize?: false` (existing convention, e.g. `ensure_customer/1`, `Referrals`).
- Service-area zone comes from `address.zone` (`nil` = outside area). Customer-facing brand name is "Driveway Detail Co".

---

## Task 1: `Marketing.Waitlist` Ash resource

Captures out-of-area leads. New resource in the existing `Marketing` domain, modeled on `Marketing.MarketingSpend`.

**Files:**
- Create: `lib/mobile_car_wash/marketing/waitlist.ex`
- Modify: `lib/mobile_car_wash/marketing.ex:13-31` (alias + `resource` registration)
- Create (generated): `priv/repo/migrations/*_add_waitlist_entries.exs`
- Test: `test/mobile_car_wash/marketing/waitlist_test.exs`

**Interfaces:**
- Produces: `MobileCarWash.Marketing.Waitlist` with create action `:join` accepting
  `[:email, :name, :phone, :address_text, :zip, :latitude, :longitude, :requested_service_slug]`.
  `:read` for tests/admin. Read policy `always()`; create policy `always()` (public lead capture).

- [ ] **Step 1: Write the failing test**

```elixir
# test/mobile_car_wash/marketing/waitlist_test.exs
defmodule MobileCarWash.Marketing.WaitlistTest do
  use MobileCarWash.DataCase, async: true

  alias MobileCarWash.Marketing.Waitlist

  test "join/1 captures a lead with the entered address" do
    {:ok, entry} =
      Waitlist
      |> Ash.Changeset.for_create(:join, %{
        email: "lead@example.com",
        name: "Lead Person",
        phone: "5125551234",
        address_text: "1 Far Away Rd, Elsewhere, TX",
        zip: "00000",
        latitude: 30.1,
        longitude: -98.5,
        requested_service_slug: "basic_wash"
      })
      |> Ash.create(authorize?: false)

    assert entry.email == "lead@example.com"
    assert entry.zip == "00000"
    assert entry.requested_service_slug == "basic_wash"
  end

  test "join/1 requires an email" do
    assert {:error, _} =
             Waitlist
             |> Ash.Changeset.for_create(:join, %{address_text: "x", zip: "00000"})
             |> Ash.create(authorize?: false)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/mobile_car_wash/marketing/waitlist_test.exs`
Expected: FAIL — `MobileCarWash.Marketing.Waitlist` is undefined / module not loaded.

- [ ] **Step 3: Create the resource**

```elixir
# lib/mobile_car_wash/marketing/waitlist.ex
defmodule MobileCarWash.Marketing.Waitlist do
  @moduledoc """
  Out-of-area lead capture. When a customer's address falls outside the
  service zones, the booking flow blocks payment and records the lead here
  for later outreach.
  """
  use Ash.Resource,
    otp_app: :mobile_car_wash,
    domain: MobileCarWash.Marketing,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("waitlist_entries")
    repo(MobileCarWash.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :email, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute(:name, :string, public?: true)
    attribute(:phone, :string, public?: true)

    attribute :address_text, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :zip, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute(:latitude, :float, public?: true)
    attribute(:longitude, :float, public?: true)
    attribute(:requested_service_slug, :string, public?: true)

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  actions do
    defaults([:read])

    create :join do
      accept([
        :email,
        :name,
        :phone,
        :address_text,
        :zip,
        :latitude,
        :longitude,
        :requested_service_slug
      ])
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if(always())
    end

    policy action_type(:create) do
      authorize_if(always())
    end
  end
end
```

- [ ] **Step 4: Register the resource in the domain**

In `lib/mobile_car_wash/marketing.ex`, add `Waitlist` to the alias block (lines 13-21) and the `resources do` block (lines 23-31):

```elixir
  alias MobileCarWash.Marketing.{
    AcquisitionChannel,
    CustomerTag,
    MarketingSpend,
    Persona,
    PersonaMembership,
    Post,
    Tag,
    Waitlist
  }

  resources do
    resource(AcquisitionChannel)
    resource(CustomerTag)
    resource(MarketingSpend)
    resource(Persona)
    resource(PersonaMembership)
    resource(Post)
    resource(Tag)
    resource(Waitlist)
  end
```

- [ ] **Step 5: Generate and apply the migration**

Run:
```bash
mix ash.codegen add_waitlist_entries
mix ecto.migrate
```
Expected: a new migration under `priv/repo/migrations/` creating `waitlist_entries`; migrate succeeds.

- [ ] **Step 6: Run test to verify it passes**

Run: `mix test test/mobile_car_wash/marketing/waitlist_test.exs`
Expected: PASS (2 tests).

- [ ] **Step 7: Commit**

```bash
git add lib/mobile_car_wash/marketing/waitlist.ex lib/mobile_car_wash/marketing.ex priv/repo/migrations test/mobile_car_wash/marketing/waitlist_test.exs
git commit -m "feat(waitlist): add Marketing.Waitlist resource for out-of-area leads"
```

---

## Task 2: Out-of-area waitlist capture + server-side pay guard

When the selected address has `zone: nil`, block payment and show a waitlist panel; reject the booking server-side regardless of client state.

**Files:**
- Modify: `lib/mobile_car_wash_web/live/booking_live.ex` (confirm_booking handler ~1178; add `join_waitlist` handler + `out_of_area?/1` helper; review-section render)
- Test: `test/mobile_car_wash_web/live/booking_single_page_test.exs` (add cases)

**Interfaces:**
- Consumes: `MobileCarWash.Marketing.Waitlist` `:join` (Task 1).
- Produces: `out_of_area?/1` private predicate over assigns; `"join_waitlist"` LiveView event.

- [ ] **Step 1: Write the failing test**

Add to `test/mobile_car_wash_web/live/booking_single_page_test.exs`. (The existing `setup` seeds a `basic_wash` ServiceType; `GeocoderClientMock` and `create_open_block/1` helpers exist in this file.)

```elixir
  test "out-of-area address blocks payment and offers the waitlist", %{conn: conn} do
    service = Ash.read_first!(MobileCarWash.Scheduling.ServiceType)
    {:ok, lv, _html} = live(conn, ~p"/book")

    # Drive the flow far enough that the review section is reachable, then
    # set an out-of-area (zone: nil) address via the manual entry form.
    render_click(lv, "select_service", %{"slug" => service.slug})

    html =
      lv
      |> form("form[phx-submit=save_address]",
        address: %{street: "1 Far Rd", city: "Nowhere", state: "TX", zip: "00000"}
      )
      |> render_submit()

    assert html =~ "Outside our service area"
    refute has_element?(lv, "button[phx-click=confirm_booking]")
    assert has_element?(lv, "button[phx-click=join_waitlist]")
  end

  test "join_waitlist records a lead", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/book")
    service = Ash.read_first!(MobileCarWash.Scheduling.ServiceType)
    render_click(lv, "select_service", %{"slug" => service.slug})

    lv
    |> form("form[phx-submit=save_address]",
      address: %{street: "1 Far Rd", city: "Nowhere", state: "TX", zip: "00000"}
    )
    |> render_submit()

    render_submit(lv, "join_waitlist", %{"email" => "lead@example.com"})

    entries = Ash.read!(MobileCarWash.Marketing.Waitlist, authorize?: false)
    assert Enum.any?(entries, &(&1.email == "lead@example.com"))
  end
```

> Note: if `Ash.read_first!/1` is unavailable, use
> `MobileCarWash.Scheduling.ServiceType |> Ash.read!() |> hd()`.

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/mobile_car_wash_web/live/booking_single_page_test.exs -k "out-of-area address blocks"`
Expected: FAIL — `join_waitlist` button absent / event unhandled.

- [ ] **Step 3: Add the `out_of_area?/1` helper and guard `confirm_booking`**

In `booking_live.ex`, add the helper near the other private helpers (after `ensure_customer`):

```elixir
  defp out_of_area?(%{selected_address: %{zone: nil}}), do: true
  defp out_of_area?(_), do: false
```

Replace the `confirm_booking` handler (currently `booking_live.ex:1178-1189`) with a guarded version:

```elixir
  def handle_event("confirm_booking", _params, socket) do
    cond do
      out_of_area?(socket.assigns) ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "That address is outside our service area. Join the waitlist below and we'll reach out."
         )}

      BookingSections.payable?(build_context(socket.assigns)) ->
        with {:ok, socket} <- ensure_customer(socket),
             {:ok, socket} <- persist_pending_records(socket) do
          do_confirm_booking(socket)
        else
          {:error, message} -> {:noreply, assign(socket, guest_error: message)}
        end

      true ->
        {:noreply, put_flash(socket, :error, "Please complete all sections before paying.")}
    end
  end
```

- [ ] **Step 4: Add the `join_waitlist` handler**

Add near the other `handle_event` clauses:

```elixir
  def handle_event("join_waitlist", %{"email" => email}, socket) do
    addr = socket.assigns.selected_address
    service = socket.assigns.selected_service

    attrs = %{
      email: email,
      name: socket.assigns[:guest_form]["name"],
      phone: socket.assigns[:guest_form]["phone"],
      address_text: addr && "#{addr.street}, #{addr.city}, #{addr.state} #{addr.zip}",
      zip: addr && addr.zip,
      latitude: addr && addr.latitude,
      longitude: addr && addr.longitude,
      requested_service_slug: service && service.slug
    }

    case MobileCarWash.Marketing.Waitlist
         |> Ash.Changeset.for_create(:join, attrs)
         |> Ash.create(authorize?: false) do
      {:ok, _entry} ->
        {:noreply,
         put_flash(socket, :info, "Thanks — we'll let you know when we reach your area.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Please enter a valid email.")}
    end
  end
```

> If `socket.assigns.guest_form` may be unset for signed-in customers, guard with
> `(socket.assigns[:guest_form] || %{})["name"]`. Confirm the assign name matches
> `ensure_customer/1` (`booking_live.ex:1292`) which reads `socket.assigns.guest_form`.

- [ ] **Step 5: Render the waitlist panel and gate the Pay button**

In the Review & Pay section, locate the Pay button (the element with `phx-click="confirm_booking"`). Wrap it so it only renders when in-area, and add the waitlist panel for out-of-area:

```heex
        <button
          :if={not out_of_area?(assigns)}
          type="button"
          phx-click="confirm_booking"
          ...existing attrs...
        >
          ...existing label...
        </button>

        <div
          :if={out_of_area?(assigns)}
          class="bg-warning/10 border border-warning/30 rounded-box p-5 space-y-3"
        >
          <p class="text-sm font-semibold">We're not in your area yet.</p>
          <p class="text-sm text-base-content/70">
            Leave your email and we'll let you know the moment we start serving your neighborhood.
          </p>
          <form phx-submit="join_waitlist" class="flex gap-2">
            <.input
              name="email"
              type="email"
              value={(@current_customer && to_string(@current_customer.email)) || (@guest_form && @guest_form["email"]) || ""}
              placeholder="you@example.com"
              required
            />
            <button type="submit" class="btn btn-primary">Notify me</button>
          </form>
        </div>
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `mix test test/mobile_car_wash_web/live/booking_single_page_test.exs`
Expected: PASS, including the two new cases.

- [ ] **Step 7: Commit**

```bash
git add lib/mobile_car_wash_web/live/booking_live.ex test/mobile_car_wash_web/live/booking_single_page_test.exs
git commit -m "feat(booking): waitlist capture + server guard for out-of-area addresses"
```

---

## Task 3: Surface geocoder failures

Replace the silent empty-list behavior on geocoder error with a user-visible message and the manual-entry form expanded.

**Files:**
- Modify: `lib/mobile_car_wash_web/live/booking_live.ex` (mount assign ~81; `address_search` handler ~1036-1043; `handle_async(:geocode_suggest, ...)` ~1270-1280; address-section render ~472-519)
- Test: `test/mobile_car_wash_web/live/booking_single_page_test.exs`

**Interfaces:**
- Produces: `geocoder_error` boolean assign (default `false`).

- [ ] **Step 1: Write the failing test**

The `GeocoderClientMock` supports `put_error/2` (per memory #9626-9628). Add:

```elixir
  test "geocoder failure shows an error and surfaces manual entry", %{conn: conn} do
    GeocoderClientMock.put_error("broken st", {:error, :geocoder_unavailable})
    {:ok, lv, _html} = live(conn, ~p"/book")
    service = Ash.read!(MobileCarWash.Scheduling.ServiceType) |> hd()
    render_click(lv, "select_service", %{"slug" => service.slug})

    html = render_change(lv, "address_search", %{"q" => "broken st"})
    # async runs; re-render
    html = render(lv)

    assert html =~ "having trouble"
  end
```

> Confirm `GeocoderClientMock.put_error/2`'s exact arity/shape in
> `test/support/` before finalizing; adjust the seeding call to match.

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/mobile_car_wash_web/live/booking_single_page_test.exs -k "geocoder failure"`
Expected: FAIL — no "having trouble" copy rendered.

- [ ] **Step 3: Add the default assign**

In `mount/3`, alongside `address_suggestions: [], loading_suggestions: false` (`booking_live.ex:81-82`), add:

```elixir
        geocoder_error: false,
```

- [ ] **Step 4: Set/clear the flag in the async + search handlers**

Replace the two failure clauses (`booking_live.ex:1274-1280`):

```elixir
  def handle_async(:geocode_suggest, {:ok, {:ok, suggestions}}, socket) do
    {:noreply,
     assign(socket,
       address_suggestions: suggestions,
       loading_suggestions: false,
       geocoder_error: false
     )}
  end

  def handle_async(:geocode_suggest, {:ok, {:error, _reason}}, socket) do
    {:noreply,
     assign(socket, address_suggestions: [], loading_suggestions: false, geocoder_error: true)}
  end

  def handle_async(:geocode_suggest, {:exit, _reason}, socket) do
    {:noreply,
     assign(socket, address_suggestions: [], loading_suggestions: false, geocoder_error: true)}
  end
```

In the `address_search` handler, clear the flag when a new query starts (`booking_live.ex:1041-1043`, the `start_async` branch):

```elixir
       |> assign(address_query: q, loading_suggestions: true, geocoder_error: false)
       |> start_async(:geocode_suggest, fn -> GeocoderClient.suggest(q) end)}
```

- [ ] **Step 5: Render the error + expand manual entry**

After the "Searching…" indicator (`booking_live.ex:472-474`), add:

```heex
        <div
          :if={@geocoder_error}
          class="bg-warning/10 border border-warning/30 rounded-lg p-3 mb-2 text-sm text-warning"
        >
          Address lookup is having trouble right now — please enter your address manually below.
        </div>
```

Change the manual-entry `<details>` (`booking_live.ex:493`) to auto-open on error:

```heex
        <details class="mb-4" open={@geocoder_error}>
```

- [ ] **Step 6: Run test to verify it passes**

Run: `mix test test/mobile_car_wash_web/live/booking_single_page_test.exs -k "geocoder failure"`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/mobile_car_wash_web/live/booking_live.ex test/mobile_car_wash_web/live/booking_single_page_test.exs
git commit -m "fix(booking): surface geocoder failures instead of empty suggestions"
```

---

## Task 4: Guest-email sign-in affordance

When a guest enters an email belonging to a registered account, render a sign-in link (route exists: `/book/sign-in`, stashes return path) rather than a bare error string.

**Files:**
- Modify: `lib/mobile_car_wash_web/live/booking_live.ex` (guest-error render in the review section)
- Test: `test/mobile_car_wash_web/live/booking_single_page_test.exs`

**Interfaces:**
- Consumes: `guest_error` assign set by `confirm_booking`/`ensure_customer` (existing, `booking_live.ex:1184`, `:1307`).

- [ ] **Step 1: Write the failing test**

```elixir
  test "guest email matching a registered account shows a sign-in link", %{conn: conn} do
    # A registered (password) customer already owns this email.
    Customer
    |> Ash.Changeset.for_create(:register_with_password, %{
      email: "taken@example.com",
      name: "Real Account",
      password: "password1234",
      password_confirmation: "password1234"
    })
    |> Ash.create!()

    {:ok, lv, _html} = live(conn, ~p"/book")
    # Simulate ensure_customer's existing-account error by asserting the
    # render reacts to a guest_error assign carrying that message.
    send(lv.pid, {:set_guest_error, "An account with this email already exists. Please sign in instead."})
    html = render(lv)

    assert html =~ "sign in"
    assert has_element?(lv, "a[href='/book/sign-in']")
  end
```

> If injecting state via `send/2` is undesirable, instead drive the full flow to
> the Pay step with a guest email equal to the registered one and assert on the
> post-`confirm_booking` render. Use whichever matches existing test style in the
> file; the assertion (`a[href='/book/sign-in']`) is the contract.

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/mobile_car_wash_web/live/booking_single_page_test.exs -k "sign-in link"`
Expected: FAIL — no sign-in anchor rendered.

- [ ] **Step 3: Render the guest-error block with a sign-in link**

Locate where `@guest_error` is currently rendered in the review section (it is set at `booking_live.ex:1184` / `:1307`). Replace/insert this block near the Pay button:

```heex
        <div
          :if={@guest_error}
          class="bg-error/10 border border-error/30 rounded-lg p-3 mb-3 text-sm text-error space-y-2"
        >
          <p>{@guest_error}</p>
          <.link
            navigate={~p"/book/sign-in"}
            class="btn btn-sm btn-outline"
          >
            Sign in to continue
          </.link>
        </div>
```

> If `@guest_error` is not currently assigned at mount, add `guest_error: nil` to
> the mount assigns to avoid a `KeyError` in the template.

- [ ] **Step 4: (If needed) handle the test injection message**

Only if Step 1 uses `send/2`, add a `handle_info` clause:

```elixir
  @impl true
  def handle_info({:set_guest_error, message}, socket) do
    {:noreply, assign(socket, guest_error: message)}
  end
```

> Prefer the full-flow assertion (Step 1 note) and skip this if it fits the
> existing test style — don't add test-only code paths to production unless needed.

- [ ] **Step 5: Run test to verify it passes**

Run: `mix test test/mobile_car_wash_web/live/booking_single_page_test.exs -k "sign-in link"`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/mobile_car_wash_web/live/booking_live.ex test/mobile_car_wash_web/live/booking_single_page_test.exs
git commit -m "feat(booking): offer sign-in link when guest email is a registered account"
```

---

## Task 5: Email parity for block-scheduled notifications

The optimizer already enqueues SMS + push when arrival times are assigned (`block_optimizer.ex:119-129`). Add an email worker for parity.

**Files:**
- Modify: `lib/mobile_car_wash/notifications/email.ex` (add `block_scheduled/4`)
- Create: `lib/mobile_car_wash/notifications/email_block_scheduled_worker.ex`
- Modify: `lib/mobile_car_wash/scheduling/block_optimizer.ex:16,119-129`
- Test: `test/mobile_car_wash/notifications/email_block_scheduled_worker_test.exs`

**Interfaces:**
- Consumes: `Email.booking_confirmation/4` shape (existing, email.ex:48).
- Produces: `Email.block_scheduled(appointment, service_type, customer, address)`;
  `MobileCarWash.Notifications.EmailBlockScheduledWorker` with `perform/1` on
  args `%{"appointment_id" => id}`.

- [ ] **Step 1: Write the failing test**

```elixir
# test/mobile_car_wash/notifications/email_block_scheduled_worker_test.exs
defmodule MobileCarWash.Notifications.EmailBlockScheduledWorkerTest do
  use MobileCarWash.DataCase, async: false
  import Swoosh.TestAssertions

  alias MobileCarWash.Notifications.{Email, EmailBlockScheduledWorker}

  test "block_scheduled/4 builds an email to the customer" do
    appt = %{
      id: "appt-1",
      scheduled_at: ~U[2026-07-01 15:00:00Z],
      price_cents: 5_000,
      duration_minutes: 45
    }

    service = %{name: "Basic Wash"}
    customer = %{name: "Sam", email: "sam@example.com"}
    address = %{street: "1 A St", city: "San Antonio", state: "TX", zip: "78261"}

    email = Email.block_scheduled(appt, service, customer, address)
    assert {_, "sam@example.com"} in email.to
    assert email.subject =~ "confirmed"
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/mobile_car_wash/notifications/email_block_scheduled_worker_test.exs`
Expected: FAIL — `Email.block_scheduled/4` undefined.

- [ ] **Step 3: Add the email template**

In `lib/mobile_car_wash/notifications/email.ex`, add after `booking_confirmation/4`:

```elixir
  @doc """
  Arrival-window-confirmed email — sent after the route optimizer assigns the
  exact arrival time inside the customer's booked block.
  """
  def block_scheduled(appointment, service_type, customer, address) do
    when_str = Calendar.strftime(appointment.scheduled_at, "%B %d, %Y at %I:%M %p")
    where_str = "#{address.street}, #{address.city}, #{address.state} #{address.zip}"

    inner_html = """
    <h2 style="margin:0 0 12px;font-size:20px;color:#0f172a;">Your arrival time is confirmed!</h2>
    <p>Hi #{customer.name},</p>
    <p>Your <strong>#{service_type.name}</strong> is scheduled. We'll arrive at:</p>
    <table cellpadding="0" cellspacing="0" style="margin:16px 0;">
      <tr><td style="padding:4px 16px 4px 0;color:#64748b;font-size:13px;">When</td><td style="padding:4px 0;font-weight:600;">#{when_str}</td></tr>
      <tr><td style="padding:4px 16px 4px 0;color:#64748b;font-size:13px;">Where</td><td style="padding:4px 0;font-weight:600;">#{where_str}</td></tr>
    </table>
    <p style="color:#64748b;font-size:12px;">Booking ID: <code>#{appointment.id}</code></p>
    """

    inner_text = """
    Your arrival time is confirmed!

    Hi #{customer.name},

    #{service_type.name}
    When: #{when_str}
    Where: #{where_str}

    Booking ID: #{appointment.id}
    """

    new()
    |> to({customer.name, to_string(customer.email)})
    |> from(@from)
    |> subject("Arrival Time Confirmed - #{service_type.name}")
    |> html_body(Layout.wrap_html(inner_html))
    |> text_body(Layout.wrap_text(inner_text))
  end
```

- [ ] **Step 4: Create the worker** (modeled on `booking_confirmation_worker.ex`)

```elixir
# lib/mobile_car_wash/notifications/email_block_scheduled_worker.ex
defmodule MobileCarWash.Notifications.EmailBlockScheduledWorker do
  @moduledoc """
  Emails the customer their confirmed arrival window after the route optimizer
  assigns a time inside their booked block. Enqueued by `Scheduling.BlockOptimizer`.
  """
  use Oban.Worker, queue: :notifications, max_attempts: 3

  alias MobileCarWash.Scheduling.{Appointment, ServiceType}
  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Fleet.Address
  alias MobileCarWash.Notifications.Email
  alias MobileCarWash.Mailer

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"appointment_id" => appointment_id}}) do
    with {:ok, appointment} <- Ash.get(Appointment, appointment_id, authorize?: false),
         {:ok, service_type} <-
           Ash.get(ServiceType, appointment.service_type_id, authorize?: false),
         {:ok, customer} <- Ash.get(Customer, appointment.customer_id, authorize?: false),
         {:ok, address} <- Ash.get(Address, appointment.address_id, authorize?: false) do
      email = Email.block_scheduled(appointment, service_type, customer, address)

      case Mailer.deliver(email) do
        {:ok, _} ->
          :ok

        {:error, reason} ->
          Logger.error("Email block scheduled failed: #{inspect(reason)}")
          {:error, reason}
      end
    else
      {:error, reason} ->
        Logger.error("Email block scheduled data load failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
```

- [ ] **Step 5: Wire it into the optimizer**

In `block_optimizer.ex:16`, add the worker to the alias:

```elixir
  alias MobileCarWash.Notifications.{
    EmailBlockScheduledWorker,
    PushBlockScheduledWorker,
    SMSBlockScheduledWorker
  }
```

In `enqueue_notifications/1` (`block_optimizer.ex:119-129`), add the email enqueue inside the `Enum.each`:

```elixir
      %{appointment_id: appt.id}
      |> EmailBlockScheduledWorker.new(queue: :notifications)
      |> Oban.insert()
```

- [ ] **Step 6: Run tests to verify they pass**

Run:
```bash
mix test test/mobile_car_wash/notifications/email_block_scheduled_worker_test.exs
mix test test/mobile_car_wash/scheduling/ -k "optimiz"
```
Expected: PASS; optimizer tests still green.

- [ ] **Step 7: Commit**

```bash
git add lib/mobile_car_wash/notifications/email.ex lib/mobile_car_wash/notifications/email_block_scheduled_worker.ex lib/mobile_car_wash/scheduling/block_optimizer.ex test/mobile_car_wash/notifications/email_block_scheduled_worker_test.exs
git commit -m "feat(notifications): email parity for confirmed arrival times"
```

---

## Task 6: Size-aware add-on pricing in `Billing.Pricing`

Add vehicle-size multiplier support to the pure pricing helpers. (Behavior change — base for Task 7.)

**Files:**
- Modify: `lib/mobile_car_wash/billing/pricing.ex:75-83` (`addons_total_cents`, `addon_lines`)
- Test: `test/mobile_car_wash/billing/pricing_test.exs`

**Interfaces:**
- Produces: `Pricing.addons_total_cents/2`, `Pricing.addon_lines/2` (both take
  `(add_ons, vehicle_size)`). Arity-1 versions retained as `size == nil`
  (multiplier 1.0) for backward compatibility.

- [ ] **Step 1: Write the failing test**

```elixir
# in test/mobile_car_wash/billing/pricing_test.exs
  describe "size-aware add-ons" do
    test "addons_total_cents/2 applies the vehicle-size multiplier" do
      add_ons = [%{name: "Wax", price_cents: 1_000}, %{name: "Tires", price_cents: 500}]
      # pickup = 1.5x -> 1500 + 750 = 2250
      assert Pricing.addons_total_cents(add_ons, :pickup) == 2_250
    end

    test "addons_total_cents/2 with nil size is flat" do
      add_ons = [%{name: "Wax", price_cents: 1_000}]
      assert Pricing.addons_total_cents(add_ons, nil) == 1_000
    end

    test "addon_lines/2 sizes each line amount" do
      add_ons = [%{name: "Wax", price_cents: 1_000}]
      assert [%{label: "Wax", amount_cents: 1_200}] = Pricing.addon_lines(add_ons, :suv_van)
    end
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/mobile_car_wash/billing/pricing_test.exs -k "size-aware"`
Expected: FAIL — `addons_total_cents/2` undefined.

- [ ] **Step 3: Implement size-aware helpers**

Replace `addons_total_cents/1` and `addon_lines/1` (pricing.ex:75-83) with:

```elixir
  @doc "Sum of add-on prices in cents, scaled by the vehicle-size multiplier."
  def addons_total_cents(add_ons, vehicle_size \\ nil) do
    Enum.sum(Enum.map(add_ons, &calculate(&1.price_cents, vehicle_size)))
  end

  @doc "Maps add-ons to receipt line items, each scaled by the vehicle-size multiplier."
  def addon_lines(add_ons, vehicle_size \\ nil) do
    Enum.map(add_ons, &%{label: &1.name, amount_cents: calculate(&1.price_cents, vehicle_size)})
  end
```

> `calculate/2` (pricing.ex:22) already does `round(base * Map.get(@multipliers, size, 1.0))`,
> so `nil` size yields the flat amount. The default arg keeps every existing
> arity-1 caller working.

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/mobile_car_wash/billing/pricing_test.exs`
Expected: PASS (new + existing).

- [ ] **Step 5: Commit**

```bash
git add lib/mobile_car_wash/billing/pricing.ex test/mobile_car_wash/billing/pricing_test.exs
git commit -m "feat(pricing): size-aware add-on totals and line items"
```

---

## Task 7: Apply add-on size multiplier in charge + hero (parity)

Wire Task 6's helpers into the server charge path and the live hero so the hero total equals the charged total.

**Files:**
- Modify: `lib/mobile_car_wash/scheduling/booking.ex:66-71` (add-on total), `:687-701` (`create_appointment_add_ons` per-line price)
- Modify: `lib/mobile_car_wash_web/live/booking_live.ex:1636` (hero `addon_lines`)
- Test: `test/mobile_car_wash/scheduling/booking_test.exs`

**Interfaces:**
- Consumes: `Pricing.addons_total_cents/2`, `Pricing.addon_lines/2` (Task 6); `vehicle.size` (bound at booking.ex:56).

- [ ] **Step 1: Write the failing test**

In `test/mobile_car_wash/scheduling/booking_test.exs` (follow its existing fixture style for customer/vehicle/address/service/add-on/block):

```elixir
  test "add-on price scales with vehicle size in the charged total" do
    # Arrange a pickup (1.5x) booking with one $10 add-on on a $50 basic wash.
    # base 5000 * 1.5 = 7500; add-on 1000 * 1.5 = 1500; total 9000.
    %{customer: c, service: s, address: a, block: b} = booking_fixture_pickup()
    {:ok, vehicle} = create_vehicle(c, :pickup)
    add_on = create_add_on(price_cents: 1_000)

    {:ok, %{appointment: appt}} =
      MobileCarWash.Scheduling.Booking.create_booking(%{
        customer_id: c.id,
        service_type_id: s.id,
        vehicle_id: vehicle.id,
        address_id: a.id,
        appointment_block_id: b.id,
        add_on_ids: [add_on.id]
      })

    assert appt.price_cents == 9_000
  end
```

> Reuse existing helpers in `booking_test.exs` for fixtures; the names above are
> illustrative — match the file's actual setup. The asserted number (9000) is the
> contract.

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/mobile_car_wash/scheduling/booking_test.exs -k "scales with vehicle size"`
Expected: FAIL — total is 8000 (flat add-on) not 9000.

- [ ] **Step 3: Size the add-on total in `create_booking`**

In `booking.ex`, change the add-on total line (currently lines 66-68) and pass size into appointment add-ons (line 71):

```elixir
             add_ons = load_add_ons(params[:add_on_ids]),
             price_cents =
               price_cents +
                 MobileCarWash.Billing.Pricing.addons_total_cents(add_ons, vehicle.size),
             {:ok, appointment} <-
               create_appointment(params, service_type, price_cents, discount_cents),
             :ok <- create_appointment_add_ons(appointment, add_ons, vehicle.size),
```

- [ ] **Step 4: Size the persisted per-line price**

Replace `create_appointment_add_ons/2` (booking.ex:687-701) with a size-aware `/3`:

```elixir
  defp create_appointment_add_ons(_appointment, [], _size), do: :ok

  defp create_appointment_add_ons(appointment, add_ons, vehicle_size) do
    Enum.each(add_ons, fn add_on ->
      MobileCarWash.Scheduling.AppointmentAddOn
      |> Ash.Changeset.for_create(:create, %{
        appointment_id: appointment.id,
        add_on_id: add_on.id,
        price_cents: MobileCarWash.Billing.Pricing.calculate(add_on.price_cents, vehicle_size)
      })
      |> Ash.create!()
    end)

    :ok
  end
```

- [ ] **Step 5: Size the hero add-on lines**

In `booking_live.ex:1636` (`compute_price_breakdown/1`), pass the bound `size`:

```elixir
      addon_lines: Pricing.addon_lines(assigns[:selected_add_ons] || [], size),
```

- [ ] **Step 6: Run tests to verify they pass**

Run:
```bash
mix test test/mobile_car_wash/scheduling/booking_test.exs
mix test test/mobile_car_wash_web/live/booking_single_page_test.exs
```
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/mobile_car_wash/scheduling/booking.ex lib/mobile_car_wash_web/live/booking_live.ex test/mobile_car_wash/scheduling/booking_test.exs
git commit -m "feat(booking): apply vehicle-size multiplier to add-ons (charge + hero parity)"
```

---

## Task 8: Vehicle-size pricing test through the LiveView

Lock in that selecting a larger vehicle updates the live hero by the correct multiplier end-to-end.

**Files:**
- Test: `test/mobile_car_wash_web/live/booking_single_page_test.exs`

- [ ] **Step 1: Write the test**

```elixir
  test "selecting a pickup raises the hero total by 50%", %{conn: conn} do
    service = Ash.read!(MobileCarWash.Scheduling.ServiceType) |> hd()
    {:ok, lv, _html} = live(conn, ~p"/book")
    render_click(lv, "select_service", %{"slug" => service.slug})

    # Select/save a pickup vehicle via the manual vehicle form, then assert
    # the hero shows $75.00 (5000 * 1.5). Use the file's existing vehicle-
    # selection helper/flow.
    html = select_pickup_vehicle(lv)

    assert html =~ "$75.00"
  end
```

> Implement `select_pickup_vehicle/1` (or inline the steps) to match the file's
> existing vehicle-form interaction. The contract: a pickup yields a `$75.00`
> hero total for a `$50.00` base wash.

- [ ] **Step 2: Run test to verify it passes** (logic already exists)

Run: `mix test test/mobile_car_wash_web/live/booking_single_page_test.exs -k "pickup raises"`
Expected: PASS. If it FAILS, the assertion exposed a real hero bug — debug before proceeding.

- [ ] **Step 3: Commit**

```bash
git add test/mobile_car_wash_web/live/booking_single_page_test.exs
git commit -m "test(booking): cover vehicle-size multiplier in the live hero"
```

---

## Task 9: Loyalty toggle test

Cover loyalty redemption: a covered basic wash becomes $0 and `Loyalty.redeem` is called at payment time.

**Files:**
- Test: `test/mobile_car_wash/scheduling/booking_test.exs`

**Interfaces:**
- Consumes: `Booking.create_booking/1` with `loyalty_redeem: true`; `apply_loyalty_discount/3` (booking.ex:190) and `maybe_redeem_loyalty/2` (booking.ex:197).

- [ ] **Step 1: Write the test**

```elixir
  test "loyalty redemption zeroes a covered basic wash and consumes a free wash" do
    %{customer: c, service: s, vehicle: v, address: a, block: b} = booking_fixture()
    grant_free_wash(c)  # seed loyalty card with >=1 free wash

    {:ok, %{appointment: appt}} =
      MobileCarWash.Scheduling.Booking.create_booking(%{
        customer_id: c.id,
        service_type_id: s.id,
        vehicle_id: v.id,
        address_id: a.id,
        appointment_block_id: b.id,
        loyalty_redeem: true
      })

    assert appt.price_cents == 0
    refute MobileCarWash.Loyalty.has_free_wash?(c.id)  # or equivalent check
  end
```

> Match the loyalty seeding/inspection helpers to the actual `MobileCarWash.Loyalty`
> API (see `Loyalty.redeem/1`, booking.ex:198). Contract: price 0 + one free wash consumed.

- [ ] **Step 2: Run test to verify it passes**

Run: `mix test test/mobile_car_wash/scheduling/booking_test.exs -k "loyalty redemption"`
Expected: PASS. If FAIL with `:no_loyalty_free_washes`, the seeding step is wrong — fix the fixture, not production code.

- [ ] **Step 3: Commit**

```bash
git add test/mobile_car_wash/scheduling/booking_test.exs
git commit -m "test(booking): cover loyalty redemption to a $0 wash"
```

---

## Task 10: Referral application + mutual-exclusivity test

Cover that a valid referral code discounts the total, and that loyalty + referral are mutually exclusive in the hero.

**Files:**
- Test: `test/mobile_car_wash/scheduling/booking_test.exs` (referral discount)
- Test: `test/mobile_car_wash_web/live/booking_single_page_test.exs` (UI exclusivity)

**Interfaces:**
- Consumes: `maybe_apply_referral/3` (booking.ex:399); `compute_price_breakdown/1` exclusivity (booking_live.ex:1627-1631 — `redeem_loyalty` overrides referral).

- [ ] **Step 1: Write the referral discount test**

```elixir
  test "a valid referral code reduces the charged total" do
    %{customer: c, service: s, vehicle: v, address: a, block: b} = booking_fixture()
    referrer = create_customer_with_referral_code()

    {:ok, %{appointment: appt}} =
      MobileCarWash.Scheduling.Booking.create_booking(%{
        customer_id: c.id,
        service_type_id: s.id,
        vehicle_id: v.id,
        address_id: a.id,
        appointment_block_id: b.id,
        referral_code: referrer.referral_code
      })

    # base 5000 - referral discount (configured reward, default $10 = 1000)
    assert appt.price_cents < 5_000
    assert appt.referral_code_used == referrer.referral_code
  end
```

- [ ] **Step 2: Write the exclusivity test (LiveView)**

```elixir
  test "redeeming loyalty overrides any referral discount in the hero", %{conn: conn} do
    # Drive flow with both a referral applied and loyalty toggled on; assert the
    # hero total equals the loyalty ($0) outcome, not the referral outcome.
    # (compute_price_breakdown: redeem_loyalty branch wins, booking_live.ex:1629)
    ...drive flow per existing helpers...
    assert html =~ "$0.00"
  end
```

> Fill the exclusivity test body with the file's existing flow helpers. Contract:
> with loyalty toggled on, the hero shows the loyalty ($0) total regardless of any
> referral code entered.

- [ ] **Step 3: Run tests to verify they pass**

Run:
```bash
mix test test/mobile_car_wash/scheduling/booking_test.exs -k "referral code reduces"
mix test test/mobile_car_wash_web/live/booking_single_page_test.exs -k "overrides any referral"
```
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add test/mobile_car_wash/scheduling/booking_test.exs test/mobile_car_wash_web/live/booking_single_page_test.exs
git commit -m "test(booking): cover referral discount and loyalty/referral exclusivity"
```

---

## Task 11: Low-stock emphasis on block picker

The picker already shows "{remaining} of {capacity} spots left" (`booking_components.ex:166`). Add urgency styling when remaining is low.

**Files:**
- Modify: `lib/mobile_car_wash_web/live/components/booking_components.ex:166`
- Test: `test/mobile_car_wash_web/live/booking_single_page_test.exs`

**Interfaces:**
- Consumes: `block.capacity`, `block.appointment_count` (already loaded by `BlockAvailability`, block_availability.ex:33).

- [ ] **Step 1: Read the component context**

Read `lib/mobile_car_wash_web/live/components/booking_components.ex:109-175` to see the markup around line 166 and match its class conventions.

- [ ] **Step 2: Write the failing test**

```elixir
  test "a nearly-full block shows a low-stock emphasis", %{conn: conn} do
    service = Ash.read!(MobileCarWash.Scheduling.ServiceType) |> hd()
    block = create_open_block(service)          # capacity 5 (helper in this file)
    fill_block_to(block, 3)                      # leave 2 spots -> "2 of 5 spots left"

    {:ok, lv, _html} = live(conn, ~p"/book")
    render_click(lv, "select_service", %{"slug" => service.slug})
    # navigate to schedule / select the date so the block renders, then:
    html = render(lv)

    assert html =~ "spots left"
    assert html =~ "text-warning"   # urgency class applied at <= 3 remaining
  end
```

> Use the file's existing schedule-navigation helpers; `create_open_block/1`
> exists. Implement `fill_block_to/2` by creating N confirmed appointments in the
> block (or reuse an existing fixture). Contract: low remaining → `text-warning`.

- [ ] **Step 3: Run test to verify it fails**

Run: `mix test test/mobile_car_wash_web/live/booking_single_page_test.exs -k "low-stock"`
Expected: FAIL — no `text-warning` class on the spots-left text.

- [ ] **Step 4: Add the urgency class**

At `booking_components.ex:166`, wrap the spots-left text with conditional emphasis (threshold ≤ 3):

```heex
            <span class={[
              "text-xs",
              if(block.capacity - block.appointment_count <= 3,
                do: "text-warning font-semibold",
                else: "text-base-content/50"
              )
            ]}>
              {block.capacity - block.appointment_count} of {block.capacity} spots left
            </span>
```

> Preserve the existing surrounding markup; only the spots-left node changes. If
> it is already wrapped in a styled element, adjust that element's class list
> instead of adding a new `<span>`.

- [ ] **Step 5: Run test to verify it passes**

Run: `mix test test/mobile_car_wash_web/live/booking_single_page_test.exs -k "low-stock"`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/mobile_car_wash_web/live/components/booking_components.ex test/mobile_car_wash_web/live/booking_single_page_test.exs
git commit -m "feat(booking): emphasize low-stock blocks in the time picker"
```

---

## Task 12: Mobile PaymentIntent path test

Cover the `payment_flow: :mobile` branch of `create_payment_and_checkout` using the existing Stripe payment-intent mock.

**Files:**
- Test: `test/mobile_car_wash/scheduling/booking_test.exs`
- Reference: `config/test.exs:65` (`:stripe_payment_intent_module`), `booking.ex:505-536`.

**Interfaces:**
- Consumes: `Booking.create_booking/1` with `payment_flow: :mobile`; result shape `%{appointment: _, payment_intent_client_secret: secret}`.

- [ ] **Step 1: Confirm the mock shape**

Read the module set at `config/test.exs:65` (`:stripe_payment_intent_module`) to confirm `create/1` (called via `StripeClient.create_payment_intent/3`, booking.ex:520) returns `{:ok, %{id: ..., client_secret: ...}}`.

- [ ] **Step 2: Write the test**

```elixir
  test "mobile payment flow creates a PaymentIntent and returns a client secret" do
    %{customer: c, service: s, vehicle: v, address: a, block: b} = booking_fixture()

    {:ok, result} =
      MobileCarWash.Scheduling.Booking.create_booking(%{
        customer_id: c.id,
        service_type_id: s.id,
        vehicle_id: v.id,
        address_id: a.id,
        appointment_block_id: b.id,
        payment_flow: :mobile
      })

    assert is_binary(result.payment_intent_client_secret)
    refute Map.has_key?(result, :checkout_url)

    payments =
      MobileCarWash.Billing.Payment
      |> Ash.read!(authorize?: false)

    assert Enum.any?(payments, &(&1.appointment_id == result.appointment.id))
  end
```

> Match `booking_fixture/0` to the file's existing setup helpers. If the test
> Stripe payment-intent mock returns `client_secret: nil`, seed/stub it to a
> binary so the assertion is meaningful; otherwise assert the result key exists.

- [ ] **Step 3: Run test to verify it passes**

Run: `mix test test/mobile_car_wash/scheduling/booking_test.exs -k "mobile payment flow"`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add test/mobile_car_wash/scheduling/booking_test.exs
git commit -m "test(booking): cover the mobile PaymentIntent payment path"
```

---

## Final Verification

- [ ] **Run the full precommit gate**

Run: `mix precommit`
Expected: clean compile (no warnings), unused deps removed, formatted, all tests pass.

- [ ] **Manual smoke (optional)**

Boot the dev server and walk the booking flow: an out-of-area ZIP shows the waitlist; a pickup with an add-on shows the sized hero total; a forced geocoder error shows the manual-entry nudge.

---

## Notes on Findings That Were Already Done

Investigation during planning found three items largely implemented; this plan
only extends/tests them rather than building from scratch:

- **Guest email collision** was already rejected with a message
  (`ensure_customer/1`, booking_live.ex:1305-1307) — Task 4 only adds the sign-in
  affordance.
- **Confirmed-time SMS + push** already fire from `BlockOptimizer`
  (block_optimizer.ex:119-129) on both full-block close and the midnight cron —
  Task 5 only adds email parity.
- **"X of Y spots left"** already renders (booking_components.ex:166) — Task 11
  only adds low-stock emphasis.
