# Phase-1, Plan 3b-1 — Booking Components Refresh + Simple Step Templates

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refresh all 6 components in `MobileCarWashWeb.BookingComponents` to use Plan 1's design tokens, replace the daisyUI step indicator with a progress bar pattern, and rewrite 3 simple step templates (`:select_service`, `:schedule`, `:confirmed`) in `booking_live.ex`.

**Architecture:** Each component refreshed individually via TDD (test the new markup, then update the implementation). Component public APIs preserved. State machine + event handlers untouched. The 5 sub-flow-heavy step templates stay un-refreshed — they belong to Plans 3b-2 and 3b-3.

**Tech Stack:** Phoenix LiveView, Tailwind v4 + daisyUI, Phoenix.Component, ExUnit, `Phoenix.LiveViewTest.rendered_to_string/1` for component testing.

**Spec reference:** [docs/superpowers/specs/2026-04-27-plan3b1-booking-components-simple-steps-design.md](docs/superpowers/specs/2026-04-27-plan3b1-booking-components-simple-steps-design.md)

**File map:**

- Modify: `lib/mobile_car_wash_web/live/components/booking_components.ex` — refresh all 6 components in place
- Modify: `lib/mobile_car_wash_web/live/booking_live.ex` — rewrite `:select_service`, `:schedule`, `:confirmed` step templates
- New: `test/mobile_car_wash_web/live/components/booking_components_test.exs` — ~10-12 tests
- Modify (if existing tests break): `test/mobile_car_wash_web/live/booking_live_test.exs` and any sibling files asserting on old markup

**Out of scope (deferred):**

- `:auth` / `:vehicle` / `:address` step rewrites → **Plan 3b-2**
- `:photos` / `:review` step rewrites → **Plan 3b-3**
- Mobile sticky CTA → 3b-2 or 3b-3
- Stripe Elements styling → 3b-3
- Standalone `/book/success` page → **Plan 3c**
- BookingStateMachine logic changes (never)
- Event handler changes (never)

---

## Task 0: Pre-flight verification

**Files:** none modified — read-only.

- [ ] **Step 1: Verify clean tree on right branch + Plan 3a baseline green**

```bash
git status && git branch --show-current && mix test 2>&1 | tail -3
```
Expected: clean working tree; branch is `main` or a Plan 3b-1 feature branch; ≥1039 tests passing.

- [ ] **Step 2: Note baseline test count for final-checkpoint comparison**

Record the count from Step 1.

- [ ] **Step 3: Find existing `mount/3` assigns in booking_live.ex**

Run: `grep -A 50 'def mount' lib/mobile_car_wash_web/live/booking_live.ex | head -60`

Note which assign holds the user's selected service. Likely `:selected_service`. If it's named differently (e.g., `:service_slug`), adapt the `:select_service` step template in Task 8 accordingly.

- [ ] **Step 4: Find which test files touch booking page or its components**

Run: `grep -lE '(booking|service_card|step.*indicator|block_window_picker|confirmation_card)' test/mobile_car_wash_web/ --include='*.exs' -r 2>/dev/null`

Note the list — these may need assertion updates in Task 11.

---

## Task 1: Refresh `step_indicator/1` (TDD)

**Files:**
- Modify: `lib/mobile_car_wash_web/live/components/booking_components.ex` (`step_indicator/1`, lines 10-28)
- Create: `test/mobile_car_wash_web/live/components/booking_components_test.exs`

- [ ] **Step 1: Write failing test**

Create `test/mobile_car_wash_web/live/components/booking_components_test.exs`:

```elixir
defmodule MobileCarWashWeb.BookingComponentsTest do
  use ExUnit.Case, async: true
  import Phoenix.Component
  import Phoenix.LiveViewTest
  import MobileCarWashWeb.BookingComponents

  describe "step_indicator/1" do
    test "renders progress bar with current step number, label, and percent" do
      assigns = %{}
      html = rendered_to_string(~H|<.step_indicator current_step={:vehicle} />|)

      # Step 3 of 8 (vehicle is index 2 → step number 3)
      assert html =~ "Step 3 of 8"
      assert html =~ "Vehicle"
      # 3/8 = 37.5% → rounds to 38%
      assert html =~ "38%"
      # Progress bar fill width
      assert html =~ "width: 38%"
    end

    test "shows next step hint when not on last step" do
      assigns = %{}
      html = rendered_to_string(~H|<.step_indicator current_step={:vehicle} />|)
      assert html =~ "Next: Address"
    end

    test "omits next step hint on last step" do
      assigns = %{}
      html = rendered_to_string(~H|<.step_indicator current_step={:confirmed} />|)
      refute html =~ "Next:"
    end
  end
end
```

- [ ] **Step 2: Run test, verify failure**

Run: `mix test test/mobile_car_wash_web/live/components/booking_components_test.exs --only describe:step_indicator`
Expected: failures — old markup doesn't say "Step 3 of 8".

