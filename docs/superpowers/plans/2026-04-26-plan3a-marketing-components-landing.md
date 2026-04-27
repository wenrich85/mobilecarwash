# Phase-1, Plan 3a — Marketing Components + Landing Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `MobileCarWashWeb.MarketingComponents` module with 6 reusable customer-facing components (`hero`, `service_tier_card`, `tech_section`, `testimonial`, `cta_band`, `feature_grid`), then rewrite `landing_live.ex` to use them. All copy is locked in the spec — implementer renders it as-is.

**Architecture:** Each component is a Phoenix function component, TDD'd individually before the next is added. Landing page rewrite is a single coordinated change (template swap + mount cleanup + new structural test file). Builds on Plan 1's design tokens and Plan 2's brand assets — references `logo_light_v2.svg` and the new color palette via daisyUI.

**Tech Stack:** Phoenix LiveView 1.x, Tailwind CSS v4 + daisyUI, Phoenix.Component, ExUnit, `Phoenix.LiveViewTest.rendered_to_string/1` for component testing, `Phoenix.LiveViewTest.live/2` for the landing page integration test.

**Spec reference:** [docs/superpowers/specs/2026-04-26-plan3a-marketing-components-landing-design.md](docs/superpowers/specs/2026-04-26-plan3a-marketing-components-landing-design.md) — all drafted copy is in the spec's "Drafted copy" section.

**File map for this plan:**

- New: `lib/mobile_car_wash_web/components/marketing_components.ex` — 6 components
- New: `test/mobile_car_wash_web/components/marketing_components_test.exs` — ~15 tests
- Modify: `lib/mobile_car_wash_web/live/landing_live.ex` — drop `SubscriptionPlan` from `mount/3`; rewrite `render/1` template
- New: `test/mobile_car_wash_web/live/landing_live_test.exs` — structural test for the new landing
- (Existing `test/mobile_car_wash_web/live/seo_test.exs` should keep passing — JSON-LD + canonical assertions still hold)

**Out of scope (deferred):**

- Booking page rewrite → **Plan 3b**
- Booking success page rewrite → **Plan 3c**
- Sign-in / register / subscription manage redesigns → phase-2 spec
- Real testimonial copy (3 placeholders ship; user replaces pre-launch)
- Mobile sticky CTA, A/B testing, i18n

---

## Task 0: Pre-flight verification

**Files:** none modified — read-only.

- [ ] **Step 1: Verify clean tree on the right branch**

Run: `git status && git branch --show-current`
Expected: clean tree on a Plan-3a feature branch (or `main` if working directly — the controller will tell you).

- [ ] **Step 2: Verify Plan 1 + Plan 2 baseline is green**

