# Plan 4: Cash Flow Page Redesign — Design

**Date:** 2026-04-28
**Status:** Approved, ready for implementation plan
**Predecessor:** Plan 3c (`/book/success` redesign)
**Successor:** Plan 5 (Wallaby integration)

---

## Goal

Redesign the admin cash-flow page to match the Phase-1 visual language (modern navy + cyan palette, Inter typography, JetBrains Mono for figures, no emoji-laden gradients), split the 1,385-LOC `CashFlowLive` into Dashboard + Projections LiveViews so each is focused, and add a regression test net for the heretofore-untested page.

## Non-Goals

- Changes to business logic (`MobileCarWash.CashFlow`, `Engine`, `Projections`, `Broadcaster`, `Config`, `Account`, `Transaction`) — pure web-layer refactor.
- Mobile redesign of the SVG bucket diagram — desktop/tablet tool, stays mostly unchanged on phones via `viewBox` scaling. Phone overflow is a follow-up.
- Component extraction beyond what's already in `cash_flow_components.ex`.
- Ash policy / authorization changes.
- Analytics / event tracking changes.
- Any change to the projections math itself.

---

## Architecture

### Route split

Both routes live under the existing `:require_admin` admin scope (current scope contains line `live "/cash-flow", CashFlowLive`):

```elixir
# lib/mobile_car_wash_web/router.ex (admin scope)
live "/cash-flow", CashFlowLive
live "/cash-flow/projections", CashFlowProjectionsLive   # NEW
```

Full URLs:
- `/admin/cash-flow` → Dashboard (current SVG diagram + action buttons + thresholds + transactions)
- `/admin/cash-flow/projections` → Projections (the form + result panel that today lives behind the "Projections" tab)

### File responsibilities

**Modified:**
- `lib/mobile_car_wash_web/live/admin/cash_flow_live.ex` — Dashboard only. Strip projections-related state, event handlers, render branches. Estimated post-edit size: ~700 LOC (from 1,385).
- `lib/mobile_car_wash_web/live/admin/components/cash_flow_components.ex` — Restyle bucket diagram + sub-components for the modernized semantic palette. Same export surface; both LiveViews import it.

**New:**
- `lib/mobile_car_wash_web/live/admin/cash_flow_projections_live.ex` — Projections page. Owns `proj_actuals`, `proj_inputs`, `projections`, `editing_field` assigns and the four projection event handlers (`adjust_projection`, `edit_field`, `commit_field`, `reset_projection`). Also subscribes to `CashFlow.Broadcaster` so updates while editing trigger a refresh — same pattern as today, just lifted into the new module. Estimated size: ~500 LOC.

### No tab bar

The current "tabs tabs-boxed" element with `phx-click="switch_view"` is removed. Each page has a small header navigation:
- Dashboard's header: "Projections →" link in the top-right (tertiary button styling).
- Projections' header: "← Back to Dashboard" link in the top-left (tertiary button styling).

The `switch_view` event handler is removed entirely.

### PubSub continuity

Both LiveViews subscribe to `MobileCarWash.CashFlow.Broadcaster` on mount when `connected?(socket)` is true. Each handles `:cash_flow_updated` (re-fetch balances, schedule a `:clear_animations` Process.send_after) and `:clear_animations` (drop active flow animations). Behavior is byte-identical to today; the only difference is the event lives in two modules instead of one.

---

## Visual Treatment

### Header (both pages)

Slim brand band, ~64-80 px tall:

```heex
<div class="bg-base-300 border-b border-cyan-500/30">
  <div class="max-w-7xl mx-auto px-4 py-5 flex items-center justify-between">
    <div class="flex items-center gap-3">
      <.icon name="hero-banknotes" class="h-6 w-6 text-cyan-500" />
      <div>
        <h1 class="text-2xl font-bold text-base-content">Cash Flow</h1>
        <p class="text-xs text-base-content/60">5-bucket money flow</p>
      </div>
    </div>
    <%!-- Right side: page-specific nav link --%>
    <.link navigate={~p"/admin/cash-flow/projections"} class="btn btn-ghost btn-sm">
      Projections →
    </.link>
  </div>
</div>
```

No gradient. No emoji. Drop the `from-primary-700 to-primary-900` block. Drop the `💰` and `📋` and `⚙️` from titles and button labels — replace with Heroicons where the icon adds value, drop where it doesn't.

### Bucket diagram

The SVG itself stays — same layout, same flow arrows, same animations. Only fills, strokes, and label colors change.