- [ ] **Step 3: Replace `step_indicator/1` body**

In `lib/mobile_car_wash_web/live/components/booking_components.ex`, replace the entire `step_indicator/1` function (lines 10-28 + the `attr :current_step` line above it) with:

```elixir
  attr :current_step, :atom, required: true

  def step_indicator(assigns) do
    labels = step_labels()
    steps = @steps
    current_index = Enum.find_index(steps, &(&1 == assigns.current_step)) || 0
    step_number = current_index + 1
    total_steps = length(steps)
    progress_percent = round(step_number / total_steps * 100)
    current_label = Keyword.get(labels, assigns.current_step, "")

    next_label =
      case Enum.at(steps, current_index + 1) do
        nil -> nil
        next -> Keyword.get(labels, next)
      end

    assigns =
      assign(assigns,
        step_number: step_number,
        total_steps: total_steps,
        progress_percent: progress_percent,
        current_label: current_label,
        next_label: next_label
      )

    ~H"""
    <div class="mb-8">
      <div class="flex items-baseline justify-between mb-2">
        <div class="text-sm font-semibold text-base-content">
          Step {@step_number} of {@total_steps} — {@current_label}
        </div>
        <div class="text-xs text-base-content/60">{@progress_percent}% complete</div>
      </div>
      <div class="h-1.5 bg-base-200 rounded-full overflow-hidden">
        <div
          class="h-full bg-cyan-500 rounded-full transition-all"
          style={"width: #{@progress_percent}%"}
        />
      </div>
      <div :if={@next_label} class="text-xs text-base-content/60 mt-1.5">
        Next: {@next_label}
      </div>
    </div>
    """
  end
```

Also change `step_labels/0` to return a Keyword list (it currently returns a list of tuples — same shape, but `Keyword.get/2` lookup is cleaner). The existing definition already returns `[{:select_service, "Service"}, ...]` which IS a keyword list. No change needed.

You can also delete the old `defp step_class/2` private helper since it's no longer used. Verify by grep before deleting:

Run: `grep step_class lib/mobile_car_wash_web/live/components/booking_components.ex`
If only the `defp step_class` definition matches (no callers), delete it.

- [ ] **Step 4: Run tests, verify pass**

Run: `mix test test/mobile_car_wash_web/live/components/booking_components_test.exs`
Expected: 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/mobile_car_wash_web/live/components/booking_components.ex test/mobile_car_wash_web/live/components/booking_components_test.exs
git commit -m "booking: replace step_indicator daisyUI steps with progress-bar pattern"
```

---

## Task 2: Refresh `service_card/1` (TDD)

**Files:**
- Modify: `lib/mobile_car_wash_web/live/components/booking_components.ex` (`service_card/1`, lines 53-77)
- Modify: `test/mobile_car_wash_web/live/components/booking_components_test.exs`

- [ ] **Step 1: Append failing tests**

Append to test file (before module's closing `end`):

```elixir
  describe "service_card/1" do
    setup do
      service = %{
        slug: "basic_wash",
        name: "Basic Wash",
        description: "Exterior hand wash and quick interior",
        base_price_cents: 5000,
        duration_minutes: 45
      }
      %{service: service}
    end

    test "renders selected state with cyan border and check badge", %{service: service} do
      assigns = %{service: service}
      html = rendered_to_string(~H|<.service_card service={@service} selected={true} />|)
      assert html =~ "border-cyan-500"
      # Check badge — look for the inline svg or the heroicon class
      assert html =~ "✓" or html =~ "hero-check"
    end

    test "unselected state has no check badge", %{service: service} do
      assigns = %{service: service}
      html = rendered_to_string(~H|<.service_card service={@service} selected={false} />|)
      refute html =~ "border-cyan-500"
    end

    test "click emits select_service event with slug", %{service: service} do
      assigns = %{service: service}
      html = rendered_to_string(~H|<.service_card service={@service} />|)
      assert html =~ ~s(phx-click="select_service")
      assert html =~ ~s(phx-value-slug="basic_wash")
    end

    test "renders price in mono font with dollar amount", %{service: service} do
      assigns = %{service: service}
      html = rendered_to_string(~H|<.service_card service={@service} />|)
      assert html =~ "$50"
      assert html =~ "font-mono"
    end
  end
