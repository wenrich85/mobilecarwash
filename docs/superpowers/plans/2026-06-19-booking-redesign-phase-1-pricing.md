# Booking Redesign — Phase 1: Live Pricing & Hero Header — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the booking price prominent and live — a pure pricing-breakdown function feeding a reusable hero price header that shows the total (and an itemized receipt) on every step, building up as the customer picks a service, vehicle size, and (later) add-ons.

**Architecture:** A pure `Billing.Pricing.breakdown/1` returns a structured map (base, size delta, add-on lines, discount, total). A stateless `PriceHeader` HTML component renders that map as a hero total with a tap-to-expand receipt and a change delta. `BookingLive` computes the breakdown on every relevant state change, assigns it, and renders the header above all steps. A small colocated JS hook animates the number count-up.

**Tech Stack:** Elixir 1.18 / Phoenix 1.8 LiveView / Ash / Tailwind v4 / colocated JS hooks.

## Global Constraints

- Money is always integer **cents**; format for display only.
- Size multipliers are fixed: **car 1.0×, suv_van 1.2×, pickup 1.5×** (already in `Pricing`).
- All external/third-party calls (later phases) are server-side via `Req`; **CSP/`connect-src` must not change**.
- Phoenix 1.8 rules: components use `use MobileCarWashWeb, :html`; use the imported `<.icon>` for icons; never add inline `<script>` in templates (JS goes in colocated hooks / `app.js`).
- TDD per repo convention; `mix precommit` must be green before the phase is done.
- Add-ons are flat-priced (not size-scaled). Phase 1 only passes add-on lines *through* the breakdown; the add-ons UI/resource is Phase 2.

---

## File Structure

- **Modify** `lib/mobile_car_wash/billing/pricing.ex` — add pure `breakdown/1` + `format_cents/1`.
- **Test** `test/mobile_car_wash/billing/pricing_test.exs` — breakdown cases.
- **Create** `lib/mobile_car_wash_web/components/price_header.ex` — stateless hero component.
- **Test** `test/mobile_car_wash_web/components/price_header_test.exs` — component render.
- **Modify** `lib/mobile_car_wash_web/live/booking_live.ex` — compute/assign `@price_breakdown`, render header on all steps, `toggle_receipt` event, replace inline review calc.
- **Test** `test/mobile_car_wash_web/live/booking_price_header_test.exs` — header shows + updates across steps.
- **Create** `assets/js/hooks/price_count_up.js` + register in `assets/js/app.js` — number animation.

---

### Task 1: Pure pricing breakdown

**Files:**
- Modify: `lib/mobile_car_wash/billing/pricing.ex`
- Test: `test/mobile_car_wash/billing/pricing_test.exs`

**Interfaces:**
- Consumes: existing `Pricing.calculate/2`, `Pricing.size_label/1`.
- Produces:
  - `Pricing.breakdown(input :: map) :: map` where `input` keys are
    `:base_price_cents` (integer, required), `:vehicle_size` (atom | nil),
    `:addon_lines` (list of `%{label: String.t(), amount_cents: integer()}`, default `[]`),
    `:discount_cents` (integer, default `0`).
    Returns `%{base_cents, size_label, size_delta_cents, addon_lines, addons_total_cents, discount_cents, subtotal_cents, total_cents}`.
    `size_label` is `nil` when `vehicle_size` is `nil`; `total_cents` is floored at 0.
  - `Pricing.format_cents(integer) :: String.t()` → e.g. `"$60.00"`.

- [ ] **Step 1: Write the failing tests**

Add to `test/mobile_car_wash/billing/pricing_test.exs` inside the module:

