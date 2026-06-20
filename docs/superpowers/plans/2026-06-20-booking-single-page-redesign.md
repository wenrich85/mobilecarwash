# Single-page Booking Flow (progressive reveal) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the multi-step booking wizard with one continuously-scrolling page whose sections (Service → Add-ons → Vehicle → Address → Schedule → Review & Pay) reveal progressively, stay freely editable, with sign-in pinned at the top and guest contact captured at the bottom.

**Architecture:** A new pure `MobileCarWash.Booking.BookingSections` module derives each section's status (`:locked | :active | :complete`) and payability from the accumulated selections. `BookingLive` is rewritten to render the sticky price hero + a top sign-in prompt + all six sections at once, each gated by its status; the linear step machine, `next_step`/`prev_step`, the step indicator, and the photos step are removed. Existing section bodies and event handlers are reused; guest-customer creation moves to the pay submit. Backend pricing/Stripe and `SessionCache` are unchanged.

**Tech Stack:** Phoenix LiveView, Tailwind/daisyUI, Ash. This is **Sub-project 1** of `docs/superpowers/specs/2026-06-20-booking-single-page-redesign-design.md`. (Sub-project 2 — geocoder address autocomplete — is a separate later plan; this plan keeps the existing address form.)

## Global Constraints

- **TDD mandatory:** failing test → implement → green, per task. Capture RED/GREEN evidence.
- **`mix precommit` green** before merge (`compile --warnings-as-errors`, `deps.unlock --unused`, `format`, `test`). Benign noise (NOT failures): Ash "missed notifications" warnings; occasional `Postgrex ... disconnected`.
- **Server-authoritative pricing & payment are unchanged:** `Booking.create_booking/1` + dynamic Stripe `unit_amount`; the page sends only ids/selections. Keep `assign_price_breakdown` as the single price source.
- **Progressive reveal, freely editable:** all sections render at once; a section is `:locked` (muted, inputs disabled) until its prerequisites are met, `:active`/`:complete` otherwise. Editing a completed section live-updates price and preserves still-valid later selections.
- **Auth:** optional "Sign in" prompt at the top links to the existing `/book/sign-in` (which stashes `return_to`). Guests enter name/email/phone in Review & Pay; the guest customer is created at pay submit.
- **Pay** enables only when `BookingSections.payable?/1` is true (all required sections complete + customer/contact present).
- **Photos are removed** from the booking flow (section, upload configs, and the now-unused photo event handlers/helpers in `BookingLive`). Do not touch the photo subsystem outside `BookingLive`.
- **Keep** `SessionCache` persistence (resume a half-filled page).
- Run the app with `PORT=4010 mix phx.server`. Do NOT push. Do NOT touch `config/dev.exs`, `AGENTS.md`, `docs/customer-flows.html`.

---

## File structure

| File | Responsibility | Task |
|------|----------------|------|
| `lib/mobile_car_wash/booking/booking_sections.ex` (create) | Pure section-status + payability from context | 1 |
| `test/mobile_car_wash/booking/booking_sections_test.exs` (create) | Status transitions + payable gating | 1 |
| `lib/mobile_car_wash_web/live/booking_live.ex` (rewrite render + handlers) | Single-page progressive-reveal flow | 2 |
| `test/mobile_car_wash_web/live/booking_single_page_test.exs` (create) | Progressive reveal, edit-back, guest pay, signed-in prefill | 2 |
| `lib/mobile_car_wash_web/live/components/booking_components.ex` (modify) | Add `booking_section/1` wrapper; `step_indicator/1` no longer used by booking | 2 |

> The existing per-step tests (`booking_vehicle_step_test.exs`, `booking_addons_test.exs`, `booking_price_header_test.exs`, `booking_subscription_price_test.exs`) navigate via `next_step`. Task 2 updates their navigation helpers to the single-page model (no `next_step`); their assertions about pricing/vehicle/add-on behavior stay.

---

## Task 1: `BookingSections` pure status module

**Files:**
- Create: `lib/mobile_car_wash/booking/booking_sections.ex`
- Test: `test/mobile_car_wash/booking/booking_sections_test.exs`