```

- [ ] **Step 2: Run tests, verify failure**

Run: `mix test test/mobile_car_wash_web/live/components/booking_components_test.exs --only describe:service_card`
Expected: failures on `border-cyan-500` and `font-mono`.

- [ ] **Step 3: Replace `service_card/1`**

In `booking_components.ex`, replace the existing `service_card/1` function (look for `def service_card`) with:

```elixir
  attr :service, :map, required: true
  attr :selected, :boolean, default: false

  def service_card(assigns) do
    ~H"""
    <div
      class={[
        "relative bg-base-100 rounded-box p-5 cursor-pointer transition-shadow hover:shadow-md",
        if(@selected, do: "border-2 border-cyan-500", else: "border border-base-300")
      ]}
      phx-click="select_service"
      phx-value-slug={@service.slug}
    >
      <div
        :if={@selected}
        class="absolute top-3 right-3 w-6 h-6 bg-cyan-500 text-white rounded-full flex items-center justify-center text-sm font-bold"
      >
        ✓
      </div>
      <div class="text-xs font-semibold uppercase tracking-wide text-base-content/60 mb-1">
        {@service.name}
      </div>
      <div class="font-mono text-3xl font-bold text-base-content tabular-nums">
        ${div(@service.base_price_cents, 100)}
      </div>
      <div class="text-xs text-base-content/60 mt-0.5 mb-3">
        {@service.duration_minutes} min
      </div>
      <p class="text-sm text-base-content/80">{@service.description}</p>
    </div>
    """
  end
```

- [ ] **Step 4: Run tests**

Run: `mix test test/mobile_car_wash_web/live/components/booking_components_test.exs`
Expected: 7 tests pass (3 step_indicator + 4 service_card).

- [ ] **Step 5: Commit**

```bash
git add lib/mobile_car_wash_web/live/components/booking_components.ex test/mobile_car_wash_web/live/components/booking_components_test.exs
git commit -m "booking: refresh service_card as selectable (cyan ring + check badge)"
```

---

## Task 3: Refresh `block_window_picker/1` with date strip (TDD)

**Files:**
- Modify: `lib/mobile_car_wash_web/live/components/booking_components.ex` (`block_window_picker/1`, lines 79-132)
- Modify: `test/mobile_car_wash_web/live/components/booking_components_test.exs`

This is the biggest component refresh — replaces the date input with a horizontal date strip and adds a new optional `:available_dates` attr.

- [ ] **Step 1: Append failing tests**

Append:

```elixir
  describe "block_window_picker/1" do
    test "renders 7 date chips when available_dates not provided" do
      assigns = %{date: Date.utc_today(), blocks: [], selected_block: nil}

      html =
        rendered_to_string(
          ~H|<.block_window_picker date={@date} blocks={@blocks} selected_block={@selected_block} />|
        )

      # Should show 7 date chips
      today = Date.utc_today()
      assert html =~ "#{today.day}"
      future = Date.add(today, 6)
      assert html =~ "#{future.day}"
    end

    test "highlights selected date chip with cyan" do
      today = Date.utc_today()
      assigns = %{date: today, blocks: [], selected_block: nil}

      html =
        rendered_to_string(
          ~H|<.block_window_picker date={@date} blocks={@blocks} selected_block={@selected_block} />|
        )

      # The today chip should have cyan styling (because @date matches it)
      assert html =~ "bg-cyan-500"
    end

    test "renders blocks list when provided" do
      block = %{
        id: "block-1",
        starts_at: ~U[2026-04-30 09:00:00Z],
        ends_at: ~U[2026-04-30 11:00:00Z],
        capacity: 3,
        appointment_count: 1
      }

      assigns = %{date: ~D[2026-04-30], blocks: [block], selected_block: nil}

      html =
        rendered_to_string(
          ~H|<.block_window_picker date={@date} blocks={@blocks} selected_block={@selected_block} />|
        )

      assert html =~ "9:00"
      assert html =~ "11:00"
      assert html =~ "2 of 3 spots left"
    end

    test "selected block has cyan-500 background" do
      block = %{
        id: "block-1",
        starts_at: ~U[2026-04-30 09:00:00Z],
        ends_at: ~U[2026-04-30 11:00:00Z],
        capacity: 3,
        appointment_count: 1
      }

      assigns = %{date: ~D[2026-04-30], blocks: [block], selected_block: block}

      html =
        rendered_to_string(
          ~H|<.block_window_picker date={@date} blocks={@blocks} selected_block={@selected_block} />|
        )

      assert html =~ "bg-cyan-500"
    end

    test "shows warning when blocks empty for selected date" do
      assigns = %{date: ~D[2026-04-30], blocks: [], selected_block: nil}

      html =
        rendered_to_string(
          ~H|<.block_window_picker date={@date} blocks={@blocks} selected_block={@selected_block} />|
        )

      assert html =~ "No available windows"
    end
  end