**Modernized semantic palette** (inline `style` attributes on SVG elements; SVG can't take Tailwind classes directly):

> **As implemented:** the 5-distinct-color table below was narrowed during planning — the actual `cash_flow_components.ex` shares colors across buckets (3 colors + a navy fallback). See the implementation plan's `## Spec Correction: Color Mapping` section in `docs/superpowers/plans/2026-04-28-plan4-cash-flow-redesign.md` for the mapping that shipped.

| Bucket | Old hex | New | Tailwind v4 token |
|---|---|---|---|
| Operating Income | `#27AE60` | `#059669` | `emerald-600` |
| Tax | `#E8A03C` (amber) | `#ef4444` | `red-500` |
| Owner Pay (Personal Salary) | `#3A7CA5` | `#0284c7` | `sky-600` |
| Profit (Business Savings / Investment) | `#F0AD4E` | `#f59e0b` | `amber-500` |
| Operating Expenses | `#1E2A38` | `#334155` | `slate-700` |

> **Note for the implementer:** `cash_flow_components.ex` likely declares these colors in module attributes or component attrs. Find the source of truth (constant, attr default, etc.) and update there. If the colors are scattered across the file, do a targeted grep/replace and verify with `git diff`.

Cyan stays reserved as the brand accent — used for the page header icon, the navigation link, form focus rings, and the animation-toggle. It does NOT appear in the diagram itself.

**Card wrapping the SVG:**

Replace `card bg-gradient-to-br from-secondary-50 to-tertiary-50 shadow-2xl border border-tertiary-200 rounded-2xl` with:

```heex
<div class="bg-base-100 ring-1 ring-base-300 rounded-2xl p-6 mb-6">
  <div class="flex items-center justify-between mb-4">
    <h2 class="text-lg font-semibold text-base-content">5-bucket cash flow</h2>
    <label class="label cursor-pointer gap-3">
      <span class="label-text font-medium text-base-content/70">Enable animations</span>
      <input type="checkbox" class="toggle toggle-primary"
             checked={@animations_enabled} phx-click="toggle_animations" />
    </label>
  </div>
  <.bucket_diagram ... />
</div>
```

### Action button row

Replace inline `style="background-color: #..."` with daisyUI semantic button classes + Heroicons. Each button keeps its existing `phx-click` and `phx-value-modal`.

```heex
<div class="flex flex-wrap gap-3 mb-8">
  <button type="button" class="btn btn-success btn-sm"
          phx-click="open_modal" phx-value-modal="deposit">
    <.icon name="hero-plus-circle" class="h-4 w-4" />
    Record Income
  </button>
  <button type="button" class="btn btn-error btn-sm"
          phx-click="open_modal" phx-value-modal="withdrawal">
    <.icon name="hero-minus-circle" class="h-4 w-4" />
    Record Expense
  </button>
  <button type="button" class="btn btn-warning btn-sm"
          phx-click="open_modal" phx-value-modal="transfer">
    <.icon name="hero-arrow-path-rounded-square" class="h-4 w-4" />
    Rebalance to Expense
  </button>
  <button type="button" class="btn btn-info btn-sm"
          phx-click="pay_salary">
    <.icon name="hero-banknotes" class="h-4 w-4" />
    Pay Salary
  </button>
  <button type="button" class="btn btn-neutral btn-sm"
          phx-click="open_modal" phx-value-modal="config">
    <.icon name="hero-cog-6-tooth" class="h-4 w-4" />
    Settings
  </button>
</div>
```

### Threshold cards (3-card grid)

Drop gradient backgrounds + colored borders. Each card has a flat `bg-base-100`, a thin neutral ring, semantic icon + label, mono-font number in the matching semantic color.

```heex
<div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4 mb-8">
  <div class="bg-base-100 ring-1 ring-base-300 rounded-xl p-6">
    <div class="flex items-center gap-2 mb-3">
      <.icon name="hero-currency-dollar" class="h-4 w-4 text-emerald-600" />
      <span class="text-xs uppercase tracking-wide font-semibold text-base-content/70">
        Expense threshold
      </span>
    </div>
    <div class="text-2xl font-mono font-bold text-emerald-600">
      ${format_cents(@thresholds.expense)}
    </div>
    <div class="text-xs text-base-content/60 mt-1">= Monthly Opex × 1.25</div>
  </div>

  <%!-- Savings threshold + Investment target follow same pattern with sky-600 / amber-500 --%>
</div>
```

### Recent transactions table

```heex
<div class="bg-base-100 ring-1 ring-base-300 rounded-2xl p-6">
  <h2 class="text-2xl font-bold text-base-content mb-4">Recent Transactions</h2>
  <div class="overflow-x-auto">
    <table class="w-full text-sm">
      <thead>
        <tr class="border-b border-base-300">
          <th class="text-left py-2 px-3 font-semibold text-base-content/80">Type</th>
          <th class="text-right py-2 px-3 font-semibold text-base-content/80">Amount</th>
          <th class="text-left py-2 px-3 font-semibold text-base-content/80">Description</th>
          <th class="text-left py-2 px-3 font-semibold text-base-content/80">Date</th>
        </tr>
      </thead>
      <tbody>
        <%= for txn <- @transactions do %>
          <tr class="border-b border-base-200">
            <td class="py-2 px-3">{txn.type}</td>
            <td class="py-2 px-3 text-right font-mono">${format_cents(txn.amount_cents)}</td>
            <td class="py-2 px-3 text-base-content/80">{txn.description}</td>
            <td class="py-2 px-3 text-base-content/60">{format_date(txn.inserted_at)}</td>
          </tr>
        <% end %>
      </tbody>
    </table>
    <p :if={@transactions == []} class="text-base-content/60 py-6 text-center">
      No transactions yet.
    </p>
  </div>
</div>
```

(Implementer should grep the existing render to confirm the assign name for transactions — it may be `@accounts.transactions` or similar. Don't invent a new name; use what's already there.)

### Modals

The daisyUI `modal` shell stays. Inside each modal:

- Form labels use Inter (already inherited from app theme).
- Inputs use the existing form-control pattern from the booking redesign.
- Drop any custom hex / gradient inside modal bodies. Replace with `bg-base-100`.
- Submit buttons use `btn-success` (deposit), `btn-error` (withdrawal), `btn-warning` (transfer), `btn-neutral` (config). Cancel buttons use `btn-ghost`.
- Modal headers drop emoji (`💰`, etc.) — use Heroicons or just a plain text title.

### Projections page

Same header treatment. Page body:

- **Form section** — 1-col mobile, 2-col `sm:`. Each input row:
  - Label in xs uppercase tracking-wide muted (e.g., "Monthly Operating Income")
  - Number input with `font-mono` text class. `inputmode="numeric"`.
  - Tiny ghost button "Reset to actual" if the field has been edited (i.e., diverges from `proj_actuals`).
- **Result panel** — Card showing projected end-of-period balances per bucket, in the bucket palette colors. Title "Projected balances after 12 months" in lg semibold. Each row: bucket name + mono dollar amount in semantic color.

The inline-edit-on-click pattern (current `editing_field` assign + `edit_field` / `commit_field` events) is preserved — just restyled.

---

## Tests

### `test/mobile_car_wash_web/live/admin/cash_flow_live_test.exs` (new)

```elixir
defmodule MobileCarWashWeb.Admin.CashFlowLiveTest do
  use MobileCarWashWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias MobileCarWash.Accounts.Customer
  # ... admin sign-in helper following existing admin test patterns
end
```

Cases:
1. Mount renders without crashing for an admin user; non-admin redirected to a safe page (covers existing `:require_admin` plug).
2. Page title is "Cash Flow"; header copy "5-bucket money flow" appears.
3. All 5 buckets render with their balance amounts (data assigns wired correctly — assert each bucket label and balance text appears).
4. Threshold cards render the three numbers from `@thresholds.expense`, `@thresholds.business_savings`, `@config.investment_target_cents`.
5. All 5 action buttons render with expected labels: "Record Income", "Record Expense", "Rebalance to Expense", "Pay Salary", "Settings".
6. Animation toggle event flips `@animations_enabled` (`render_click(view, "toggle_animations") =~ ...` flow).
7. "Open income modal" event renders the modal; close event hides it (one happy-path event handler smoke test).
8. Recent transactions table renders rows when transactions exist; empty state shows otherwise.
9. "Projections →" link href points at `/admin/cash-flow/projections`.

### `test/mobile_car_wash_web/live/admin/cash_flow_projections_live_test.exs` (new)

Cases:
1. Mount renders without crashing for an admin user; non-admin redirected.
2. `proj_actuals`, `proj_inputs`, `projections` are loaded on mount (no longer lazy).
3. "← Back to Dashboard" link href points at `/admin/cash-flow`.
4. `adjust_projection` event updates `proj_inputs` and recomputes `projections`.
5. `edit_field` / `commit_field` events drive the inline-edit affordance through one round-trip.
6. `reset_projection` event clears modifications back to `proj_actuals`.

### `test/mobile_car_wash/cash_flow/projections_test.exs` (new)

Cases:
1. `Projections.compute/1` with a hand-rolled input map returns expected output keys (asserts the result map shape).
2. One numeric assertion: known input → known output. Specific values to be filled in by the implementer based on reading `lib/mobile_car_wash/cash_flow/projections.ex` — pick a clean case (e.g., income $10,000, expense $7,000, allocations at defaults → projected end-of-period profit at a specific cents value). The point is locking in current math, not validating it.
3. Projection-with-adjustment path: override one input field, assert the output differs from the actuals-only path in the expected direction.

> **Implementer note:** No tests exist today for `Projections`. Read the module first to understand its current contract. Don't refactor the module — just add tests that lock in current behavior.

---

## Acceptance Criteria

A reviewer should be able to verify:

1. Visiting `/admin/cash-flow` as an admin renders the Dashboard with: brand-band header, modernized bucket diagram in semantic colors, action button row using daisyUI tokens, three threshold cards in flat styling, recent transactions table.
2. Visiting `/admin/cash-flow/projections` as an admin renders the Projections page with: same header treatment, form section, result panel.
3. Both pages have the cross-navigation link in the header.
4. Tab bar is gone; `switch_view` event handler is removed.
5. All five action buttons open their modals correctly. Modals submit and close.
6. Animation toggle still flips animations on the bucket diagram.
7. PubSub `:cash_flow_updated` event refreshes balances on whichever page is open.
8. Projections form: editing a number field, hitting commit, recomputes and shows new projected balances. "Reset to actual" restores the original.
9. Full test suite green: `mix test` passes with the new tests.
10. No regressions in existing tests.
11. `mix compile --warnings-as-errors` passes.

---

## Files Touched (Estimate)

**Modified:**
- `lib/mobile_car_wash_web/live/admin/cash_flow_live.ex` (gut + restyle)
- `lib/mobile_car_wash_web/live/admin/components/cash_flow_components.ex` (restyle, semantic colors)
- `lib/mobile_car_wash_web/router.ex` (add projections route)

**New:**
- `lib/mobile_car_wash_web/live/admin/cash_flow_projections_live.ex`
- `test/mobile_car_wash_web/live/admin/cash_flow_live_test.exs`
- `test/mobile_car_wash_web/live/admin/cash_flow_projections_live_test.exs`
- `test/mobile_car_wash/cash_flow/projections_test.exs`

---

## Risk Callouts

- **The split is the load-bearing risk.** Splitting a 1,385-LOC LiveView with no prior test coverage means subtle assigns/event-handler bugs can slip through. The character tests will catch most, but not all. Plan calls for a careful read-through of the diff before merge and a manual smoke check in the dev server.
- **PubSub on both pages.** Both LiveViews subscribe to `CashFlow.Broadcaster`. Verify both handle `:cash_flow_updated` and `:clear_animations` correctly. The current code in `cash_flow_live.ex` lines 305-330 has the handlers; both new modules need them.
- **Inline SVG color attributes.** SVG fills can't take Tailwind classes — they need either inline `style` attributes or hex literals. Audit the components file to find the existing color source of truth and update once, not in many places.
- **Modal shell continuity.** The modals are real Phoenix LiveView modals with form state. Restyling must preserve the form behavior (CSRF tokens, phx-submit, validation states). Don't rewrite — only restyle wrappers and inputs.

---

## Out of Scope (Explicitly)

- Wallaby / E2E tests — Plan 5.
- Mobile-screen redesign of the SVG bucket diagram.
- Refactoring `Projections` math.
- Component extraction beyond `cash_flow_components.ex`.
- Removing or renaming `MobileCarWash.CashFlow` domain modules.
- Changing the `:require_admin` plug or admin auth.

---

## Approval & Implementation Path

1. User reviews this spec → approves.
2. `superpowers:writing-plans` creates the bite-sized task plan at `docs/superpowers/plans/2026-04-28-plan4-cash-flow-redesign.md`.
3. `superpowers:using-git-worktrees` sets up `.claude/worktrees/plan4-cash-flow`.
4. `superpowers:subagent-driven-development` executes the plan task-by-task (or inline if subagents prove unreliable, as happened on Plan 3c).
5. Final code review.
6. Apply review fixes.
7. `superpowers:finishing-a-development-branch` merges back to main when green.