Run: `mix test 2>&1 | tail -3`
Expected: at least `1017 tests, 0 failures` (Plan 2's count). Higher is fine.

- [ ] **Step 3: Read current landing_live.ex to map what exists**

Run: `wc -l lib/mobile_car_wash_web/live/landing_live.ex && grep -n 'def mount\|def render\|def handle' lib/mobile_car_wash_web/live/landing_live.ex`
Expected: ~336 lines, with at least `mount/3` and `render/1`. Note any handlers — they'll need to stay or be deliberately removed.

- [ ] **Step 4: Read current mount/3 to find SubscriptionPlan load**

Run: `grep -A 20 'def mount' lib/mobile_car_wash_web/live/landing_live.ex | head -30`
Note the lines that load `SubscriptionPlan` records (assigned to something like `@subscription_plans`). These get deleted in Task 8.

- [ ] **Step 5: Note baseline test count**

Record the test count for the final-checkpoint comparison.

---

## Task 1: Create MarketingComponents module + `hero/1`

**Files:**
- Create: `lib/mobile_car_wash_web/components/marketing_components.ex`
- Create: `test/mobile_car_wash_web/components/marketing_components_test.exs`

- [ ] **Step 1: Write the failing test**

Create `test/mobile_car_wash_web/components/marketing_components_test.exs`:

```elixir
defmodule MobileCarWashWeb.MarketingComponentsTest do
  use ExUnit.Case, async: true
  import Phoenix.Component
  import Phoenix.LiveViewTest
  import MobileCarWashWeb.MarketingComponents

  describe "hero/1" do
    test "renders headline and subhead" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.hero headline="Big Promise" subhead="Small Detail">
          <:primary_cta>
            <a href="/booking">Book</a>
          </:primary_cta>
        </.hero>
        """)

      assert html =~ "Big Promise"
      assert html =~ "Small Detail"
      assert html =~ ~s(href="/booking")
    end

    test "renders trust badge when provided" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.hero headline="X" subhead="Y" trust_badge="LICENSED">
          <:primary_cta><a>Go</a></:primary_cta>
        </.hero>
        """)

      assert html =~ "LICENSED"
    end

    test "renders secondary_cta when provided" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.hero headline="X" subhead="Y">
          <:primary_cta><a href="/a">Primary</a></:primary_cta>
          <:secondary_cta><a href="/b">Secondary</a></:secondary_cta>
        </.hero>
        """)

      assert html =~ "Primary"
      assert html =~ "Secondary"
      assert html =~ ~s(href="/b")
    end
  end
end
```

- [ ] **Step 2: Run tests, verify they fail**

Run: `mix test test/mobile_car_wash_web/components/marketing_components_test.exs`
Expected: compile error — `MobileCarWashWeb.MarketingComponents` is undefined.

- [ ] **Step 3: Create the module with `hero/1`**

Create `lib/mobile_car_wash_web/components/marketing_components.ex`:

```elixir
defmodule MobileCarWashWeb.MarketingComponents do
  @moduledoc """
  Customer-facing components used on landing, booking, and other
  marketing pages. Distinct from CoreComponents (which are general-
  purpose). All components use Plan 1's design tokens and Plan 2's
  brand assets.
  """
  use Phoenix.Component

  @doc """
  Renders a centered hero with optional trust badge above the headline.

  ## Examples

      <.hero headline="Your car, washed where you parked it."
             subhead="Book in 30 seconds. We come to you."
             trust_badge="SAN ANTONIO · LICENSED & INSURED">
        <:primary_cta>
          <a href="/booking" class="btn btn-primary">Book my first wash</a>
        </:primary_cta>
        <:secondary_cta>
          <a href="#pricing" class="btn btn-ghost">See pricing</a>
        </:secondary_cta>
      </.hero>
  """
  attr :headline, :string, required: true
  attr :subhead, :string, required: true
  attr :trust_badge, :string, default: nil
  slot :primary_cta, required: true
  slot :secondary_cta

  def hero(assigns) do
    ~H"""
    <section class="bg-base-100 py-12 md:py-16 px-4">
      <div class="max-w-3xl mx-auto text-center">
        <div
          :if={@trust_badge}
          class="inline-block text-[11px] font-semibold tracking-wider text-cyan-700 bg-cyan-50 px-3 py-1 rounded-full mb-4"
        >
          {@trust_badge}
        </div>
        <h1 class="text-3xl md:text-5xl font-bold text-base-content tracking-tight leading-[1.1] mb-3">
          {@headline}
        </h1>
        <p class="text-base md:text-lg text-base-content/70 max-w-xl mx-auto mb-6">
          {@subhead}
        </p>
        <div class="flex flex-col sm:flex-row items-center justify-center gap-3">
          <div>{render_slot(@primary_cta)}</div>
          <div :if={@secondary_cta != []}>{render_slot(@secondary_cta)}</div>
        </div>
      </div>
    </section>
    """
  end
end
```

- [ ] **Step 4: Run tests, verify pass**

Run: `mix test test/mobile_car_wash_web/components/marketing_components_test.exs`
Expected: 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/mobile_car_wash_web/components/marketing_components.ex test/mobile_car_wash_web/components/marketing_components_test.exs
git commit -m "marketing: add MarketingComponents module + <.hero> component"
```

---

## Task 2: Add `service_tier_card/1`

**Files:**
- Modify: `lib/mobile_car_wash_web/components/marketing_components.ex`
- Modify: `test/mobile_car_wash_web/components/marketing_components_test.exs`

- [ ] **Step 1: Append failing tests**

Append to test file (before module's closing `end`):

```elixir
  describe "service_tier_card/1" do
    test "renders name, price, duration, features" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.service_tier_card
          name="Basic Wash"
          price="$50"
          duration="~45 min"
          features={["Exterior hand wash", "Wheels & tires"]}
        >
          <:cta><a href="/booking?tier=basic">Book Basic</a></:cta>
        </.service_tier_card>
        """)

      assert html =~ "Basic Wash"
      assert html =~ "$50"
      assert html =~ "~45 min"
      assert html =~ "Exterior hand wash"
      assert html =~ "Wheels &amp; tires"
      assert html =~ "Book Basic"
    end

    test "renders highlighted variant with MOST POPULAR badge" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.service_tier_card
          name="Premium"
          price="$199.99"
          duration="~3 hours"
          features={["Everything in Basic"]}
          highlighted={true}
        >
          <:cta><a>Book Premium</a></:cta>
        </.service_tier_card>
        """)

      assert html =~ "MOST POPULAR"
      assert html =~ "border-cyan-500"
    end

    test "non-highlighted card omits MOST POPULAR badge" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.service_tier_card name="Basic" price="$50" duration="~45 min" features={[]}>
          <:cta><a>Book</a></:cta>
        </.service_tier_card>
        """)

      refute html =~ "MOST POPULAR"
    end
  end
```

- [ ] **Step 2: Run tests, verify failure**

Run: `mix test test/mobile_car_wash_web/components/marketing_components_test.exs --only describe:service_tier_card`
Expected: function undefined.

- [ ] **Step 3: Add `service_tier_card/1` to MarketingComponents**

Append to `marketing_components.ex` before its final `end`:

```elixir
  @doc """
  Renders a pricing tier card with optional MOST POPULAR highlight.

  ## Examples

      <.service_tier_card
        name="Premium"
        price="$199.99"
        duration="~3 hours"
        features={["Everything in Basic", "Full interior wipe-down"]}
        highlighted={true}
      >
        <:cta><a href="/booking?tier=premium" class="btn btn-primary w-full">Book Premium</a></:cta>
      </.service_tier_card>
  """
  attr :name, :string, required: true
  attr :price, :string, required: true
  attr :duration, :string, required: true
  attr :features, :list, required: true
  attr :highlighted, :boolean, default: false
  slot :cta, required: true

  def service_tier_card(assigns) do
    ~H"""
    <div class={[
      "relative bg-base-100 rounded-box p-5 flex flex-col",
      if(@highlighted, do: "border-2 border-cyan-500", else: "border border-base-300")
    ]}>
      <div
        :if={@highlighted}
        class="absolute -top-3 right-4 bg-cyan-500 text-white text-[10px] font-bold tracking-wide px-2 py-1 rounded-full"
      >
        MOST POPULAR
      </div>
      <div class="text-xs font-semibold uppercase tracking-wide text-base-content/60 mb-1">
        {@name}
      </div>
      <div class="font-mono text-3xl font-bold text-base-content tracking-tight">
        {@price}
      </div>
      <div class="text-xs text-base-content/60 mt-0.5 mb-4">{@duration}</div>
      <ul class="text-sm text-base-content/80 space-y-1.5 mb-6 flex-1">
        <li :for={feature <- @features} class="flex items-start gap-2">
          <span class="text-cyan-500 font-semibold">✓</span>
          <span>{feature}</span>
        </li>
      </ul>
      <div class="mt-auto min-h-12">
        {render_slot(@cta)}
      </div>
    </div>
    """
  end
```

- [ ] **Step 4: Run tests**

Run: `mix test test/mobile_car_wash_web/components/marketing_components_test.exs`
Expected: 6 tests pass (3 hero + 3 service_tier_card).

- [ ] **Step 5: Commit**

```bash
git add lib/mobile_car_wash_web/components/marketing_components.ex test/mobile_car_wash_web/components/marketing_components_test.exs
git commit -m "marketing: add <.service_tier_card> component"
```

---

## Task 3: Add `tech_section/1`

**Files:**
- Modify: `lib/mobile_car_wash_web/components/marketing_components.ex`
- Modify: `test/mobile_car_wash_web/components/marketing_components_test.exs`

- [ ] **Step 1: Append failing tests**

Append to test file:

```elixir
  describe "tech_section/1" do
    test "renders eyebrow, headline, subhead" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.tech_section
          eyebrow="[ DIFF ]"
          headline="On-time arrival"
          subhead="15-min windows."
        >
          <:preview>SMS_PREVIEW_HERE</:preview>
        </.tech_section>
        """)

      assert html =~ "[ DIFF ]"
      assert html =~ "On-time arrival"
      assert html =~ "15-min windows."
      assert html =~ "SMS_PREVIEW_HERE"
    end

    test "renders bullets with arrow prefixes" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.tech_section
          headline="X"
          subhead="Y"
          bullets={["First point", "Second point"]}
        >
          <:preview>P</:preview>
        </.tech_section>
        """)

      assert html =~ "First point"
      assert html =~ "Second point"
    end
  end
```

- [ ] **Step 2: Run tests, verify failure**

Run: `mix test test/mobile_car_wash_web/components/marketing_components_test.exs --only describe:tech_section`
Expected: function undefined.

- [ ] **Step 3: Add `tech_section/1`**

Append to `marketing_components.ex`:

```elixir
  @doc """
  Renders a dark "how we're different" section with cyan glow.

  Two-column on desktop (type left, :preview slot right), stacks on mobile.

  ## Examples

      <.tech_section
        headline="We tell you exactly when we'll arrive."
        subhead="Most washes give you a 4-hour window. We give you 15 minutes."
        bullets={["15-minute arrival windows", "Live SMS updates"]}
      >
        <:preview>
          <!-- inline stylized SMS conversation -->
        </:preview>
      </.tech_section>
  """
  attr :eyebrow, :string, default: "[ HOW WE'RE DIFFERENT ]"
  attr :headline, :string, required: true
  attr :subhead, :string, required: true
  attr :bullets, :list, default: []
  slot :preview

  def tech_section(assigns) do
    ~H"""
    <section class="relative bg-slate-900 py-16 px-4 overflow-hidden">
      <div class="absolute top-1/2 -right-20 w-96 h-96 bg-cyan-500/25 rounded-full blur-3xl -translate-y-1/2"></div>
      <div class="relative max-w-6xl mx-auto grid grid-cols-1 md:grid-cols-2 gap-10 items-center">
        <div>
          <div class="font-mono text-xs text-cyan-400 tracking-widest mb-2">
            {@eyebrow}
          </div>
          <h2 class="text-2xl md:text-3xl font-bold text-white tracking-tight leading-[1.15] mb-3">
            {@headline}
          </h2>
          <p class="text-sm md:text-base text-slate-400 leading-relaxed mb-4">
            {@subhead}
          </p>
          <ul :if={@bullets != []} class="text-sm text-slate-300 space-y-2 list-none p-0">
            <li :for={bullet <- @bullets}>{bullet}</li>
          </ul>
        </div>
        <div :if={@preview != []}>
          {render_slot(@preview)}
        </div>
      </div>
    </section>
    """
  end
```

- [ ] **Step 4: Run tests**

Run: `mix test test/mobile_car_wash_web/components/marketing_components_test.exs`
Expected: 8 tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/mobile_car_wash_web/components/marketing_components.ex test/mobile_car_wash_web/components/marketing_components_test.exs
git commit -m "marketing: add <.tech_section> component"
```

---

## Task 4: Add `testimonial/1`

**Files:**
- Modify: `lib/mobile_car_wash_web/components/marketing_components.ex`
- Modify: `test/mobile_car_wash_web/components/marketing_components_test.exs`

- [ ] **Step 1: Append failing tests**

Append:

```elixir
  describe "testimonial/1" do
    test "renders quote and name" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.testimonial quote="Great service" name="Maria G." />
        """)

      assert html =~ "Great service"
      assert html =~ "Maria G."
    end

    test "renders vehicle when provided" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.testimonial quote="X" name="Y" vehicle="2023 Tesla" />
        """)

      assert html =~ "2023 Tesla"
    end

    test "omits vehicle row when not provided" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.testimonial quote="X" name="Y" />
        """)

      refute html =~ "Tesla"
    end
  end