```

- [ ] **Step 2: Run tests, verify failure**

Run: `mix test test/mobile_car_wash_web/live/components/booking_components_test.exs --only describe:block_window_picker`
Expected: failures (date chips not rendered, etc.).

- [ ] **Step 3: Replace `block_window_picker/1`**

Replace the existing `block_window_picker/1` function in `booking_components.ex` with:

```elixir
  attr :date, :any, required: true
  attr :blocks, :list, required: true
  attr :selected_block, :any, default: nil
  attr :available_dates, :list, default: nil

  def block_window_picker(assigns) do
    available_dates =
      assigns.available_dates ||
        Enum.map(0..6, fn offset -> Date.add(Date.utc_today(), offset) end)

    assigns = assign(assigns, available_dates: available_dates)

    ~H"""
    <div>
      <%!-- Date strip --%>
      <div class="mb-6">
        <div class="text-sm font-semibold text-base-content mb-2">Pick a date</div>
        <div class="flex gap-2 overflow-x-auto pb-2">
          <button
            :for={d <- @available_dates}
            type="button"
            class={[
              "flex flex-col items-center justify-center w-14 h-14 shrink-0 rounded-lg border transition-colors",
              if(date_match?(@date, d),
                do: "bg-cyan-500 text-white border-cyan-500",
                else: "bg-base-100 border-base-300 text-base-content hover:border-cyan-500"
              )
            ]}
            phx-click="select_date"
            phx-value-date={Date.to_string(d)}
          >
            <div class="text-[10px] font-semibold uppercase tracking-wide opacity-80">
              {Calendar.strftime(d, "%a")}
            </div>
            <div class="text-lg font-bold leading-none">{d.day}</div>
          </button>
        </div>
      </div>

      <%!-- Blocks list --%>
      <div :if={@blocks != []} class="space-y-2">
        <p class="text-sm text-base-content/70 mb-2">
          Pick a window. We'll confirm your exact arrival time by midnight the day before.
        </p>
        <button
          :for={block <- @blocks}
          type="button"
          class={[
            "w-full flex items-center justify-between px-4 py-3 rounded-lg border transition-colors",
            if(@selected_block && @selected_block.id == block.id,
              do: "bg-cyan-500 text-white border-cyan-500",
              else: "bg-base-100 border-base-300 hover:border-cyan-500"
            )
          ]}
          phx-click="select_block"
          phx-value-id={block.id}
        >
          <span class="font-semibold">
            {Calendar.strftime(block.starts_at, "%I:%M %p")} – {Calendar.strftime(
              block.ends_at,
              "%I:%M %p"
            )}
          </span>
          <span class="text-xs opacity-75">
            {block.capacity - block.appointment_count} of {block.capacity} spots left
          </span>
        </button>
      </div>

      <div :if={@date && @blocks == []} class="alert alert-warning mt-4">
        <span>No available windows for this date. Please try another day.</span>
      </div>
    </div>
    """
  end

  # Date matching helper — handles both Date and string forms
  defp date_match?(nil, _), do: false
  defp date_match?(%Date{} = a, %Date{} = b), do: Date.compare(a, b) == :eq

  defp date_match?(a, %Date{} = b) when is_binary(a) do
    case Date.from_iso8601(a) do
      {:ok, parsed} -> Date.compare(parsed, b) == :eq
      _ -> false
    end
  end

  defp date_match?(_, _), do: false
```

- [ ] **Step 4: Run tests**

Run: `mix test test/mobile_car_wash_web/live/components/booking_components_test.exs`
Expected: 12 tests pass (3 step_indicator + 4 service_card + 5 block_window_picker).

- [ ] **Step 5: Commit**

```bash
git add lib/mobile_car_wash_web/live/components/booking_components.ex test/mobile_car_wash_web/live/components/booking_components_test.exs
git commit -m "booking: replace block_window_picker date input with horizontal date strip"
```

---

## Task 4: Refresh `time_slot_picker/1` (TDD)

**Files:**
- Modify: `lib/mobile_car_wash_web/live/components/booking_components.ex` (`time_slot_picker/1`, lines 138-176)
- Modify: `test/mobile_car_wash_web/live/components/booking_components_test.exs`

- [ ] **Step 1: Append failing test**

Append:

```elixir
  describe "time_slot_picker/1" do
    test "renders slots and highlights selected" do
      slot1 = %{starts_at: ~U[2026-04-30 09:00:00Z]}
      slot2 = %{starts_at: ~U[2026-04-30 10:00:00Z]}

      assigns = %{
        date: ~D[2026-04-30],
        slots: [slot1, slot2],
        selected_slot: slot1.starts_at
      }

      html =
        rendered_to_string(
          ~H|<.time_slot_picker date={@date} slots={@slots} selected_slot={@selected_slot} />|
        )

      assert html =~ "9:00"
      assert html =~ "10:00"
      assert html =~ "bg-cyan-500"
    end
  end