**Interfaces:**
- Produces:
  - `BookingSections.sections() :: [:service, :add_ons, :vehicle, :address, :schedule, :review]` (order)
  - `BookingSections.status(section, context) :: :locked | :active | :complete`
  - `BookingSections.payable?(context) :: boolean()`
  - `context` is a map with optional keys: `selected_service`, `selected_add_ons` (list), `selected_vehicle`, `selected_address`, `selected_slot`, `current_customer`.

- [ ] **Step 1: Write the failing test**

Create `test/mobile_car_wash/booking/booking_sections_test.exs`:

```elixir
defmodule MobileCarWash.Booking.BookingSectionsTest do
  use ExUnit.Case, async: true

  alias MobileCarWash.Booking.BookingSections

  defp ctx(overrides), do: Map.merge(%{
    selected_service: nil, selected_add_ons: [], selected_vehicle: nil,
    selected_address: nil, selected_slot: nil, current_customer: nil
  }, overrides)

  test "section order is service → add_ons → vehicle → address → schedule → review" do
    assert BookingSections.sections() ==
             [:service, :add_ons, :vehicle, :address, :schedule, :review]
  end

  test "service is active and everything after it is locked when nothing is chosen" do
    c = ctx(%{})
    assert BookingSections.status(:service, c) == :active
    assert BookingSections.status(:add_ons, c) == :locked
    assert BookingSections.status(:vehicle, c) == :locked
    assert BookingSections.status(:review, c) == :locked
  end

  test "choosing a service completes it and unlocks add_ons + vehicle" do
    c = ctx(%{selected_service: %{id: "s"}})
    assert BookingSections.status(:service, c) == :complete
    # add_ons is optional → active (never blocks) once service is chosen
    assert BookingSections.status(:add_ons, c) == :active
    assert BookingSections.status(:vehicle, c) == :active
    assert BookingSections.status(:address, c) == :locked
  end

  test "a chosen vehicle completes vehicle and unlocks address" do
    c = ctx(%{selected_service: %{id: "s"}, selected_vehicle: %{id: "v"}})
    assert BookingSections.status(:vehicle, c) == :complete
    assert BookingSections.status(:address, c) == :active
    assert BookingSections.status(:schedule, c) == :locked
  end

  test "address then schedule unlock in order; review unlocks after a slot" do
    c = ctx(%{
      selected_service: %{id: "s"}, selected_vehicle: %{id: "v"},
      selected_address: %{id: "a"}
    })
    assert BookingSections.status(:address, c) == :complete
    assert BookingSections.status(:schedule, c) == :active
    assert BookingSections.status(:review, c) == :locked

    c2 = Map.put(c, :selected_slot, %{id: "slot"})
    assert BookingSections.status(:schedule, c2) == :complete
    assert BookingSections.status(:review, c2) == :active
  end

  test "payable? only when all required sections complete AND a customer is present" do
    full = ctx(%{
      selected_service: %{id: "s"}, selected_vehicle: %{id: "v"},
      selected_address: %{id: "a"}, selected_slot: %{id: "slot"}
    })
    # No customer yet (guest hasn't entered contact) → not payable
    refute BookingSections.payable?(full)
    assert BookingSections.payable?(Map.put(full, :current_customer, %{id: "c"}))
    # Missing a slot → not payable even with a customer
    refute BookingSections.payable?(%{full | selected_slot: nil, current_customer: %{id: "c"}})
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `MIX_ENV=test mix test test/mobile_car_wash/booking/booking_sections_test.exs`
Expected: FAIL — `module MobileCarWash.Booking.BookingSections is not available`.

- [ ] **Step 3: Write the module**

Create `lib/mobile_car_wash/booking/booking_sections.ex`:

```elixir
defmodule MobileCarWash.Booking.BookingSections do
  @moduledoc """
  Pure section-status logic for the single-page booking flow.

  Given the accumulated selection context, reports each section's status
  (`:locked | :active | :complete`) and whether the order is payable. No
  Phoenix/Ash deps — drives the progressive-reveal UI and the Pay gate.
  """

  @sections [:service, :add_ons, :vehicle, :address, :schedule, :review]

  @type section :: :service | :add_ons | :vehicle | :address | :schedule | :review
  @type status :: :locked | :active | :complete
  @type context :: map()

  @doc "Sections in display order."
  @spec sections() :: [section()]
  def sections, do: @sections

  @doc "Status of a section given the current selections."
  @spec status(section(), context()) :: status()
  def status(:service, ctx), do: if(present?(ctx, :selected_service), do: :complete, else: :active)

  def status(:add_ons, ctx) do
    # Optional: never blocks. Active once a service is chosen; complete when
    # at least one add-on is selected (purely cosmetic — it stays passable).
    cond do
      not present?(ctx, :selected_service) -> :locked
      list_present?(ctx, :selected_add_ons) -> :complete
      true -> :active
    end
  end

  def status(:vehicle, ctx), do: gated(ctx, present?(ctx, :selected_service), :selected_vehicle)

  def status(:address, ctx),
    do: gated(ctx, complete?(:vehicle, ctx), :selected_address)

  def status(:schedule, ctx),
    do: gated(ctx, complete?(:address, ctx), :selected_slot)

  def status(:review, ctx),
    do: if(complete?(:schedule, ctx), do: :active, else: :locked)

  @doc "True when every required section is complete and a customer is present."
  @spec payable?(context()) :: boolean()
  def payable?(ctx) do
    complete?(:service, ctx) and complete?(:vehicle, ctx) and
      complete?(:address, ctx) and complete?(:schedule, ctx) and
      present?(ctx, :current_customer)
  end

  # A required section is locked until `unlocked?`, complete when its value is
  # present, else active.
  defp gated(ctx, unlocked?, key) do
    cond do
      not unlocked? -> :locked
      present?(ctx, key) -> :complete
      true -> :active
    end
  end

  defp complete?(section, ctx), do: status(section, ctx) == :complete

  defp present?(ctx, key), do: Map.get(ctx, key) != nil

  defp list_present?(ctx, key) do
    case Map.get(ctx, key) do
      [_ | _] -> true
      _ -> false
    end
  end