```

- [ ] **Step 2: Run tests, verify failure**

Run: `mix test test/mobile_car_wash_web/components/marketing_components_test.exs --only describe:testimonial`

- [ ] **Step 3: Add `testimonial/1`**

Append to `marketing_components.ex`:

```elixir
  @doc """
  Renders a single customer testimonial card.

  ## Examples

      <.testimonial
        quote="Showed up exactly on time and my car looked brand new."
        name="Maria G."
        vehicle="2023 Tesla Model 3"
      />
  """
  attr :quote, :string, required: true
  attr :name, :string, required: true
  attr :vehicle, :string, default: nil

  def testimonial(assigns) do
    ~H"""
    <div class="bg-base-100 border border-base-300 rounded-box p-5">
      <div class="text-cyan-500 text-3xl font-serif leading-none mb-2">"</div>
      <p class="text-sm text-base-content/80 italic leading-relaxed mb-3">
        {@quote}
      </p>
      <div class="text-xs">
        <div class="font-semibold text-base-content">{@name}</div>
        <div :if={@vehicle} class="text-base-content/60 mt-0.5">{@vehicle}</div>
      </div>
    </div>
    """
  end
```

- [ ] **Step 4: Run tests**

Run: `mix test test/mobile_car_wash_web/components/marketing_components_test.exs`
Expected: 11 tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/mobile_car_wash_web/components/marketing_components.ex test/mobile_car_wash_web/components/marketing_components_test.exs
git commit -m "marketing: add <.testimonial> component"
```