```

- [ ] **Step 2: Run, verify failure (or pass — depends on existing markup)**

Run: `mix test test/mobile_car_wash_web/live/components/booking_components_test.exs --only describe:time_slot_picker`

The existing `time_slot_picker` uses `btn-primary` for selected which compiles to a colored class but probably not `bg-cyan-500` directly. Test will fail.

- [ ] **Step 3: Replace `time_slot_picker/1`**

```elixir
  attr :date, :any, required: true
  attr :slots, :list, required: true
  attr :selected_slot, :any, default: nil

  def time_slot_picker(assigns) do
    ~H"""
    <div>
      <div :if={@slots != []} class="grid grid-cols-2 md:grid-cols-4 gap-2">
        <button
          :for={slot <- @slots}
          type="button"
          class={[
            "px-3 py-2 rounded-lg border text-sm font-semibold transition-colors",
            if(@selected_slot && DateTime.compare(@selected_slot, slot.starts_at) == :eq,
              do: "bg-cyan-500 text-white border-cyan-500",
              else: "bg-base-100 border-base-300 hover:border-cyan-500"
            )
          ]}
          phx-click="select_slot"
          phx-value-slot={DateTime.to_iso8601(slot.starts_at)}
        >
          {Calendar.strftime(slot.starts_at, "%I:%M %p")}
        </button>
      </div>

      <div :if={@date && @slots == []} class="alert alert-warning mt-4">
        <span>No available slots for this date. Please try another day.</span>
      </div>
    </div>
    """
  end
```

Note: removed the inline date-input from `time_slot_picker` since the date is selected via the `block_window_picker`'s date strip (or a parent). Component is now purely a slot picker.

- [ ] **Step 4: Run tests**

Run: `mix test test/mobile_car_wash_web/live/components/booking_components_test.exs`
Expected: 13 tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/mobile_car_wash_web/live/components/booking_components.ex test/mobile_car_wash_web/live/components/booking_components_test.exs
git commit -m "booking: refresh time_slot_picker chips (cyan-500 selected); drop inline date input"
```

---

## Task 5: Refresh `booking_summary/1` (TDD)

**Files:**
- Modify: `lib/mobile_car_wash_web/live/components/booking_components.ex` (`booking_summary/1`, lines 183-241)
- Modify: `test/mobile_car_wash_web/live/components/booking_components_test.exs`

- [ ] **Step 1: Append failing test**

```elixir
  describe "booking_summary/1" do
    test "renders all booking detail fields" do
      assigns = %{
        appointment: %{
          scheduled_at: ~U[2026-04-30 09:00:00Z],
          price_cents: 5000,
          discount_cents: 0
        },
        service: %{name: "Basic Wash", base_price_cents: 5000, duration_minutes: 45},
        vehicle: %{year: 2023, make: "Tesla", model: "Model 3", size: :car},
        address: %{street: "123 Main St", city: "San Antonio", state: "TX", zip: "78261"}
      }

      html =
        rendered_to_string(
          ~H|<.booking_summary appointment={@appointment} service={@service} vehicle={@vehicle} address={@address} />|
        )

      assert html =~ "Basic Wash"
      assert html =~ "2023 Tesla Model 3"
      assert html =~ "123 Main St"
      assert html =~ "$50"
      assert html =~ "45 minutes"
    end
  end
```

- [ ] **Step 2: Run, verify pass or fail**

Run: `mix test test/mobile_car_wash_web/live/components/booking_components_test.exs --only describe:booking_summary`
Likely passes with old markup since assertions are loose. If so, refresh classes anyway in Step 3 — test won't break.

- [ ] **Step 3: Replace `booking_summary/1`**

```elixir
  attr :appointment, :map, required: true
  attr :service, :map, required: true
  attr :vehicle, :map, required: true
  attr :address, :map, required: true

  def booking_summary(assigns) do
    ~H"""
    <div class="bg-base-100 border border-base-300 rounded-box p-5">
      <h3 class="text-lg font-semibold text-base-content mb-4">Booking Summary</h3>

      <dl class="space-y-3 text-sm">
        <div class="flex justify-between gap-4">
          <dt class="text-base-content/60">Service</dt>
          <dd class="font-semibold text-right">{@service.name}</dd>
        </div>

        <div class="flex justify-between gap-4">
          <dt class="text-base-content/60">Vehicle</dt>
          <dd class="font-semibold text-right">
            {@vehicle.year} {@vehicle.make} {@vehicle.model}
            <span class="ml-1 text-xs font-normal text-base-content/60">
              ({MobileCarWash.Billing.Pricing.size_label(@vehicle.size)})
            </span>
          </dd>
        </div>

        <div class="flex justify-between gap-4">
          <dt class="text-base-content/60">Location</dt>
          <dd class="font-semibold text-right">
            {@address.street}, {@address.city}, {@address.state} {@address.zip}
          </dd>
        </div>

        <div class="flex justify-between gap-4">
          <dt class="text-base-content/60">Date &amp; Time</dt>
          <dd class="font-semibold text-right">
            {Calendar.strftime(@appointment.scheduled_at, "%B %d, %Y at %I:%M %p")}
          </dd>
        </div>

        <div class="flex justify-between gap-4">
          <dt class="text-base-content/60">Duration</dt>
          <dd class="font-semibold text-right">{@service.duration_minutes} minutes</dd>
        </div>
      </dl>

      <div class="border-t border-base-300 mt-4 pt-4 flex justify-between items-baseline">
        <span class="text-sm font-semibold text-base-content">Total</span>
        <div>
          <span
            :if={@appointment.discount_cents > 0}
            class="line-through text-base-content/50 mr-2 text-sm"
          >
            ${div(@service.base_price_cents, 100)}
          </span>
          <span class="font-mono text-2xl font-bold text-cyan-700 tabular-nums">
            ${div(@appointment.price_cents, 100)}
          </span>
        </div>
      </div>
    </div>
    """
  end
```