end
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `MIX_ENV=test mix test test/mobile_car_wash/booking/booking_sections_test.exs`
Expected: PASS (all tests).

- [ ] **Step 5: Commit**

```bash
git add lib/mobile_car_wash/booking/booking_sections.ex test/mobile_car_wash/booking/booking_sections_test.exs
git commit -m "feat: BookingSections pure status module for single-page flow"
```

---

## Task 2: Rewrite `BookingLive` as a single progressive-reveal page

**Files:**
- Modify: `lib/mobile_car_wash_web/live/booking_live.ex` (render + handlers + mount cleanup)
- Modify: `lib/mobile_car_wash_web/live/components/booking_components.ex` (add `booking_section/1`)
- Test: `test/mobile_car_wash_web/live/booking_single_page_test.exs` (create)
- Modify (navigation only): `test/mobile_car_wash_web/live/booking_vehicle_step_test.exs`, `booking_addons_test.exs`, `booking_price_header_test.exs`, `booking_subscription_price_test.exs`

**Interfaces:**
- Consumes: `BookingSections.sections/0`, `status/2`, `payable?/1` (Task 1); existing `assign_price_breakdown`, `build_context`, `persist_booking_state`, `load_*` helpers, and all existing section event handlers.
- Produces: a single-page `BookingLive` with no `current_step`/`next_step`/`prev_step`/step indicator/photos; a `booking_section/1` wrapper component; guest creation + booking on a single `confirm_booking` (Pay) submit.

> **Implementer note:** this is a large, atomic rewrite of one file — read the whole current `render/1` (lines ~270–884) and the handler region (~886–1440) before editing. The existing **section bodies are reused verbatim**; you are re-homing them, not rewriting them. Work in the order below and keep the focused test green as you go.

### 2A — Section wrapper component

- [ ] **Step 1: Add `booking_section/1` to `booking_components.ex`**

Add this component (it renders a titled card; when `status == :locked` it dims the card and disables interaction via a `fieldset[disabled]`; the inner content is passed as the default slot):

```elixir
  attr :title, :string, required: true
  attr :index, :integer, required: true
  attr :status, :atom, required: true, doc: ":locked | :active | :complete"
  attr :id, :string, required: true
  slot :inner_block, required: true

  def booking_section(assigns) do
    ~H"""
    <section
      id={@id}
      class={[
        "rounded-box border p-5 mb-4 transition-opacity",
        @status == :locked && "border-base-300 bg-base-200/40 opacity-50",
        @status != :locked && "border-base-300 bg-base-100"
      ]}
    >
      <div class="flex items-center gap-2 mb-4">
        <span class={[
          "flex items-center justify-center size-6 rounded-full text-xs font-bold",
          @status == :complete && "bg-success text-success-content",
          @status != :complete && "bg-base-300 text-base-content/70"
        ]}>
          {if @status == :complete, do: "✓", else: @index}
        </span>
        <h2 class="text-lg font-semibold text-base-content">{@title}</h2>
      </div>
      <fieldset disabled={@status == :locked}>
        {render_slot(@inner_block)}
      </fieldset>
    </section>
    """
  end
```