---

## Task 5: Add `cta_band/1`

**Files:**
- Modify: `lib/mobile_car_wash_web/components/marketing_components.ex`
- Modify: `test/mobile_car_wash_web/components/marketing_components_test.exs`

- [ ] **Step 1: Append failing tests**

Append:

```elixir
  describe "cta_band/1" do
    test "renders headline, subhead, cta" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.cta_band headline="Ready?" subhead="No commitment.">
          <:cta><a href="/booking">Book</a></:cta>
        </.cta_band>
        """)

      assert html =~ "Ready?"
      assert html =~ "No commitment."
      assert html =~ ~s(href="/booking")
      assert html =~ ">Book<"
    end
  end
```

- [ ] **Step 2: Run, verify failure**

Run: `mix test test/mobile_car_wash_web/components/marketing_components_test.exs --only describe:cta_band`

- [ ] **Step 3: Add `cta_band/1`**

Append to `marketing_components.ex`:

```elixir
  @doc """
  Renders a centered CTA band — used near the bottom of marketing pages
  to drive a final conversion.

  ## Examples

      <.cta_band
        headline="Ready for a clean car without the trip?"
        subhead="First wash, no commitment."
      >
        <:cta>
          <a href="/booking" class="btn btn-primary">Book my first wash →</a>
        </:cta>
      </.cta_band>
  """
  attr :headline, :string, required: true
  attr :subhead, :string, required: true
  slot :cta, required: true

  def cta_band(assigns) do
    ~H"""
    <section class="bg-base-100 py-12 px-4 text-center">
      <h2 class="text-2xl font-bold text-base-content tracking-tight mb-2">
        {@headline}
      </h2>
      <p class="text-sm text-base-content/60 mb-5">{@subhead}</p>
      <div class="flex justify-center min-h-12">
        {render_slot(@cta)}
      </div>
    </section>
    """
  end
```

- [ ] **Step 4: Run tests**