- [ ] **Step 4: Run tests**

Run: `mix test test/mobile_car_wash_web/live/components/booking_components_test.exs`
Expected: 14 tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/mobile_car_wash_web/live/components/booking_components.ex test/mobile_car_wash_web/live/components/booking_components_test.exs
git commit -m "booking: refresh booking_summary with new tokens, mono total"
```

---

## Task 6: Refresh `confirmation_card/1` (TDD)

**Files:**
- Modify: `lib/mobile_car_wash_web/live/components/booking_components.ex` (`confirmation_card/1`, lines 246-276)
- Modify: `test/mobile_car_wash_web/live/components/booking_components_test.exs`

- [ ] **Step 1: Append failing test**

```elixir
  describe "confirmation_card/1" do
    test "renders headline, service, formatted date, and booking ID" do
      assigns = %{
        appointment: %{id: "appt_test_123", scheduled_at: ~U[2026-04-30 09:00:00Z]},
        service: %{name: "Basic Wash"}
      }

      html =
        rendered_to_string(
          ~H|<.confirmation_card appointment={@appointment} service={@service} />|
        )

      assert html =~ "Booking Confirmed"
      assert html =~ "Basic Wash"
      assert html =~ "appt_test_123"
      assert html =~ "April 30"
    end

    test "renders cyan check icon" do
      assigns = %{
        appointment: %{id: "x", scheduled_at: ~U[2026-04-30 09:00:00Z]},
        service: %{name: "X"}
      }

      html =
        rendered_to_string(
          ~H|<.confirmation_card appointment={@appointment} service={@service} />|
        )

      assert html =~ "hero-check-circle" or html =~ "text-cyan-500"
    end

    test "does NOT render its own CTA link (consumer renders that)" do
      assigns = %{
        appointment: %{id: "x", scheduled_at: ~U[2026-04-30 09:00:00Z]},
        service: %{name: "X"}
      }

      html =
        rendered_to_string(
          ~H|<.confirmation_card appointment={@appointment} service={@service} />|
        )

      refute html =~ "Back to Home"
    end
  end
```

- [ ] **Step 2: Run, verify failure**

Run: `mix test test/mobile_car_wash_web/live/components/booking_components_test.exs --only describe:confirmation_card`
Expected: failures — old card has "Back to Home" link, no `hero-check-circle`.

- [ ] **Step 3: Replace `confirmation_card/1`**

```elixir
  attr :appointment, :map, required: true
  attr :service, :map, required: true

  def confirmation_card(assigns) do
    ~H"""
    <div class="text-center py-8 max-w-md mx-auto">
      <div class="flex justify-center mb-4">
        <.icon name="hero-check-circle" class="size-12 text-cyan-500" />
      </div>
      <h2 class="text-2xl font-bold text-base-content tracking-tight mb-2">
        Booking Confirmed!
      </h2>
      <p class="text-sm text-base-content/70 mb-6">
        Your <strong>{@service.name}</strong> is scheduled for {Calendar.strftime(
          @appointment.scheduled_at,
          "%B %d, %Y at %I:%M %p"
        )}.
      </p>

      <div class="bg-base-100 border border-base-300 rounded-box p-4 text-left">
        <div class="text-xs font-semibold uppercase tracking-wide text-base-content/60 mb-1">
          Booking ID
        </div>
        <div class="font-mono text-sm text-base-content">{@appointment.id}</div>
        <div class="mt-3">
          <span class="inline-flex items-center text-[10px] font-bold uppercase tracking-wide bg-warning/15 text-warning px-2 py-0.5 rounded">
            Pending Confirmation
          </span>
        </div>
      </div>
    </div>
    """
  end
```

Note: this references `<.icon name="hero-check-circle" />`. The `icon/1` component is defined in `MobileCarWashWeb.CoreComponents` and imported into the page via `use MobileCarWashWeb, :live_view`. Since `BookingComponents` does NOT use `:live_view`, you need to import `icon/1` explicitly. Add at the top of the module after `use Phoenix.Component`:

```elixir
  import MobileCarWashWeb.CoreComponents, only: [icon: 1]
```

- [ ] **Step 4: Run tests**

Run: `mix test test/mobile_car_wash_web/live/components/booking_components_test.exs`
Expected: 17 tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/mobile_car_wash_web/live/components/booking_components.ex test/mobile_car_wash_web/live/components/booking_components_test.exs
git commit -m "booking: refresh confirmation_card (cyan check, no embedded CTA)"
```