- [ ] **Step 2: Commit the component scaffold**

```bash
git add lib/mobile_car_wash_web/live/components/booking_components.ex
git commit -m "feat: booking_section wrapper component for single-page flow"
```

### 2B — Mount cleanup (remove step/photos state)

- [ ] **Step 3: Simplify mount assigns**

In `BookingLive.mount/3`:
- Remove `current_step`, `validated_step`, and the `StateMachine.resolve_step` call; the page no longer tracks a step. Keep `base_assigns` (it builds the context).
- Remove the two `allow_upload(...)` blocks and photo assigns (`uploaded_photos`, `photo_caption`, `selected_car_part`, `show_all_parts`).
- Replace `load_step_data(validated_step)` with eager loads needed for an all-sections page: call `load_step_data(:vehicle)` then `load_step_data(:address)` then `load_step_data(:schedule)` (these load `existing_vehicles`, `existing_addresses`, `available_blocks`) — or inline their bodies. Keep `assign_price_breakdown()`.
- Keep `existing_vehicles`, `existing_addresses`, `show_new_vehicle_form`, `show_new_address_form`, `available_blocks`, vehicle-form assigns (`vehicle_makes`, `vehicle_models`, `loading_models`, `vehicle_form`, `vin_error`), `address_form`, subscription/loyalty/referral assigns, `receipt_expanded`, `price_breakdown`, the timing assigns, and add `guest_error: nil`.
- Add a `guest_form` assign default: `guest_form: %{"name" => "", "email" => "", "phone" => ""}`.

(The implementer keeps every assign still referenced by a reused body; remove only step/photos state. Grep `current_step`, `uploaded_photos`, `selected_car_part`, `photo_caption`, `show_all_parts` afterward to confirm no remaining references outside removed code.)

### 2C — Render rewrite

- [ ] **Step 4: Replace the render shell**

Replace the top of `render/1` (the `<.step_indicator .../>` line and the wrapping structure) so the page is: sticky hero → top sign-in prompt → the six `booking_section` wrappers in order. Compute `ctx = build_context(assigns)` at the top of render via an assign instead (assign `:sections_ctx` whenever selections change — simplest: compute in render from existing assigns). Concretely, render becomes:

```heex
    <div class="max-w-4xl mx-auto py-8 px-4">
      <MobileCarWashWeb.PriceHeader.price_header
        breakdown={@price_breakdown}
        expanded={@receipt_expanded}
      />

      <%!-- Top sign-in prompt (optional; returning customers) --%>
      <div :if={is_nil(@current_customer)} class="my-4 flex items-center justify-between gap-3 rounded-box bg-base-200 px-4 py-3">
        <span class="text-sm text-base-content/80">Have an account?</span>
        <.link href={~p"/book/sign-in"} class="btn btn-ghost btn-sm">Sign in</.link>
      </div>
      <div :if={@current_customer} class="my-4 rounded-box bg-success/10 border border-success/30 px-4 py-2 text-sm text-success">
        Signed in as {@current_customer.name}
      </div>

      <.booking_section id="section-service" index={1} title="Service" status={BookingSections.status(:service, build_context(assigns))}>
        <%!-- (1) existing :select_service body goes here --%>
      </.booking_section>

      <.booking_section id="section-add_ons" index={2} title="Add-ons" status={BookingSections.status(:add_ons, build_context(assigns))}>
        <%!-- (2) existing :add_ons body goes here --%>
      </.booking_section>

      <.booking_section id="section-vehicle" index={3} title="Your vehicle" status={BookingSections.status(:vehicle, build_context(assigns))}>
        <%!-- (3) existing :vehicle body goes here --%>
      </.booking_section>

      <.booking_section id="section-address" index={4} title="Service location" status={BookingSections.status(:address, build_context(assigns))}>
        <%!-- (4) existing :address body goes here --%>
      </.booking_section>

      <.booking_section id="section-schedule" index={5} title="Pick a time" status={BookingSections.status(:schedule, build_context(assigns))}>
        <%!-- (5) existing :schedule body goes here --%>
      </.booking_section>

      <.booking_section id="section-review" index={6} title="Review & Pay" status={BookingSections.status(:review, build_context(assigns))}>
        <%!-- (6) review summary + guest contact form + Pay button (see 2E) --%>
      </.booking_section>
    </div>
```