```elixir
  describe "breakdown/1" do
    test "service only (no vehicle yet) has no size delta" do
      b = Pricing.breakdown(%{base_price_cents: 5000})
      assert b.base_cents == 5000
      assert b.size_label == nil
      assert b.size_delta_cents == 0
      assert b.addons_total_cents == 0
      assert b.discount_cents == 0
      assert b.total_cents == 5000
    end

    test "suv adds a 20% size delta on top of base" do
      b = Pricing.breakdown(%{base_price_cents: 5000, vehicle_size: :suv_van})
      assert b.size_label == "SUV / Van"
      assert b.size_delta_cents == 1000
      assert b.total_cents == 6000
    end

    test "add-on lines stack flat and total" do
      b =
        Pricing.breakdown(%{
          base_price_cents: 5000,
          vehicle_size: :suv_van,
          addon_lines: [
            %{label: "Wax & shine", amount_cents: 1500},
            %{label: "Pet hair removal", amount_cents: 1000}
          ]
        })

      assert b.addons_total_cents == 2500
      assert b.subtotal_cents == 8500
      assert b.total_cents == 8500
    end

    test "discount subtracts and floors at zero" do
      b = Pricing.breakdown(%{base_price_cents: 5000, discount_cents: 9000})
      assert b.total_cents == 0
    end

    test "format_cents renders dollars" do
      assert Pricing.format_cents(6000) == "$60.00"
      assert Pricing.format_cents(7550) == "$75.50"
      assert Pricing.format_cents(0) == "$0.00"
    end
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/mobile_car_wash/billing/pricing_test.exs`
Expected: FAIL — `function Pricing.breakdown/1 is undefined` (and `format_cents/1`).

- [ ] **Step 3: Implement breakdown/1 and format_cents/1**

Add to `lib/mobile_car_wash/billing/pricing.ex` before the final `end`:

```elixir
  @doc """
  Pure price breakdown for the live hero header and the persisted total.

  Input keys: `:base_price_cents` (required), `:vehicle_size` (atom | nil),
  `:addon_lines` (list of `%{label, amount_cents}`), `:discount_cents`.
  """
  def breakdown(input) when is_map(input) do
    base = Map.fetch!(input, :base_price_cents)
    size = Map.get(input, :vehicle_size)
    addon_lines = Map.get(input, :addon_lines, [])
    discount = Map.get(input, :discount_cents, 0)

    sized = if size, do: calculate(base, size), else: base
    size_delta = sized - base
    addons_total = Enum.sum(Enum.map(addon_lines, & &1.amount_cents))
    subtotal = sized + addons_total
    total = max(subtotal - discount, 0)

    %{
      base_cents: base,
      size_label: size && size_label(size),
      size_delta_cents: size_delta,
      addon_lines: addon_lines,
      addons_total_cents: addons_total,
      discount_cents: discount,
      subtotal_cents: subtotal,
      total_cents: total
    }
  end

  @doc "Formats integer cents as a dollar string, e.g. 6050 -> \"$60.50\"."
  def format_cents(cents) when is_integer(cents) do
    "$#{:erlang.float_to_binary(cents / 100, decimals: 2)}"
  end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/mobile_car_wash/billing/pricing_test.exs`
Expected: PASS (all breakdown + format_cents tests plus existing `calculate/2` tests).

- [ ] **Step 5: Commit**

```bash
git add lib/mobile_car_wash/billing/pricing.ex test/mobile_car_wash/billing/pricing_test.exs
git commit -m "feat: add pure pricing breakdown + cents formatter"
```

---

### Task 2: PriceHeader component

**Files:**
- Create: `lib/mobile_car_wash_web/components/price_header.ex`
- Test: `test/mobile_car_wash_web/components/price_header_test.exs`

**Interfaces:**
- Consumes: `Pricing.format_cents/1`; the breakdown map from Task 1.
- Produces: `MobileCarWashWeb.PriceHeader.price_header/1` function component.
  Attrs: `:breakdown` (map | nil, default nil), `:expanded` (boolean, default false),
  `:toggle_event` (string, default `"toggle_receipt"`).
  Renders nothing meaningful (a "Select a service" prompt) when `breakdown` is nil;
  otherwise the total, an optional `+$delta` size hint, and (when expanded) the receipt lines.

- [ ] **Step 1: Write the failing test**

Create `test/mobile_car_wash_web/components/price_header_test.exs`:

```elixir
defmodule MobileCarWashWeb.PriceHeaderTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest
  alias MobileCarWashWeb.PriceHeader

  defp render(assigns), do: render_component(&PriceHeader.price_header/1, assigns)

  test "prompts to pick a service when breakdown is nil" do
    html = render(%{breakdown: nil})
    assert html =~ "Select a service"
  end

  test "shows the total prominently" do
    bd = MobileCarWash.Billing.Pricing.breakdown(%{base_price_cents: 5000, vehicle_size: :suv_van})
    html = render(%{breakdown: bd})
    assert html =~ "$60.00"
    assert html =~ "data-cents=\"6000\""
  end

  test "expanded shows itemized receipt lines" do
    bd =
      MobileCarWash.Billing.Pricing.breakdown(%{
        base_price_cents: 5000,
        vehicle_size: :suv_van,
        addon_lines: [%{label: "Wax & shine", amount_cents: 1500}]
      })

    html = render(%{breakdown: bd, expanded: true})
    assert html =~ "Wax &amp; shine"
    assert html =~ "SUV / Van"
    assert html =~ "$75.00"
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `mix test test/mobile_car_wash_web/components/price_header_test.exs`
Expected: FAIL — `module MobileCarWashWeb.PriceHeader is not available`.

- [ ] **Step 3: Implement the component**

Create `lib/mobile_car_wash_web/components/price_header.ex`:

```elixir
defmodule MobileCarWashWeb.PriceHeader do
  @moduledoc """
  Stateless hero price header for the booking wizard. Renders the live
  total prominently with a tap-to-expand itemized receipt. Fed by
  `MobileCarWash.Billing.Pricing.breakdown/1`.
  """
  use MobileCarWashWeb, :html

  alias MobileCarWash.Billing.Pricing

  attr :breakdown, :map, default: nil
  attr :expanded, :boolean, default: false
  attr :toggle_event, :string, default: "toggle_receipt"

  def price_header(assigns) do
    ~H"""
    <div class="sticky top-0 z-30 -mx-4 px-4 pt-3 pb-2 bg-base-100/95 backdrop-blur">
      <div :if={is_nil(@breakdown)} class="rounded-2xl bg-base-200 px-4 py-3 text-center text-sm text-base-content/60">
        Select a service to see your price
      </div>

      <div :if={@breakdown}>
        <button
          type="button"
          phx-click={@toggle_event}
          class="w-full rounded-2xl bg-gradient-to-br from-success to-success/80 text-success-content px-4 py-3 text-center"
        >
          <div
            id="price-hero-total"
            phx-hook="PriceCountUp"
            data-cents={@breakdown.total_cents}
            class="text-3xl font-extrabold leading-none"
          >
            {Pricing.format_cents(@breakdown.total_cents)}
          </div>
          <div :if={@breakdown.size_delta_cents > 0} class="text-xs opacity-90 mt-1">
            ▲ +{Pricing.format_cents(@breakdown.size_delta_cents)} {@breakdown.size_label}
          </div>
          <div class="text-[11px] opacity-80 mt-1">
            <.icon name="hero-receipt-percent" class="size-3" />
            {if @expanded, do: "Hide breakdown", else: "Tap for breakdown"}
          </div>
        </button>

        <div :if={@expanded} class="mt-2 rounded-xl border border-base-300 bg-base-100 px-4 py-3 text-sm">
          <.line label="Base" amount={@breakdown.base_cents} />
          <.line :if={@breakdown.size_label} label={@breakdown.size_label} amount={@breakdown.size_delta_cents} />
          <.line :for={l <- @breakdown.addon_lines} label={l.label} amount={l.amount_cents} />
          <.line :if={@breakdown.discount_cents > 0} label="Discount" amount={-@breakdown.discount_cents} />
          <div class="flex justify-between font-extrabold text-success border-t border-base-300 mt-2 pt-2">
            <span>Total</span>
            <span>{Pricing.format_cents(@breakdown.total_cents)}</span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :amount, :integer, required: true

  defp line(assigns) do
    ~H"""
    <div class="flex justify-between py-0.5 text-base-content/80">
      <span>{@label}</span>
      <span>{format_signed(@amount)}</span>
    </div>
    """
  end

  defp format_signed(amount) when amount < 0, do: "−" <> Pricing.format_cents(-amount)
  defp format_signed(amount), do: Pricing.format_cents(amount)
end
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `mix test test/mobile_car_wash_web/components/price_header_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/mobile_car_wash_web/components/price_header.ex test/mobile_car_wash_web/components/price_header_test.exs
git commit -m "feat: add PriceHeader hero component"
```

---

### Task 3: Wire the hero into BookingLive on every step

**Files:**
- Modify: `lib/mobile_car_wash_web/live/booking_live.ex`
- Test: `test/mobile_car_wash_web/live/booking_price_header_test.exs`

**Interfaces:**
- Consumes: `Pricing.breakdown/1`, `MobileCarWashWeb.PriceHeader.price_header/1`.
- Produces: socket assigns `:price_breakdown` (map | nil) and `:receipt_expanded` (boolean);
  a `"toggle_receipt"` event handler; a private `assign_price_breakdown/1` recomputed
  wherever `selected_service`, `selected_vehicle`, `redeem_loyalty`, `referral_discount`,
  or `active_subscription` change.

- [ ] **Step 1: Write the failing test**

Create `test/mobile_car_wash_web/live/booking_price_header_test.exs`:

```elixir
defmodule MobileCarWashWeb.BookingPriceHeaderTest do
  use MobileCarWashWeb.ConnCase, async: true
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

  test "hero shows base price once a service is selected", %{conn: conn} do
    {:ok, view, html} = live(conn, "/book")
    # Before selecting: prompt to pick a service.
    assert html =~ "Select a service to see your price"

    html = render_click(view, "select_service", %{"slug" => "basic_wash"})
    assert html =~ "$50.00"
  end

  test "tapping the hero toggles the itemized receipt", %{conn: conn} do
    {:ok, view, _} = live(conn, "/book")
    render_click(view, "select_service", %{"slug" => "basic_wash"})

    html = render_click(view, "toggle_receipt", %{})
    assert html =~ "Total"
    assert html =~ "Base"
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `mix test test/mobile_car_wash_web/live/booking_price_header_test.exs`
Expected: FAIL — assertion on `"Select a service to see your price"` / `"$50.00"` not found (header not rendered yet).

- [ ] **Step 3: Add price assigns + helper + toggle handler**

In `lib/mobile_car_wash_web/live/booking_live.ex`, add an alias near the top aliases:

```elixir
  alias MobileCarWash.Billing.Pricing
```

Add the toggle handler near the other `handle_event/3` clauses (e.g. after `clear_referral`):

```elixir
  def handle_event("toggle_receipt", _params, socket) do
    {:noreply, assign(socket, receipt_expanded: !socket.assigns.receipt_expanded)}
  end
```

Add these private helpers (near the bottom, with the other private fns):

```elixir
  defp assign_price_breakdown(socket) do
    assign(socket, price_breakdown: compute_price_breakdown(socket.assigns))
  end

  defp compute_price_breakdown(%{selected_service: nil}), do: nil

  defp compute_price_breakdown(assigns) do
    base = assigns.selected_service.base_price_cents
    size = assigns.selected_vehicle && assigns.selected_vehicle.size

    sized =
      if size, do: Pricing.calculate(base, size), else: base

    discount =
      cond do
        assigns[:redeem_loyalty] -> sized
        true -> assigns[:referral_discount] || 0
      end

    Pricing.breakdown(%{
      base_price_cents: base,
      vehicle_size: size,
      addon_lines: [],
      discount_cents: discount
    })
  end
```

- [ ] **Step 4: Initialize assigns and recompute on changes**

In `mount/3`, where the socket assigns are set (the big `assign(...)` with `referral_discount: 0` etc.), add:

```elixir
      receipt_expanded: false,
      price_breakdown: nil,
```

Then ensure the breakdown is recomputed after the relevant events. At the end of each of these handlers, pipe the socket through `assign_price_breakdown/1` before returning `{:noreply, socket}`:
- `"select_service"`
- `"select_vehicle"` and `"save_vehicle"`
- `"toggle_loyalty"`
- `"apply_referral"` and `"clear_referral"`

Example for `select_service` (apply the same `|> assign_price_breakdown()` pattern to each listed handler):

```elixir
  def handle_event("select_service", %{"slug" => slug}, socket) do
    service = Enum.find(socket.assigns.services, &(&1.slug == slug))

    socket =
      socket
      |> assign(selected_service: service)
      |> assign_price_breakdown()

    {:noreply, socket}
  end
```

(Adapt to the existing body of each handler — only add the `|> assign_price_breakdown()` step; do not remove existing logic.)

- [ ] **Step 5: Render the hero on every step**

In `render/1`, immediately inside the wizard container (above the per-step `<div :if={@current_step == ...}>` blocks), add:

```heex
<MobileCarWashWeb.PriceHeader.price_header
  breakdown={@price_breakdown}
  expanded={@receipt_expanded}
/>
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `mix test test/mobile_car_wash_web/live/booking_price_header_test.exs`
Expected: PASS.

- [ ] **Step 7: Replace the inline review-step price calc with the breakdown**

In the `:review` step template (around the current `<% base_price = Pricing.calculate(...) %>` block), use `@price_breakdown.total_cents` for the displayed total and the Confirm button label instead of recomputing inline. Keep the existing `confirm_booking` payload working by mapping `price_cents`/`discount_cents` from `@price_breakdown` (`total_cents` and `discount_cents`). Show the total via `Pricing.format_cents(@price_breakdown.total_cents)`.

- [ ] **Step 8: Run the full booking test suites**

Run: `mix test test/mobile_car_wash_web/live/ test/features/customer_booking_test.exs`
Expected: PASS (no regressions in existing booking tests).

- [ ] **Step 9: Commit**

```bash
git add lib/mobile_car_wash_web/live/booking_live.ex test/mobile_car_wash_web/live/booking_price_header_test.exs
git commit -m "feat: render live hero price across booking steps"
```

---

### Task 4: Count-up animation hook (polish)

**Files:**
- Create: `assets/js/hooks/price_count_up.js`
- Modify: `assets/js/app.js`

**Interfaces:**
- Consumes: the `#price-hero-total` element with `phx-hook="PriceCountUp"` and
  `data-cents` (rendered in Task 2).
- Produces: a `PriceCountUp` hook registered in the LiveSocket `hooks` map.

- [ ] **Step 1: Create the hook**

Create `assets/js/hooks/price_count_up.js`:

```javascript
// Animates the hero price number when data-cents changes.
export const PriceCountUp = {
  mounted() { this.current = this.target(); this.paint(this.current); },
  updated() { this.animate(this.current ?? this.target(), this.target()); },
  target() { return parseInt(this.el.dataset.cents || "0", 10); },
  paint(c) { this.el.textContent = "$" + (c / 100).toFixed(2); },
  animate(from, to) {
    const start = performance.now(), dur = 320;
    const tick = (now) => {
      const t = Math.min((now - start) / dur, 1);
      const v = Math.round(from + (to - from) * t);
      this.paint(v);
      if (t < 1) requestAnimationFrame(tick);
      else this.current = to;
    };
    requestAnimationFrame(tick);
  },
};
```

- [ ] **Step 2: Register the hook in app.js**

In `assets/js/app.js`, add the import near the other imports:

```javascript
import {PriceCountUp} from "./hooks/price_count_up.js"
```

And add it to the hooks map (the existing `hooks: {...colocatedHooks, Sortable, DispatchMap, ClipboardCopy}` line):

```javascript
  hooks: {...colocatedHooks, Sortable, DispatchMap, ClipboardCopy, PriceCountUp},
```

- [ ] **Step 3: Verify build + manual check**

Run: `mix assets.build`
Expected: builds with no errors.

Then manually: start the server (`PORT=4010 mix phx.server`), open `/book`, select a service and (later) change vehicle size — the hero number animates from the old value to the new one.

- [ ] **Step 4: Run precommit**

Run: `mix precommit`
Expected: PASS (compile clean, formatted, full suite green).

- [ ] **Step 5: Commit**

```bash
git add assets/js/hooks/price_count_up.js assets/js/app.js
git commit -m "feat: animate hero price count-up"
```

---

## Self-Review

- **Spec coverage (Phase 1 scope):** prominent live price ✓ (Tasks 2–3), builds with size ✓ (breakdown + recompute on vehicle), itemized receipt ✓ (Task 2 expanded), pass-through for add-on lines ✓ (breakdown accepts `addon_lines` for Phase 2), pricing as single source ✓ (review uses breakdown, Task 3 Step 7). Add-ons UI/resource, NHTSA, geocoder = later phases (out of scope here).
- **Placeholders:** none — all steps include concrete code or exact edit instructions. Task 3 Steps 4/5/7 are integration edits described against named anchors in the existing file (handlers + review block) since the surrounding body is large; the code to add is given verbatim.
- **Type consistency:** `breakdown/1` keys used by `PriceHeader` (`total_cents`, `size_delta_cents`, `size_label`, `addon_lines` with `%{label, amount_cents}`, `discount_cents`, `base_cents`) match Task 1's return map and Task 3's construction. `format_cents/1` used consistently. Hook reads `data-cents` rendered by the component.

## Notes for later phases (not part of this plan)

- Phase 2 feeds real `addon_lines` from the new `AddOn` step into `compute_price_breakdown/1`.
- Phase 1 keeps the existing discount logic (referral/loyalty) as-is; subscription discount refinement can fold into `compute_price_breakdown/1` later without changing `breakdown/1`.