---

## Task 7: Rewrite `:select_service` step in booking_live.ex

**Files:**
- Modify: `lib/mobile_car_wash_web/live/booking_live.ex` (the `:select_service` step block, ~lines 231-243)

- [ ] **Step 1: Read current `:select_service` block**

Run: `sed -n '225,250p' lib/mobile_car_wash_web/live/booking_live.ex`
Note the current markup. Identify the assign that drives "selected" highlight (likely `@selected_service` or `@service_slug`).

- [ ] **Step 2: Replace the `:select_service` block**

Find the block `<div :if={@current_step == :select_service}>...</div>` and replace its contents with:

```heex
      <div :if={@current_step == :select_service}>
        <div class="text-center mb-6">
          <h1 class="text-2xl font-bold text-base-content tracking-tight">
            Pick your service
          </h1>
          <p class="text-sm text-base-content/60 mt-1">
            Two tiers. No hidden fees.
          </p>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mb-6">
          <.service_card
            :for={service <- @services}
            service={service}
            selected={@selected_service && @selected_service.slug == service.slug}
          />
        </div>

        <div class="flex justify-end">
          <button
            class="btn btn-primary"
            phx-click="next_step"
            disabled={is_nil(@selected_service)}
          >
            Continue
          </button>
        </div>
      </div>
```

**If the existing assign is named differently** (e.g., `@service_slug`), substitute it. The selection logic in the OLD code is:
```heex
selected={@selected_service && @selected_service.slug == service.slug}
```

If there's no `@selected_service` and selection is by slug-string only, use:
```heex
selected={@service_slug == service.slug}
```

- [ ] **Step 3: Verify compile**

Run: `mix compile --warnings-as-errors 2>&1 | tail -3`
Expected: clean. If you see `undefined assign @selected_service`, the assign is named differently — adapt and re-compile.

- [ ] **Step 4: SKIP — controller will run full mix test at final checkpoint**

- [ ] **Step 5: Commit**

```bash
git add lib/mobile_car_wash_web/live/booking_live.ex
git commit -m "booking: rewrite :select_service step against refreshed service_card"
```

---

## Task 8: Rewrite `:schedule` step in booking_live.ex

**Files:**
- Modify: `lib/mobile_car_wash_web/live/booking_live.ex` (the `:schedule` step block, ~lines 573-583)

- [ ] **Step 1: Read current `:schedule` block**

Run: `sed -n '568,590p' lib/mobile_car_wash_web/live/booking_live.ex`
Note the assigns it uses (likely `@selected_date`, `@available_blocks`, `@selected_block`).

- [ ] **Step 2: Replace the `:schedule` block**

Find `<div :if={@current_step == :schedule}>...</div>` and replace its contents with:

```heex
      <div :if={@current_step == :schedule}>
        <div class="mb-6">
          <h1 class="text-2xl font-bold text-base-content tracking-tight">
            Pick a time
          </h1>
          <p class="text-sm text-base-content/60 mt-1">
            We'll confirm your exact arrival time by midnight the day before.
          </p>
        </div>

        <.block_window_picker
          date={@selected_date}
          blocks={@available_blocks}
          selected_block={@selected_block}
        />

        <div class="flex justify-end mt-6">
          <button
            class="btn btn-primary"
            phx-click="next_step"
            disabled={is_nil(@selected_block)}
          >
            Continue
          </button>
        </div>
      </div>
```

**Adapt assign names** if needed (`@selected_date`, `@available_blocks`, `@selected_block`).

- [ ] **Step 3: Verify compile**

Run: `mix compile --warnings-as-errors 2>&1 | tail -3`
Expected: clean.

- [ ] **Step 4: Commit**

```bash
git add lib/mobile_car_wash_web/live/booking_live.ex
git commit -m "booking: rewrite :schedule step against refreshed block_window_picker"
```

---

## Task 9: Rewrite `:confirmed` step in booking_live.ex

**Files:**
- Modify: `lib/mobile_car_wash_web/live/booking_live.ex` (the `:confirmed` step block, ~lines 680-682)

- [ ] **Step 1: Read current block**

Run: `sed -n '678,690p' lib/mobile_car_wash_web/live/booking_live.ex`
Note: the existing `confirmation_card` is called with `appointment` AND `service`. The template needs to pass both.

- [ ] **Step 2: Replace the `:confirmed` block**

Find `<div :if={@current_step == :confirmed && @appointment}>...</div>` and replace its contents with:

```heex
      <div :if={@current_step == :confirmed && @appointment}>
        <.confirmation_card appointment={@appointment} service={@selected_service} />

        <div class="flex justify-center mt-6">
          <.link navigate={~p"/book/success?id=#{@appointment.id}"} class="btn btn-primary">
            Track your appointment →
          </.link>
        </div>
      </div>
```