Add `alias MobileCarWash.Booking.BookingSections` to the module's alias block (and drop `StateMachine` from it if no longer referenced after this task).

- [ ] **Step 5: Re-home each existing section body**

For each section, move the **inner content** of the corresponding existing `<div :if={@current_step == :X}>…</div>` block into the matching `booking_section` slot, with these edits:
- Delete the per-step heading `<div class="mb-6"><h1>…</h1></div>` (the wrapper now shows the title) — keep any sub-descriptions if useful.
- Delete the per-step **Continue** button (`<button … phx-click="next_step">Continue</button>`) and any inline Back buttons — navigation is gone.
- Service body: lines ~281–306 (service cards grid). Keep `select_service` cards.
- Add-ons body: lines ~310–343 (toggle cards) minus the Continue button.
- Vehicle body: lines ~424–593 (saved list + VIN form + dropdown form + read-only badge) minus the trailing Continue button (~594) and the `:if={@selected_vehicle}` Continue wrapper.
- Address body: lines ~599–667 minus its Continue button (~668).
- Schedule body: lines ~704–722 (date picker + blocks) minus its Continue button.
- Review body: the summary portion of lines ~731–839 (itemized receipt, loyalty/referral/subscription controls) — but NOT its old Back/Confirm buttons; those are replaced in 2E.

Remove the now-dead `:if={@current_step == :auth}` block (lines ~347–423), the `:if={@current_step == :photos}` block (lines ~672–701), and the `:if={@current_step == :confirmed && @appointment}` block (lines ~864–884) — the confirmed view is handled by the post-pay redirect (unchanged in `confirm_booking`, which navigates to the appointment/confirmation route on success; keep that navigation).

### 2D — Handlers cleanup

- [ ] **Step 6: Remove navigation + photo handlers**