Run: `mix test test/mobile_car_wash_web/components/marketing_components_test.exs`
Expected: 12 tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/mobile_car_wash_web/components/marketing_components.ex test/mobile_car_wash_web/components/marketing_components_test.exs
git commit -m "marketing: add <.cta_band> component"
```

---

## Task 6: Add `feature_grid/1`

**Files:**
- Modify: `lib/mobile_car_wash_web/components/marketing_components.ex`
- Modify: `test/mobile_car_wash_web/components/marketing_components_test.exs`

- [ ] **Step 1: Append failing tests**

Append:

```elixir
  describe "feature_grid/1" do
    test "renders items with numbered badges and titles" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.feature_grid columns={3}>
          <:item number="1" title="Step One">First body</:item>
          <:item number="2" title="Step Two">Second body</:item>
          <:item number="3" title="Step Three">Third body</:item>
        </.feature_grid>
        """)

      assert html =~ "Step One"
      assert html =~ "Step Two"
      assert html =~ "Step Three"
      assert html =~ "First body"
      assert html =~ "Third body"
      assert html =~ ">1<"
      assert html =~ ">3<"
    end

    test "uses 3 columns by default" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.feature_grid>
          <:item number="1" title="A">B</:item>
        </.feature_grid>
        """)

      assert html =~ "md:grid-cols-3"
    end

    test "uses 2 columns when columns={2}" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.feature_grid columns={2}>
          <:item number="1" title="A">B</:item>
        </.feature_grid>
        """)

      assert html =~ "md:grid-cols-2"
    end
  end
```

- [ ] **Step 2: Run, verify failure**

Run: `mix test test/mobile_car_wash_web/components/marketing_components_test.exs --only describe:feature_grid`

- [ ] **Step 3: Add `feature_grid/1`**

Append to `marketing_components.ex`:

```elixir
  @doc """
  Renders a numbered grid of feature/step items.

  Each item slot takes a `number` (string), `title` (string), and inner
  block (the body text).

  ## Examples

      <.feature_grid columns={3}>
        <:item number="1" title="Book online">Pick a service, pick a time.</:item>
        <:item number="2" title="We come to you">SMS update with arrival window.</:item>
        <:item number="3" title="Pay when done">No deposit. Card charged after.</:item>
      </.feature_grid>
  """
  attr :columns, :integer, default: 3, values: [2, 3, 4]
  slot :item, required: true do
    attr :number, :string
    attr :title, :string, required: true
  end

  def feature_grid(assigns) do
    cols_class =
      case assigns.columns do
        2 -> "md:grid-cols-2"
        3 -> "md:grid-cols-3"
        4 -> "md:grid-cols-4"
      end

    assigns = assign(assigns, :cols_class, cols_class)

    ~H"""
    <div class={["grid grid-cols-1 gap-4", @cols_class]}>
      <div :for={item <- @item} class="bg-base-200 rounded-box p-5">
        <div
          :if={item[:number]}
          class="w-7 h-7 bg-cyan-500 text-white rounded-lg flex items-center justify-center font-bold text-sm mb-2.5"
        >
          {item.number}
        </div>
        <div class="text-sm font-semibold text-base-content mb-1">
          {item.title}
        </div>
        <div class="text-sm text-base-content/70 leading-relaxed">
          {render_slot(item)}
        </div>
      </div>
    </div>
    """
  end
```

- [ ] **Step 4: Run tests**

Run: `mix test test/mobile_car_wash_web/components/marketing_components_test.exs`
Expected: 15 tests pass (all 6 components covered).

- [ ] **Step 5: Commit**

```bash
git add lib/mobile_car_wash_web/components/marketing_components.ex test/mobile_car_wash_web/components/marketing_components_test.exs
git commit -m "marketing: add <.feature_grid> component (final marketing component)"
```

---

## Task 7: Drop unused `SubscriptionPlan` load from landing's mount/3

**Files:**
- Modify: `lib/mobile_car_wash_web/live/landing_live.ex` (mount/3 only)

- [ ] **Step 1: Find the SubscriptionPlan reference**

Run: `grep -n 'SubscriptionPlan\|subscription_plan' lib/mobile_car_wash_web/live/landing_live.ex`
Note all matches. The mount likely has a query like `SubscriptionPlan |> Ash.read!()` and an assign like `assign(socket, :subscription_plans, plans)`.

- [ ] **Step 2: Remove the load and assign from mount/3**

Edit `lib/mobile_car_wash_web/live/landing_live.ex` — delete the lines that:
- Query `SubscriptionPlan`
- Assign `:subscription_plans`

Leave the `ServiceType` query intact (still used by the new pricing tiers section).

If `SubscriptionPlan` is referenced elsewhere in `landing_live.ex` (e.g., inside `render/1` or in private helper functions), DON'T remove those references in this task — just the mount load. The render rewrite in Task 8 will replace any template references.

- [ ] **Step 3: Verify compile**

Run: `mix compile --warnings-as-errors 2>&1 | tail -3`
Expected: clean. If there are warnings about an unused alias for `SubscriptionPlan`, remove the alias from the top of the module too.

- [ ] **Step 4: Commit**

```bash
git add lib/mobile_car_wash_web/live/landing_live.ex
git commit -m "marketing: drop SubscriptionPlan load from landing mount/3

Subscriptions are not on landing in the new design — they get their
own page in phase-2. The render template still references
@subscription_plans in this commit; Task 8 replaces the template
entirely so the reference disappears."
```

---

## Task 8: Rewrite landing_live render template

**Files:**
- Modify: `lib/mobile_car_wash_web/live/landing_live.ex` (render/1)

This is the largest single edit in the plan. The `render/1` function gets entirely replaced. Behavior preserved: page renders at `/`, mount/3 still loads `@service_types` (a list of `%ServiceType{}` records).

The new render uses `MobileCarWashWeb.MarketingComponents` (already imported via `use MobileCarWashWeb, :live_view`). All copy is locked in the spec — render it as-is.

- [ ] **Step 1: Read the current render/1 to confirm what's being replaced**

Run: `grep -n 'def render' lib/mobile_car_wash_web/live/landing_live.ex`
Note the line number. The function starts there and runs until its terminating `end`. You're replacing the entire body.

- [ ] **Step 2: Add the import for MarketingComponents at the top**

Find the `use MobileCarWashWeb, :live_view` line. Immediately after it, add:

```elixir
  import MobileCarWashWeb.MarketingComponents
```

- [ ] **Step 3: Replace `render/1` entirely**

Find `def render(assigns) do` … `end` and replace with:

```elixir
  @impl true
  def render(assigns) do
    basic = Enum.find(@service_types, fn st -> st.slug == "basic_wash" end)
    premium = Enum.find(@service_types, fn st -> st.slug == "deep_clean_detail" end) ||
              Enum.find(@service_types, fn st -> st.slug == "premium" end)

    assigns = assign(assigns, basic: basic, premium: premium)

    ~H"""
    <div>
      <%!-- =================== TOP NAV =================== --%>
      <nav class="bg-base-100 border-b border-base-300">
        <div class="max-w-7xl mx-auto px-4 py-3 flex items-center justify-between">
          <a href="/" class="flex items-center">
            <img src={~p"/images/logo_light_v2.svg"} alt="Driveway Detail Co" class="h-8" />
          </a>
          <div class="flex items-center gap-4">
            <a href={~p"/sign-in"} class="hidden sm:inline text-sm text-base-content/70 hover:text-base-content">
              Sign in
            </a>
            <.link navigate={~p"/booking"} class="btn btn-primary btn-sm">
              Book a wash
            </.link>
          </div>
        </div>
      </nav>

      <%!-- =================== HERO =================== --%>
      <.hero
        headline="Your car, washed where you parked it."
        subhead="Book in 30 seconds. We come to you. Pay when it's done."
        trust_badge="SAN ANTONIO · LICENSED & INSURED"
      >
        <:primary_cta>
          <.link navigate={~p"/booking"} class="btn btn-primary">
            Book my first wash
          </.link>
        </:primary_cta>
        <:secondary_cta>
          <a href="#pricing" class="btn btn-ghost">See pricing</a>
        </:secondary_cta>
      </.hero>

      <%!-- =================== HOW IT WORKS =================== --%>
      <section class="bg-base-100 py-12 px-4">
        <div class="max-w-6xl mx-auto">
          <div class="text-center mb-8">
            <div class="text-xs font-semibold uppercase tracking-wide text-base-content/60 mb-1">
              HOW IT WORKS
            </div>
            <h2 class="text-2xl font-bold text-base-content tracking-tight">
              Three steps. No hose hookup.
            </h2>
          </div>
          <.feature_grid columns={3}>
            <:item number="1" title="Book online">
              Pick a service, pick a time, enter your address. 30 seconds.
            </:item>
            <:item number="2" title="We come to you">
              SMS update with our 15-minute arrival window. Self-contained van — no hose, no power needed.
            </:item>
            <:item number="3" title="Pay when done">
              No deposit. Card charged after the job. Photos before and after for your records.
            </:item>
          </.feature_grid>
        </div>
      </section>

      <%!-- =================== PRICING =================== --%>
      <section id="pricing" class="bg-base-200 py-12 px-4">
        <div class="max-w-4xl mx-auto">
          <div class="text-center mb-8">
            <div class="text-xs font-semibold uppercase tracking-wide text-base-content/60 mb-1">
              PRICING
            </div>
            <h2 class="text-2xl font-bold text-base-content tracking-tight">
              Two tiers. No hidden fees.
            </h2>
          </div>
          <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <.service_tier_card
              :if={@basic}
              name="Basic Wash"
              price="$50"
              duration="~45 min"
              features={[
                "Exterior hand wash",
                "Wheels & tires",
                "Window streak-free finish",
                "Quick interior vacuum"
              ]}
            >
              <:cta>
                <.link navigate={~p"/booking?tier=basic_wash"} class="btn btn-outline w-full">
                  Book Basic
                </.link>
              </:cta>
            </.service_tier_card>

            <.service_tier_card
              :if={@premium}
              name="Premium"
              price="$199.99"
              duration="~3 hours"
              highlighted={true}
              features={[
                "Everything in Basic",
                "Full interior wipe-down",
                "Shampoo carpets & seats",
                "Leather treatment",
                "Tire shine + wax coat",
                "Engine bay detail"
              ]}
            >
              <:cta>
                <.link navigate={~p"/booking?tier=deep_clean_detail"} class="btn btn-primary w-full">
                  Book Premium
                </.link>
              </:cta>
            </.service_tier_card>
          </div>
        </div>
      </section>

      <%!-- =================== TECH SECTION =================== --%>
      <.tech_section
        headline="We tell you exactly when we'll arrive."
        subhead="Most mobile washes give you a 4-hour window. We give you 15 minutes — and SMS the moment we're 5 minutes out."
        bullets={[
          "→ 15-minute arrival windows, not \"morning\" or \"afternoon\"",
          "→ Live SMS updates as your tech approaches",
          "→ Photos of your car before and after every wash"
        ]}
      >
        <:preview>
          <div class="bg-slate-800 border border-slate-700 rounded-lg p-4 font-mono text-xs text-slate-300 space-y-3">
            <div>
              <div class="text-slate-500 mb-1">Driveway · 9:42 AM</div>
              <div class="text-cyan-400">Driveway:</div>
              <div>Hi Maria — Jordan is 8 minutes away. He'll text again when he's pulling up. 🚐</div>
            </div>
            <div>
              <div class="text-slate-500 mb-1">Driveway · 9:50 AM</div>
              <div class="text-cyan-400">Driveway:</div>
              <div>Pulling into your driveway now. Wash should take about 45 min.</div>
            </div>
          </div>
        </:preview>
      </.tech_section>

      <%!-- =================== TESTIMONIALS =================== --%>
      <section class="bg-base-200 py-12 px-4">
        <div class="max-w-6xl mx-auto">
          <div class="text-center mb-8">
            <h2 class="text-2xl font-bold text-base-content tracking-tight">
              What customers say
            </h2>
          </div>
          <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            <%!-- COPY: TBD - replace with real customer quote pre-launch --%>
            <.testimonial
              quote="Showed up exactly on time and my car looked brand new. Worth every penny."
              name="Maria G."
              vehicle="2023 Tesla Model 3"
            />
            <%!-- COPY: TBD - replace with real customer quote pre-launch --%>
            <.testimonial
              quote="I work from home and didn't even have to stop my Zoom call. They just did their thing in the driveway."
              name="Marcus T."
              vehicle="2021 Toyota 4Runner"
            />
            <%!-- COPY: TBD - replace with real customer quote pre-launch --%>
            <.testimonial
              quote="The detail job on my truck was unreal. Carpets I'd written off look new again."
              name="Brittany R."
              vehicle="2018 Ford F-150"
            />
          </div>
        </div>
      </section>

      <%!-- =================== FINAL CTA =================== --%>
      <.cta_band
        headline="Ready for a clean car without the trip?"
        subhead="First wash, no commitment. Book in 30 seconds."
      >
        <:cta>
          <.link navigate={~p"/booking"} class="btn btn-primary">
            Book my first wash →
          </.link>
        </:cta>
      </.cta_band>

      <%!-- =================== FOOTER =================== --%>
      <footer class="bg-base-200 border-t border-base-300 py-6 px-4">
        <div class="max-w-7xl mx-auto flex flex-col sm:flex-row items-center justify-between gap-3 text-xs text-base-content/60">
          <div>© 2026 Driveway Detail Co. LLC · San Antonio, TX · Veteran-owned</div>
          <div class="flex items-center gap-4">
            <a href={~p"/privacy"} class="hover:text-base-content">Privacy</a>
            <a href={~p"/terms"} class="hover:text-base-content">Terms</a>
            <a href={~p"/sign-in"} class="hover:text-base-content">Sign in</a>
          </div>
        </div>
      </footer>
    </div>
    """
  end
```

**Note about routes:** the new template uses `~p"/sign-in"`, `~p"/privacy"`, `~p"/terms"`, `~p"/booking"`. If any of these routes don't exist in `router.ex`, the verified-routes macro will raise at compile time. Check existing routes first (run `grep -E 'live "/sign-in"|live "/booking"|get "/privacy"|get "/terms"' lib/mobile_car_wash_web/router.ex`) and adjust:
- If `/booking` is actually `/book` in the router, use `~p"/book"` instead.
- If `/sign-in` doesn't exist (e.g., it's `/signin` or `/users/sign-in`), use the existing path.
- If `/terms` doesn't exist, use a placeholder href or comment out the link.

The router state is what it is — adapt the template to what exists, don't add new routes here.

- [ ] **Step 4: Verify compile**

Run: `mix compile --warnings-as-errors 2>&1 | tail -10`
Expected: clean. Common failures:
- `~p"/some-route"` doesn't match a router entry → use the actual path
- `@subscription_plans` referenced somewhere we forgot → remove
- Any helper component in the OLD render that's no longer called → leave as dead code for now (Task 9 cleans up)

- [ ] **Step 5: SKIP — controller will run full `mix test` after Task 9**

- [ ] **Step 6: Commit**

```bash
git add lib/mobile_car_wash_web/live/landing_live.ex
git commit -m "marketing: rewrite landing_live render template against MarketingComponents

Top nav (logo + sign in + Book a wash CTA), hero, How It Works grid,
2-tier pricing (Basic + Premium highlighted), dark tech credibility
section with SMS preview, testimonials grid (3 placeholders flagged
for pre-launch replacement), final CTA band, minimal footer.

All copy locked from spec. Routes use existing /booking, /sign-in,
/privacy, /terms paths."
```

---

## Task 9: Add structural test for the new landing page

**Files:**
- Create: `test/mobile_car_wash_web/live/landing_live_test.exs`

The current codebase has no direct landing test (only `seo_test.exs` covers JSON-LD + canonical). Plan 3a adds a structural test asserting the new sections render.

- [ ] **Step 1: Write the test file**

Create `test/mobile_car_wash_web/live/landing_live_test.exs`:

```elixir
defmodule MobileCarWashWeb.LandingLiveTest do
  use MobileCarWashWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  describe "landing page" do
    test "renders hero with headline and trust badge", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/")

      assert html =~ "Your car, washed where you parked it."
      assert html =~ "SAN ANTONIO"
      assert html =~ "Book my first wash"
    end

    test "renders How It Works section with 3 steps", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/")

      assert html =~ "HOW IT WORKS"
      assert html =~ "Three steps. No hose hookup."
      assert html =~ "Book online"
      assert html =~ "We come to you"
      assert html =~ "Pay when done"
    end

    test "renders pricing section with both tier names and prices", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/")

      assert html =~ "PRICING"
      assert html =~ "Two tiers. No hidden fees."
      assert html =~ "Basic Wash"
      assert html =~ "$50"
      assert html =~ "Premium"
      assert html =~ "$199.99"
      assert html =~ "MOST POPULAR"
    end

    test "renders tech section with SMS preview content", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/")

      assert html =~ "We tell you exactly when we&#39;ll arrive."
      assert html =~ "15 minutes"
      assert html =~ "Jordan is 8 minutes away"
    end

    test "renders 3 testimonials", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/")

      assert html =~ "What customers say"
      assert html =~ "Maria G."
      assert html =~ "Marcus T."
      assert html =~ "Brittany R."
    end

    test "renders final CTA band and footer", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/")

      assert html =~ "Ready for a clean car without the trip?"
      assert html =~ "© 2026 Driveway Detail Co. LLC"
      assert html =~ "Veteran-owned"
    end

    test "links to booking page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/")

      # Multiple "Book ..." CTAs throughout the page should link to /booking
      # (or /book — depends on router; test the substring that's stable)
      assert html =~ "/booking" or html =~ "/book"
    end
  end
end
```

**Note on the booking-route assertion (last test):** depends on what `~p"/booking"` actually resolves to. If your router has `live "/book", BookingLive`, the rendered HTML contains `/book` not `/booking` — adjust the assertion. The `or` fallback handles both.

- [ ] **Step 2: Run the test**

Run: `mix test test/mobile_car_wash_web/live/landing_live_test.exs 2>&1 | tail -10`
Expected: 7 tests pass.

If any test fails because the assertion doesn't match what was rendered, adjust the assertion to the rendered text rather than tweaking the production template (the spec's drafted copy is authoritative).

- [ ] **Step 3: Commit**

```bash
git add test/mobile_car_wash_web/live/landing_live_test.exs
git commit -m "marketing: add structural landing-page test (7 sections covered)"
```

---

## Task 10: Final verification

**Files:** none modified.

- [ ] **Step 1: Run full project test suite**

Run: `mix test 2>&1 | tail -3`
Expected: at least 1024 tests (1017 baseline + 15 marketing components + 7 landing tests = 1039, give or take), 0 failures.

If any tests in `test/mobile_car_wash_web/live/seo_test.exs` fail, that's a real regression — the new landing must still emit the LocalBusiness JSON-LD and canonical link. Inspect the failing assertions:
- `LocalBusiness JSON-LD on /` — was the JSON-LD `<script>` block accidentally dropped from `landing_live.ex`? It was originally rendered by the old template; the new template above does NOT render JSON-LD inline (it's in `root.html.heex`). If JSON-LD lived in the old template body, you'll need to either move it to `root.html.heex` or restore it in the new landing template.
- `homepage canonical resolves to bare domain` — handled by `root.html.heex`, untouched. Should still pass.

- [ ] **Step 2: Run compile + format checks**

```bash
mix compile --warnings-as-errors 2>&1 | tail -3
mix format --check-formatted 2>&1 | tail -3
```
Both should be clean. If format flags issues, run `mix format` and add a follow-up commit.

- [ ] **Step 3: Boot dev server and smoke-test the landing page**

Run: `mix phx.server` (separate terminal)
Open `http://localhost:4000/` in a browser. Confirm:
- Top nav shows logo + "Sign in" + "Book a wash" button
- Hero renders with the new headline and trust badge
- "How It Works" 3-step grid renders correctly
- Pricing tiers render side-by-side desktop, stack on mobile (resize browser to confirm)
- Premium card has the cyan border + "MOST POPULAR" badge
- Tech section is dark with cyan glow; SMS preview readable
- 3 testimonials render in a row (or stack on mobile)
- Final CTA band centered with primary button
- Footer single row with copyright + 3 links

Also click the "Book a wash" / "Book my first wash" / "Book Basic" / "Book Premium" CTAs — each should navigate to the booking page (or whatever the router resolves `~p"/booking"` to). If any 404s, the route in the template doesn't match the router.

Stop the server (Ctrl-C) when done.

- [ ] **Step 4: Confirm git log**

Run: `git log --oneline main..HEAD | head -15` (or `git log --oneline -15` if working on main)
You should see 9 commits from Plan 3a (Tasks 1-9). All with descriptive messages.

- [ ] **Step 5: Report Plan 3a complete**

Summary:
- 6 marketing components (`hero`, `service_tier_card`, `tech_section`, `testimonial`, `cta_band`, `feature_grid`) with 15 tests
- Landing page rewritten against new components
- Drafted copy from spec rendered as-is (3 testimonials marked TBD for pre-launch replacement)
- Subscription plan load dropped from `mount/3`
- 7 new structural landing tests
- Existing SEO tests still passing

Recommend the user open `/` in a browser and visually approve before promoting. Plan 3b (booking) and 3c (success) are still ahead.

---

## What's NOT in Plan 3a (reminder)

These are explicitly deferred:

- Booking page redesign → **Plan 3b**
- Booking success page redesign → **Plan 3c**
- Real testimonial copy (3 placeholders ship; user replaces pre-launch)
- Sign-in / register / subscription manage page redesigns
- Mobile sticky CTA, A/B testing framework
- Smooth-scroll CSS for `#pricing` anchor (one-line follow-up)
- Subscription plan promotion on landing