**Adapt assign name** for service if needed. If `@selected_service` is not available at this point in the flow (e.g., it gets cleared before reaching `:confirmed`), inspect the existing template to find what's used — likely `@appointment.service` or a separately-loaded `@service` assign.

**Route check:** verify `/book/success` accepts `?id=` query param. Run: `grep -A 5 "/book/success" lib/mobile_car_wash_web/router.ex`. If the live view's mount/3 doesn't accept `id`, drop the `?id=#{@appointment.id}` part.

- [ ] **Step 3: Verify compile**

Run: `mix compile --warnings-as-errors 2>&1 | tail -3`
Expected: clean.

- [ ] **Step 4: Commit**

```bash
git add lib/mobile_car_wash_web/live/booking_live.ex
git commit -m "booking: rewrite :confirmed step against refreshed confirmation_card"
```

---

## Task 10: Update existing booking-related tests for new markup

**Files:**
- Modify: any existing test files identified in Task 0 Step 4 that assert on old markup

- [ ] **Step 1: Run full project test suite to discover regressions**

Run: `mix test 2>&1 | tee /tmp/plan3b1-regression.log | tail -20`
Expected: most tests pass. Any failures are likely from:
- Tests asserting on daisyUI `<ul class="steps">` markup
- Tests asserting on old `service_card` classes (e.g., `ring-2 ring-primary`)
- Tests asserting on the old confirmation_card "Back to Home" link
- Tests asserting on the old `<input type="date">` in block_window_picker

- [ ] **Step 2: Triage failures and update assertions**

For each failing assertion:
- Read the rendered HTML in the failure message
- Update the assertion to match the new markup OR drop assertions that no longer make sense
- DO NOT change production code to satisfy stale tests — the spec's design wins

Common updates:
- `assert html =~ "Back to Home"` → drop OR change to `assert html =~ "Track your appointment"`
- `assert html =~ "ring-primary"` → `assert html =~ "border-cyan-500"`
- `assert html =~ "<input type=\"date\""` → drop (date input replaced by date strip)
- `assert html =~ "step-primary"` → `assert html =~ "Step"` (or drop — daisyUI step pattern is gone)

- [ ] **Step 3: Re-run tests**

Run: `mix test 2>&1 | tail -3`
Expected: 0 failures, count = baseline + 17 (new component tests).

- [ ] **Step 4: Commit (if any test changes made)**

```bash
git add -p   # selectively stage
git commit -m "test: update booking test assertions for refreshed components"
```

---

## Task 11: Final verification

**Files:** none modified — purely verification.

- [ ] **Step 1: Run full project test suite**

Run: `mix test 2>&1 | tail -3`
Expected: ≥1056 tests (baseline + 17 new component tests), 0 failures.

- [ ] **Step 2: Verify compile + format + assets**

```bash
mix compile --warnings-as-errors 2>&1 | tail -3
mix format --check-formatted 2>&1 | tail -3
mix assets.deploy 2>&1 | tail -5
```
All clean.

If format flags issues: `mix format && git add -A && git commit -m "chore: mix format"`.

- [ ] **Step 3: Boot dev server and visually smoke-test the booking flow**

```bash
mix phx.server
```

Open `http://localhost:4000/book` in a browser. Click through the first few steps:
- Service selection: 2 tier cards visible, click selects (cyan ring + ✓ badge appears), Continue button enabled only with selection
- Step indicator at top shows "Step 1 of 8 — Service · 13% complete"
- Click Continue → step 2 (Account/auth) — this step is OLD markup (Plan 3b-2 territory). Acceptable.
- If you can navigate past auth + vehicle + address (via existing flow) all the way to Schedule, verify the date strip renders and clicking a date fetches blocks.

Stop the server.

- [ ] **Step 4: Confirm git log**

Run: `git log --oneline main..HEAD | head -15` (or `git log --oneline -15`)
You should see 9-10 commits from Plan 3b-1.

- [ ] **Step 5: Report Plan 3b-1 complete**

Summary:
- 6 booking components refreshed (step indicator → progress bar; service card → selectable cyan; block picker → date strip; time slot picker → cyan chips; booking summary → mono total; confirmation card → cyan check)
- 17 new component tests
- 3 step templates rewritten (`:select_service`, `:schedule`, `:confirmed`)
- Existing tests updated for new markup
- All ≥1056 tests passing

Recommend the user click through `/book` step 1 → step 6 to visually verify before promoting. Plans 3b-2 (auth/vehicle/address) and 3b-3 (photos/review) are still ahead.

---

## What's NOT in Plan 3b-1

- `:auth` / `:vehicle` / `:address` step rewrites → **Plan 3b-2**
- `:photos` / `:review` step rewrites → **Plan 3b-3**
- Mobile sticky CTA pattern → 3b-2 or 3b-3
- Stripe Elements styling → 3b-3
- Standalone `/book/success` page → **Plan 3c**
- BookingStateMachine logic changes (never)
- Event handler changes (never)