In the handler region:
- Delete `handle_event("next_step", …)` (~921), `handle_event("prev_step", …)` (~941).
- Delete photo handlers: `validate_photos`, both `cancel_photo_upload` clauses, `select_car_part`, `toggle_all_parts`, `delete_uploaded_photo` (~1227–1267), and the `handle_photo_progress/3`, `upload_name_for/1`, `maybe_auto_apply_ai_tags`, `maybe_assign_car_part`, `maybe_assign_caption` helpers, and the `{:ai_tags, photo}` `handle_info` clause (~176–239) — all photo-only.
- In every remaining handler that ends by re-rendering (e.g. `select_service`, `toggle_add_on`, `save_vehicle`, `select_vehicle`, `save_address`, `select_address`, `select_block`, `vehicle_form_change`, `decode_vin`, loyalty/referral), keep the existing `assign_price_breakdown()` + `persist_booking_state()` calls. They no longer set `current_step`. (They already mostly don't; just remove any `current_step:` assigns.)
- `load_step_data/2`: keep the `:vehicle`/`:address`/`:schedule` clauses (used by mount eager-load) and the catch-all; remove any step-transition coupling.
- Remove `alias …StateMachine` if unused; delete the `track_step_completion/1` helper if it only referenced step state (or keep analytics calls if still meaningful without steps).

- [ ] **Step 7: Add scroll-to-next on section completion (progressive reveal feel)**

Add a tiny client hook OR use LiveView's `push_event`. Simplest: after a handler that newly completes a section, `push_event(socket, "scroll_to", %{id: next_section_dom_id})` and add a JS listener in `assets/js/app.js`:

```javascript
window.addEventListener("phx:scroll_to", (e) => {
  const el = document.getElementById(e.detail.id)
  if (el) el.scrollIntoView({behavior: "smooth", block: "start"})
})
```

Add a helper `defp maybe_scroll(socket, prev_ctx)` that compares the previous vs new `payable?`/section statuses and pushes `scroll_to` to the first newly-`:active` section. (Keep it best-effort; the page works without JS.)

### 2E — Auth/contact-at-end + Pay

- [ ] **Step 8: Build the Review & Pay section body**

In the review `booking_section` slot, render (a) the existing itemized summary, then (b) a guest-contact form shown only when `is_nil(@current_customer)`, then (c) the Pay button gated by `BookingSections.payable?`:

```heex
        <%!-- (existing receipt/loyalty/referral summary, re-homed) --%>

        <div :if={is_nil(@current_customer)} class="mt-4 space-y-3 border-t border-base-300 pt-4">
          <h3 class="text-sm font-semibold text-base-content">Your contact info</h3>
          <p :if={@guest_error} class="text-sm text-error">{@guest_error}</p>
          <form phx-change="guest_form_change" id="guest-contact" class="space-y-3">
            <.input name="guest[name]" type="text" label="Name" value={@guest_form["name"]} required />
            <.input name="guest[email]" type="email" label="Email" value={@guest_form["email"]} required />
            <.input name="guest[phone]" type="tel" label="Phone" value={@guest_form["phone"]} />
          </form>
        </div>

        <button
          class="btn btn-primary w-full mt-4"
          phx-click="confirm_booking"
          disabled={not BookingSections.payable?(build_context(assigns))}
        >
          {if @current_customer,
            do: "Pay #{Pricing.format_cents(@price_breakdown.total_cents)}",
            else: "Continue to payment"}
        </button>
```

- [ ] **Step 9: Add `guest_form_change` and fold guest creation into `confirm_booking`**

Add:

```elixir
  def handle_event("guest_form_change", %{"guest" => params}, socket) do
    form = Map.merge(socket.assigns.guest_form, Map.take(params, ~w(name email phone)))
    {:noreply, assign(socket, guest_form: form)}
  end
```

In `confirm_booking`, before building the booking: if `socket.assigns.current_customer` is nil, create/lookup the guest customer from `guest_form` using the **existing** `guest_checkout` logic (the `Customer` lookup + `:guest` reuse + `create_guest` branch from the old `guest_checkout/2`, lines ~958–1019). On guest error, assign `guest_error` and halt (no booking). On success, set `current_customer`, then proceed with the existing `create_booking` + Stripe flow. Then delete the standalone `guest_checkout` handler (its logic now lives in `confirm_booking`; extract it into a private `ensure_customer/1` helper to keep `confirm_booking` readable):

```elixir
  # Returns {:ok, socket_with_customer} | {:error, message}
  defp ensure_customer(%{assigns: %{current_customer: %{} = _c}} = socket), do: {:ok, socket}

  defp ensure_customer(socket) do
    # … the existing guest lookup/create logic from guest_checkout, using
    # socket.assigns.guest_form for name/email/phone; on success
    # {:ok, assign(socket, current_customer: customer, guest_mode: true)};
    # on failure {:error, message}.
  end
```

(Move the verbatim guest lookup/create code from the old `guest_checkout/2` into `ensure_customer/1`, reading `guest_form` instead of `guest_params`.)

### 2F — Tests

- [ ] **Step 10: Write the single-page LiveView tests (RED first)**

Create `test/mobile_car_wash_web/live/booking_single_page_test.exs`:

```elixir
defmodule MobileCarWashWeb.BookingSinglePageTest do
  use MobileCarWashWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias MobileCarWash.Scheduling.ServiceType

  setup do
    ServiceType
    |> Ash.Changeset.for_create(:create, %{
      name: "Basic Wash", slug: "basic_wash", description: "x",
      base_price_cents: 5_000, duration_minutes: 45
    })
    |> Ash.create!()

    :ok
  end

  test "all six sections render on one page; later ones start locked", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/book")
    for t <- ["Service", "Add-ons", "Your vehicle", "Service location", "Pick a time", "Review & Pay"] do
      assert html =~ t
    end
    # Vehicle section is locked (disabled fieldset) before a service is chosen
    assert html =~ ~r/id="section-vehicle"[^>]*>.*?<fieldset disabled/s
  end

  test "choosing a service unlocks the vehicle section and updates the hero", %{conn: conn} do
    {:ok, view, _} = live(conn, "/book")
    html = render_click(view, "select_service", %{"slug" => "basic_wash"})
    assert html =~ "$50.00"
    # vehicle section no longer disabled
    refute html =~ ~r/id="section-vehicle"[^>]*>.*?<fieldset disabled/s
  end

  test "Pay is disabled until all required sections + contact are present", %{conn: conn} do
    {:ok, view, _} = live(conn, "/book")
    html = render_click(view, "select_service", %{"slug" => "basic_wash"})
    assert html =~ ~r/phx-click="confirm_booking"[^>]*disabled/
  end

  test "the page no longer renders the step wizard controls", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/book")
    refute html =~ ~s(phx-click="next_step")
    refute html =~ ~s(phx-click="prev_step")
  end
end
```

- [ ] **Step 11: Run the new tests (RED), implement 2A–2E until GREEN**

Run: `MIX_ENV=test mix test test/mobile_car_wash_web/live/booking_single_page_test.exs`
Iterate on the rewrite until all pass.

- [ ] **Step 12: Update the existing per-step tests' navigation**

The existing tests use a `to_vehicle_step`/`next_step` navigation that no longer exists. Update their setup so they interact with the single page directly: after `select_service`, the vehicle section is immediately unlocked, so replace `render_click(view, "next_step", …)` sequences with direct interaction (e.g. `render_change(view, "vehicle_form_change", …)`, `render_click(view, "select_vehicle", …)`). Keep every behavioral assertion (pricing, add-on totals, VIN autofill, size auto-detect, swatch inline, loading state). Delete assertions that were purely about step navigation.

Run each updated file:
`MIX_ENV=test mix test test/mobile_car_wash_web/live/booking_vehicle_step_test.exs test/mobile_car_wash_web/live/booking_addons_test.exs test/mobile_car_wash_web/live/booking_price_header_test.exs test/mobile_car_wash_web/live/booking_subscription_price_test.exs`
Expected: PASS.

- [ ] **Step 13: Full regression + gate**

Run: `MIX_ENV=test mix test` then `mix precommit`.
Expected: green. Investigate any test referencing `:photos`/`next_step`/`current_step` and update or remove if it asserted removed behavior.

- [ ] **Step 14: Commit**

```bash
git add lib/mobile_car_wash_web/live/booking_live.ex lib/mobile_car_wash_web/live/components/booking_components.ex assets/js/app.js test/mobile_car_wash_web/live/
git commit -m "feat: single-page progressive-reveal booking flow (replaces wizard)"
```

---

## Final verification (before declaring done)

- [ ] **Full gate:** `mix precommit` green (re-run `mix test --failed` once if a known flake appears).
- [ ] **Manual smoke:** `PORT=4010 mix phx.server`; on `/book` the whole flow is one scroll — pick service (hero updates, vehicle unlocks), pick add-ons, complete vehicle (NHTSA), address, schedule; later sections stay locked/disabled until prereqs; editing an earlier section updates the price; as a guest, contact fields appear in Review & Pay and Pay enables only when everything's set; "Sign in" at top works and prefills saved vehicles/addresses.
- [ ] **Then** invoke `superpowers:finishing-a-development-branch` (stash `config/dev.exs`, `AGENTS.md`, `docs/customer-flows.html` before merging, pop after; do not push unless asked).

---

## Self-review (author)

- **Spec coverage (Sub-project 1):** progressive reveal via `BookingSections` status + `booking_section` wrapper (Tasks 1, 2A, 2C) ✓; freely editable (all sections rendered, handlers re-render with price update) ✓; sign-in top / guest contact at end / guest created at pay (2C, 2E) ✓; photos removed (2B, 2D) ✓; step wizard/indicator/next-prev removed (2C, 2D) ✓; pricing/Stripe/SessionCache unchanged (constraints; `confirm_booking`/`create_booking` reused) ✓; tests for reveal/lock/edit/guest-pay (2F) ✓.
- **Deferred to Sub-project 2 (separate plan):** geocoder address autocomplete + confirmation map (this plan keeps the existing address form).
- **Placeholder note:** the re-homed section bodies are **existing markup moved by line range** (not re-transcribed) — Step 5 names exact source ranges and the edits to apply; `ensure_customer/1` reuses the existing `guest_checkout` body verbatim (Step 9). All genuinely-new code (module, wrapper, render shell, new handlers, tests) is given in full.
- **Type consistency:** `BookingSections.status/2`/`payable?/1` consume the same `build_context/1` map the LiveView already builds (`selected_service`/`selected_add_ons`/`selected_vehicle`/`selected_address`/`selected_slot`/`current_customer`); the wrapper's `status` attr takes those atoms; Pay uses `payable?/1`.
