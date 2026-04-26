# Phase-1, Plan 1 — Design System Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the existing navy/grey/steel-blue daisyUI theme with the Modern SaaS palette (white/slate base + navy primary `#1e293b` + cyan accent `#06b6d4` + Inter/JetBrains Mono typography). Refresh 5 existing core components and add 6 new utility components. Showcase everything in the existing `/admin` style guide page so the rest of the phase-1 work can build on a verified foundation.

**Architecture:** TDD per component. Design tokens go in `assets/css/app.css` under daisyUI's `@plugin "../vendor/daisyui-theme"` blocks (semantic theme variables) plus Tailwind `@theme` raw color stops (so `bg-cyan-500`, `text-slate-900` etc. work directly). Components live in the existing `lib/mobile_car_wash_web/components/core_components.ex` — no new modules in Plan 1 (`marketing_components.ex` lands in Plan 3). Component tests live in `test/mobile_car_wash_web/components/core_components_test.exs` (new file).

**Tech Stack:** Phoenix LiveView 1.x, Tailwind CSS v4 (with `@theme` + `@plugin` directives), daisyUI 5.x, Phoenix.Component, ExUnit, `Phoenix.LiveViewTest.rendered_to_string/1` for component testing.

**Spec reference:** [docs/superpowers/specs/2026-04-26-phase1-redesign-and-wallaby-design.md](docs/superpowers/specs/2026-04-26-phase1-redesign-and-wallaby-design.md) — see "Design system" section.

**File map for this plan:**
- Modify: `.gitignore`
- Modify: `assets/css/app.css` (replace `@plugin "../vendor/daisyui-theme"` blocks for both light + dark; add Inter / JetBrains Mono font-family vars)
- Modify: `lib/mobile_car_wash_web/components/layouts/root.html.heex` (add Google Fonts links)
- Modify: `lib/mobile_car_wash_web/components/core_components.ex` (refresh `button`, `input`/`select`/`textarea`, `flash`, `table`, `header`; add `modal`, `status_pill`, `progress_bar`, `empty_state`, `kpi_card`, `bucket_card`)
- Modify: `lib/mobile_car_wash_web/live/admin/style_guide_live.ex` (showcase everything)
- Create: `test/mobile_car_wash_web/components/core_components_test.exs`

**Substitution from spec:** Spec lists `<.data_table>` as a new component. This plan instead refreshes the existing `<.table>` (line 356 of core_components.ex) since it already covers the same use case — a data row table with column slots. Adding both would be redundant. If a future plan finds `<.table>` insufficient, `<.data_table>` can be added then.

**Out of scope for Plan 1 (deferred to Plans 2-5):**
- Brand assets (logos, OG, favicons, emails) — Plan 2
- Cash flow page redesign — Plan 4
- Customer-facing redesigns + `marketing_components.ex` — Plan 3
- Wallaby integration + 5 E2E tests — Plan 5

---

## Task 0: Pre-flight verification

**Files:** none modified — read-only verification.

- [ ] **Step 1: Verify clean working tree**

Run: `git status`
Expected: `nothing to commit, working tree clean`. If not clean, stop and resolve before proceeding.

- [ ] **Step 2: Verify all existing tests pass on this branch**

Run: `mix test`
Expected: `0 failures` (~113 tests currently per project memory). If any test fails, stop and investigate — Plan 1 must start from a green baseline.

- [ ] **Step 3: Verify asset compile works**

Run: `mix assets.build`
Expected: exit 0, no compile errors. This confirms Tailwind/daisyUI compile pipeline is healthy before we mess with `app.css`.

- [ ] **Step 4: Note current test count**

Run: `mix test 2>&1 | tail -5`
Record the test count somewhere (e.g., your scratch notes). After Plan 1 finishes, count must be ≥ this baseline plus the new component tests we add.

---

## Task 1: Add `.superpowers/` to `.gitignore`

**Files:**
- Modify: `.gitignore`

- [ ] **Step 1: Inspect current .gitignore**

Run: `cat .gitignore | tail -20`
Confirm `.superpowers/` is not already listed.

- [ ] **Step 2: Append `.superpowers/` entry**

Append the following two lines to the END of `.gitignore`:

```
# Superpowers brainstorming session artifacts (mockups, events, server pids).
.superpowers/
```

- [ ] **Step 3: Verify it works**

Run: `git status --ignored | grep -c superpowers || echo "ignored ok"`
Expected: prints `ignored ok` (or a count of ignored files). The `.superpowers/` directory should no longer appear in `git status`.

- [ ] **Step 4: Commit**

```bash
git add .gitignore
git commit -m "chore: gitignore .superpowers/ brainstorming artifacts"
```

---

## Task 2: Add Inter + JetBrains Mono web fonts

**Files:**
- Modify: `lib/mobile_car_wash_web/components/layouts/root.html.heex`

Per spec: Inter for all UI text (display/section/body/label) and JetBrains Mono for financial figures only.

- [ ] **Step 1: Read current root layout `<head>`**

Run: `head -40 lib/mobile_car_wash_web/components/layouts/root.html.heex`
Identify where the existing `<link>` and `<script>` tags live so the font preload + stylesheet links can be added in the same area.

- [ ] **Step 2: Add font preconnect + stylesheet links to `<head>`**

Insert these tags inside the `<head>` block, BEFORE the existing CSS link (so fonts start downloading early):

```heex
<link rel="preconnect" href="https://fonts.googleapis.com" />
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
<link
  href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=JetBrains+Mono:wght@500;600;700&display=swap"
  rel="stylesheet"
/>
```

- [ ] **Step 3: Boot the dev server and visually verify fonts load**

Run: `mix phx.server` (separate terminal)
Open: `http://localhost:4000` in a browser. Open DevTools → Network → Fonts. Confirm Inter and JetBrainsMono `.woff2` files load with HTTP 200. The page text won't look different yet (the CSS doesn't reference these fonts until Task 3).

Stop the server with Ctrl-C when done verifying.

- [ ] **Step 4: Commit**

```bash
git add lib/mobile_car_wash_web/components/layouts/root.html.heex
git commit -m "ui: load Inter + JetBrains Mono web fonts in root layout"
```

---

## Task 3: Replace daisyUI theme + Tailwind tokens with Modern SaaS palette

**Files:**
- Modify: `assets/css/app.css`

Tokens replace the existing navy/grey/steel-blue palette with white/slate + navy + cyan, plus point `--font-sans` and a new `--font-mono` at the loaded webfonts.

- [ ] **Step 1: Read current app.css to locate the blocks to replace**

Run: `grep -n '^@theme\|^@plugin' assets/css/app.css`
You should see one `@theme` block, one `@plugin "../vendor/heroicons"`, one `@plugin "../vendor/daisyui"`, and two `@plugin "../vendor/daisyui-theme"` blocks (one for "dark", one for the default light theme).

- [ ] **Step 2: Replace the `@theme` block at the top of app.css**

Find the block beginning `@theme {` and ending `}` (the one that defines `--color-primary-50` through `--color-tertiary-900`). Replace its ENTIRE body with:

```css
@theme {
  /* Webfonts loaded in root layout */
  --font-sans: "Inter", ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont,
    "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
  --font-mono: "JetBrains Mono", ui-monospace, SFMono-Regular, "SF Mono",
    Menlo, Monaco, Consolas, monospace;

  /* Brand palette — Modern SaaS reboot */
  --color-surface:   #f8fafc;
  --color-card:      #ffffff;
  --color-ink:       #0f172a;
  --color-primary:   #1e293b;
  --color-accent:    #06b6d4;

  /* Slate ramp (Tailwind-compatible — usable as bg-slate-500 etc.) */
  --color-slate-50:  #f8fafc;
  --color-slate-100: #f1f5f9;
  --color-slate-200: #e2e8f0;
  --color-slate-300: #cbd5e1;
  --color-slate-400: #94a3b8;
  --color-slate-500: #64748b;
  --color-slate-600: #475569;
  --color-slate-700: #334155;
  --color-slate-800: #1e293b;
  --color-slate-900: #0f172a;

  /* Cyan ramp */
  --color-cyan-50:  #ecfeff;
  --color-cyan-100: #cffafe;
  --color-cyan-200: #a5f3fc;
  --color-cyan-300: #67e8f9;
  --color-cyan-400: #22d3ee;
  --color-cyan-500: #06b6d4;
  --color-cyan-600: #0891b2;
  --color-cyan-700: #0e7490;
  --color-cyan-800: #155e75;
  --color-cyan-900: #164e63;

  /* Semantic */
  --color-success: #16a34a;
  --color-warning: #f59e0b;
  --color-danger:  #dc2626;
  --color-info:    #0e7490;
}
```

- [ ] **Step 3: Replace the LIGHT daisyUI theme block**

Find the `@plugin "../vendor/daisyui-theme"` block whose `name:` is the default/light one (NOT `name: "dark"`). Replace its body with:

```css
@plugin "../vendor/daisyui-theme" {
  name: "light";
  default: true;
  prefersdark: false;
  color-scheme: "light";

  /* Surfaces */
  --color-base-100: #ffffff;     /* card */
  --color-base-200: #f8fafc;     /* page background */
  --color-base-300: #e2e8f0;     /* borders / dividers */
  --color-base-content: #0f172a; /* ink (body text) */

  /* Brand */
  --color-primary: #1e293b;
  --color-primary-content: #ffffff;
  --color-secondary: #475569;
  --color-secondary-content: #ffffff;
  --color-accent: #06b6d4;
  --color-accent-content: #ffffff;
  --color-neutral: #0f172a;
  --color-neutral-content: #f8fafc;

  /* Semantic */
  --color-info: #0e7490;
  --color-info-content: #ffffff;
  --color-success: #16a34a;
  --color-success-content: #ffffff;
  --color-warning: #f59e0b;
  --color-warning-content: #ffffff;
  --color-error: #dc2626;
  --color-error-content: #ffffff;

  /* Geometry */
  --radius-selector: 0.5rem;
  --radius-field: 0.5rem;
  --radius-box: 0.75rem;
  --size-selector: 0.25rem;
  --size-field: 0.25rem;
  --border: 1px;
  --depth: 1;
  --noise: 0;
}
```

- [ ] **Step 4: Replace the DARK daisyUI theme block**

Find the block beginning `@plugin "../vendor/daisyui-theme" {` with `name: "dark";`. Replace its body with:

```css
@plugin "../vendor/daisyui-theme" {
  name: "dark";
  default: false;
  prefersdark: true;
  color-scheme: "dark";

  /* Surfaces — slate-900 base */
  --color-base-100: #0f172a;
  --color-base-200: #1e293b;
  --color-base-300: #334155;
  --color-base-content: #f1f5f9;

  /* Brand */
  --color-primary: #06b6d4;          /* cyan pops on dark */
  --color-primary-content: #0f172a;
  --color-secondary: #334155;
  --color-secondary-content: #f1f5f9;
  --color-accent: #22d3ee;
  --color-accent-content: #0f172a;
  --color-neutral: #f8fafc;
  --color-neutral-content: #0f172a;

  /* Semantic */
  --color-info: #22d3ee;
  --color-info-content: #0f172a;
  --color-success: #16a34a;
  --color-success-content: #f8fafc;
  --color-warning: #f59e0b;
  --color-warning-content: #0f172a;
  --color-error: #dc2626;
  --color-error-content: #f8fafc;

  --radius-selector: 0.5rem;
  --radius-field: 0.5rem;
  --radius-box: 0.75rem;
  --size-selector: 0.25rem;
  --size-field: 0.25rem;
  --border: 1px;
  --depth: 1;
  --noise: 0;
}
```

- [ ] **Step 5: Verify Tailwind compiles**

Run: `mix assets.build`
Expected: exit 0, no errors. If you see "unknown utility" or similar, the CSS syntax is off — re-check the blocks.

- [ ] **Step 6: Boot dev server, verify visually**

Run: `mix phx.server`
Open `http://localhost:4000`. The whole site should now render in the new palette: white/slate background, navy primary buttons, cyan accents, Inter font.

Specifically check:
- Body text is Inter (compare against the Inter sample on `https://rsms.me/inter/`)
- Page background is `#f8fafc` (slate-50, very light cool grey — not pure white)
- Any visible buttons are navy `#1e293b` with white text

If colors look wrong (e.g., pages still show old navy gradient), do a hard reload (Cmd-Shift-R / Ctrl-Shift-R).

Stop the server.

- [ ] **Step 7: Commit**

```bash
git add assets/css/app.css
git commit -m "ui: swap daisyUI theme + Tailwind palette to Modern SaaS reboot

White/slate base, navy primary (#1e293b), cyan accent (#06b6d4),
Inter typography, JetBrains Mono for financial figures.
Both light and dark themes updated."
```

---

## Task 4: Verify existing test suite passes against new tokens

**Files:** none modified.

The token swap should NOT break behavioral tests, but it may break tests that assert specific class names from the OLD palette (e.g., a test asserting `text-primary-700` would fail since that class is gone).

- [ ] **Step 1: Run full suite**

Run: `mix test`
Expected: most tests pass. Some may fail because they assert class names like `bg-primary-700`, `text-tertiary-400`, `secondary-50` etc. that no longer exist.

- [ ] **Step 2: Triage failures**

For each failure:
- If the assertion is about behavior (DB state, redirect, flash content): unrelated, investigate separately.
- If the assertion is about a stale class name: update the assertion to match the new class. Examples of expected updates:
  - `bg-primary-700` → `bg-primary` (or `bg-slate-800`)
  - `text-secondary-50` → `text-base-100` (or `text-white`)
  - `text-tertiary-400` → `text-cyan-500` (or `text-accent`)
- If you can't tell what the assertion was checking, read the LiveView/template that produced the markup and update both the rendered class and the assertion to use the new tokens consistently.

- [ ] **Step 3: Iterate until green**

Re-run `mix test` after each fix. Don't proceed to Task 5 until all tests pass.

- [ ] **Step 4: Commit fixes (if any)**

```bash
git add -p   # interactively stage just the assertion / class-name updates
git commit -m "test: update class assertions to new design tokens"
```

If no test changes were needed, skip the commit.

---

## Task 5: Refresh `button` component (TDD)

**Files:**
- Create: `test/mobile_car_wash_web/components/core_components_test.exs`
- Modify: `lib/mobile_car_wash_web/components/core_components.ex` (`button/1`, currently at line 96)

Spec: `<.button variant={:primary|:secondary|:ghost|:destructive} size={:sm|:md|:lg}>`. Current component only supports `variant: "primary"` and no size.

- [ ] **Step 1: Write failing tests**

Create `test/mobile_car_wash_web/components/core_components_test.exs` with:

```elixir
defmodule MobileCarWashWeb.CoreComponentsTest do
  use ExUnit.Case, async: true
  import Phoenix.Component
  import Phoenix.LiveViewTest
  import MobileCarWashWeb.CoreComponents

  describe "button/1" do
    test "renders primary variant by default" do
      assigns = %{}
      html = rendered_to_string(~H|<.button>Click</.button>|)
      assert html =~ ~s(class=)
      assert html =~ "btn-primary"
      assert html =~ ">Click<"
    end

    test "renders secondary variant" do
      assigns = %{}
      html = rendered_to_string(~H|<.button variant="secondary">Save</.button>|)
      assert html =~ "btn-secondary"
    end

    test "renders ghost variant" do
      assigns = %{}
      html = rendered_to_string(~H|<.button variant="ghost">Cancel</.button>|)
      assert html =~ "btn-ghost"
    end

    test "renders destructive variant" do
      assigns = %{}
      html = rendered_to_string(~H|<.button variant="destructive">Delete</.button>|)
      assert html =~ "btn-error"
    end

    test "renders size sm" do
      assigns = %{}
      html = rendered_to_string(~H|<.button size="sm">Small</.button>|)
      assert html =~ "btn-sm"
    end

    test "renders size lg" do
      assigns = %{}
      html = rendered_to_string(~H|<.button size="lg">Large</.button>|)
      assert html =~ "btn-lg"
    end

    test "renders link when navigate set" do
      assigns = %{}
      html = rendered_to_string(~H|<.button navigate="/foo">Go</.button>|)
      assert html =~ ~s(href="/foo")
    end
  end
end
```

- [ ] **Step 2: Run tests, verify they fail**

Run: `mix test test/mobile_car_wash_web/components/core_components_test.exs`
Expected: failures on `btn-secondary`, `btn-ghost`, `btn-error`, `btn-sm`, `btn-lg` not present in output. The first test (default primary) and the `navigate` test may pass — that's fine.

- [ ] **Step 3: Replace `button/1` in core_components.ex**

Replace lines 82-117 of `lib/mobile_car_wash_web/components/core_components.ex` (the entire `@doc` block + `attr` block + `def button/1`) with:

```elixir
  @doc """
  Renders a button or styled link.

  ## Examples

      <.button>Send!</.button>
      <.button variant="secondary" size="sm">Cancel</.button>
      <.button variant="destructive">Delete</.button>
      <.button navigate={~p"/"}>Home</.button>
  """
  attr :rest, :global, include: ~w(href navigate patch method download name value disabled type)
  attr :class, :any, default: nil
  attr :variant, :string, values: ~w(primary secondary ghost destructive), default: "primary"
  attr :size, :string, values: ~w(sm md lg), default: "md"
  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    variant_class =
      case assigns[:variant] do
        "primary" -> "btn-primary"
        "secondary" -> "btn-secondary"
        "ghost" -> "btn-ghost"
        "destructive" -> "btn-error"
      end

    size_class =
      case assigns[:size] do
        "sm" -> "btn-sm"
        "md" -> ""
        "lg" -> "btn-lg"
      end

    assigns =
      assign(assigns, :class, [
        "btn",
        variant_class,
        size_class,
        assigns[:class]
      ])

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@class} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button class={@class} {@rest}>
        {render_slot(@inner_block)}
      </button>
      """
    end
  end
```

- [ ] **Step 4: Run tests, verify they pass**

Run: `mix test test/mobile_car_wash_web/components/core_components_test.exs --only describe:button`
Expected: all 7 button tests pass.

- [ ] **Step 5: Run full suite to catch regressions**

Run: `mix test`
Expected: 0 failures. Existing usages of `<.button>` (no variant) still get primary; usages with `variant="primary"` still work.

- [ ] **Step 6: Commit**

```bash
git add test/mobile_car_wash_web/components/core_components_test.exs lib/mobile_car_wash_web/components/core_components.ex
git commit -m "ui: button — add secondary/ghost/destructive variants and sm/md/lg sizes"
```

---

## Task 6: Refresh `input` component (TDD)

**Files:**
- Modify: `test/mobile_car_wash_web/components/core_components_test.exs` (add describe block)
- Modify: `lib/mobile_car_wash_web/components/core_components.ex` (`input/1` family, lines 184-313)

Goal: ensure all input variants (text, select, textarea, checkbox) use the new token classes consistently — `input input-bordered`, `select select-bordered`, etc. with the new height (`h-12` ≈ 48px per spec). The existing implementation is mostly right; verify and adjust.

- [ ] **Step 1: Read current input implementation**

Run: `sed -n '184,315p' lib/mobile_car_wash_web/components/core_components.ex`
Note the existing class lists for each variant. The structural pattern (label + input + error message) is fine and stays.

- [ ] **Step 2: Add tests to test file**

Append to `test/mobile_car_wash_web/components/core_components_test.exs` BEFORE the closing `end` of the module:

```elixir
  describe "input/1" do
    test "renders text input with label" do
      assigns = %{}
      html = rendered_to_string(~H|<.input name="email" label="Email" value="" />|)
      assert html =~ ~s(name="email")
      assert html =~ "Email"
      assert html =~ "input"
      assert html =~ "input-bordered"
    end

    test "renders textarea variant" do
      assigns = %{}
      html = rendered_to_string(~H|<.input type="textarea" name="msg" label="Message" value="" />|)
      assert html =~ "<textarea"
      assert html =~ "textarea-bordered"
    end

    test "renders select variant" do
      assigns = %{}
      html = rendered_to_string(~H|<.input type="select" name="tier" label="Tier" value="basic" options={[{"Basic", "basic"}, {"Premium", "premium"}]} />|)
      assert html =~ "<select"
      assert html =~ "select-bordered"
      assert html =~ "Basic"
      assert html =~ "Premium"
    end

    test "renders checkbox variant" do
      assigns = %{}
      html = rendered_to_string(~H|<.input type="checkbox" name="agree" label="I agree" checked={false} />|)
      assert html =~ ~s(type="checkbox")
      assert html =~ "checkbox"
    end

    test "shows error messages when errors present" do
      assigns = %{}
      html = rendered_to_string(~H|<.input name="email" label="Email" value="" errors={["can't be blank"]} />|)
      assert html =~ "can&#39;t be blank"
    end
  end
```

- [ ] **Step 3: Run tests to see which already pass**

Run: `mix test test/mobile_car_wash_web/components/core_components_test.exs --only describe:input`
Triage: any failures point to mismatches between the test and the existing implementation. Options:
1. The test asserts the right thing → change the implementation to match.
2. The implementation is correct → adjust the test to reflect actual class names.

Most likely the existing `input/1` already uses `input-bordered` etc. and these tests pass on the current code. If so, you're done with this task — but proceed through the remaining steps to add the height/spacing token consistency.

- [ ] **Step 4: Update input class lists for consistent sizing**

In each `def input(...)` head that renders an actual `<input>`, `<select>`, or `<textarea>`, ensure the class list includes `h-12` for text inputs and `h-12` for selects (per spec: 48px touch targets). Find each class list (e.g., line ~290 for the default text input) and ensure it contains `"h-12"` exactly once. For textareas, use `min-h-32` instead.

Example update for the default text input class list — change from whatever's there to:

```elixir
class={[
  "input input-bordered w-full h-12 text-base",
  @errors != [] && "input-error"
]}
```

For select:

```elixir
class={[
  "select select-bordered w-full h-12 text-base",
  @errors != [] && "select-error"
]}
```

For textarea:

```elixir
class={[
  "textarea textarea-bordered w-full min-h-32 text-base",
  @errors != [] && "textarea-error"
]}
```

(Adapt to the actual file structure — the surrounding code is unchanged.)

- [ ] **Step 5: Run input tests + full suite**

Run: `mix test`
Expected: 0 failures. If a form rendering test elsewhere breaks because the input is now `h-12`, adjust the assertion.

- [ ] **Step 6: Commit**

```bash
git add test/mobile_car_wash_web/components/core_components_test.exs lib/mobile_car_wash_web/components/core_components.ex
git commit -m "ui: input/select/textarea — uniform 48px height for touch targets"
```

---

## Task 7: Refresh `flash` component (TDD)

**Files:**
- Modify: `test/mobile_car_wash_web/components/core_components_test.exs`
- Modify: `lib/mobile_car_wash_web/components/core_components.ex` (`flash/1`, lines 50-80)

Existing `flash/1` already uses `alert alert-info` / `alert-error`. Spec adds: a `:warning` and `:success` kind, and consistent styling with new tokens. Existing implementation only handles `:info` and `:error`.

- [ ] **Step 1: Add tests**

Append to test file, inside the module before `end`:

```elixir
  describe "flash/1" do
    test "renders info kind" do
      assigns = %{}
      html = rendered_to_string(~H|<.flash kind={:info}>Saved.</.flash>|)
      assert html =~ "alert-info"
      assert html =~ "Saved."
    end

    test "renders error kind" do
      assigns = %{}
      html = rendered_to_string(~H|<.flash kind={:error}>Bad.</.flash>|)
      assert html =~ "alert-error"
      assert html =~ "Bad."
    end

    test "renders success kind" do
      assigns = %{}
      html = rendered_to_string(~H|<.flash kind={:success}>Ok.</.flash>|)
      assert html =~ "alert-success"
      assert html =~ "Ok."
    end

    test "renders warning kind" do
      assigns = %{}
      html = rendered_to_string(~H|<.flash kind={:warning}>Heads up.</.flash>|)
      assert html =~ "alert-warning"
      assert html =~ "Heads up."
    end
  end
```

- [ ] **Step 2: Run tests, verify warning/success fail**

Run: `mix test test/mobile_car_wash_web/components/core_components_test.exs --only describe:flash`
Expected: warning + success tests fail (kind not in attr `values:` list).

- [ ] **Step 3: Update `flash/1` to support all four kinds**

Find the `attr :kind, :atom, values: [:info, :error]` line and change to:

```elixir
  attr :kind, :atom, values: [:info, :success, :warning, :error]
```

Then update the body — find the two existing class lines:

```elixir
        @kind == :info && "alert-info",
        @kind == :error && "alert-error"
```

Change to:

```elixir
        @kind == :info && "alert-info",
        @kind == :success && "alert-success",
        @kind == :warning && "alert-warning",
        @kind == :error && "alert-error"
```

And update the icon lines just below to add icons for the new kinds:

```elixir
        <.icon :if={@kind == :info} name="hero-information-circle" class="size-5 shrink-0" />
        <.icon :if={@kind == :success} name="hero-check-circle" class="size-5 shrink-0" />
        <.icon :if={@kind == :warning} name="hero-exclamation-triangle" class="size-5 shrink-0" />
        <.icon :if={@kind == :error} name="hero-exclamation-circle" class="size-5 shrink-0" />
```

- [ ] **Step 4: Run tests, verify pass**

Run: `mix test test/mobile_car_wash_web/components/core_components_test.exs --only describe:flash`
Expected: all 4 flash tests pass.

- [ ] **Step 5: Run full suite**

Run: `mix test`
Expected: 0 failures.

- [ ] **Step 6: Commit**

```bash
git add test/mobile_car_wash_web/components/core_components_test.exs lib/mobile_car_wash_web/components/core_components.ex
git commit -m "ui: flash — add :success and :warning kinds with hero icons"
```

---

## Task 8: Refresh `table` component (TDD)

**Files:**
- Modify: `test/mobile_car_wash_web/components/core_components_test.exs`
- Modify: `lib/mobile_car_wash_web/components/core_components.ex` (`table/1`, line 356)

Goal: existing `table/1` is fine in shape. Refresh classes to use the new tokens (`bg-card`, `border-base-300`, `text-base-content/70` for headers). Confirm via tests that headers and rows render with expected structure.

- [ ] **Step 1: Read current implementation**

Run: `sed -n '320,408p' lib/mobile_car_wash_web/components/core_components.ex`
Note the slot definitions and current class lists.

- [ ] **Step 2: Add tests**

Append to test file:

```elixir
  describe "table/1" do
    test "renders rows and headers" do
      rows = [%{name: "Alice", role: "Admin"}, %{name: "Bob", role: "Tech"}]
      assigns = %{rows: rows}

      html =
        rendered_to_string(~H"""
        <.table id="users" rows={@rows}>
          <:col :let={u} label="Name">{u.name}</:col>
          <:col :let={u} label="Role">{u.role}</:col>
        </.table>
        """)

      assert html =~ "Name"
      assert html =~ "Role"
      assert html =~ "Alice"
      assert html =~ "Bob"
      assert html =~ "Admin"
      assert html =~ "Tech"
    end
  end
```

- [ ] **Step 3: Run test**

Run: `mix test test/mobile_car_wash_web/components/core_components_test.exs --only describe:table`
Likely passes already (existing implementation is functional). If it fails, the slot or row syntax in the test may need to match what the existing component expects — read the component and adjust the test rather than the component.

- [ ] **Step 4: Update class lists for new tokens**

In `def table(assigns) do`, find class attributes referencing OLD tokens (`primary-700`, `secondary-50`, `tertiary-400`, etc.) and update them to use the new ones. Common updates:

| Old | New |
|---|---|
| `bg-primary-700` / `bg-primary-900` | `bg-base-100` (header row) |
| `text-secondary-50` | `text-base-content` |
| `border-primary-200` | `border-base-300` |
| `text-tertiary-500` | `text-cyan-700` (or `text-accent`) |
| `hover:bg-primary-50` | `hover:bg-base-200` |

Do a per-line search-and-replace inside the `table/1` function body only — don't touch other functions in this step.

- [ ] **Step 5: Run full suite**

Run: `mix test`
Expected: 0 failures. Any existing admin page using the table should still render (the new classes resolve to the new theme colors).

- [ ] **Step 6: Commit**

```bash
git add test/mobile_car_wash_web/components/core_components_test.exs lib/mobile_car_wash_web/components/core_components.ex
git commit -m "ui: table — refresh class tokens to new palette"
```

---

## Task 9: Refresh `header` component (TDD)

**Files:**
- Modify: `test/mobile_car_wash_web/components/core_components_test.exs`
- Modify: `lib/mobile_car_wash_web/components/core_components.ex` (`header/1`, line 315)

- [ ] **Step 1: Add test**

Append to test file:

```elixir
  describe "header/1" do
    test "renders title and subtitle" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.header>
          Page title
          <:subtitle>Helpful description</:subtitle>
        </.header>
        """)

      assert html =~ "Page title"
      assert html =~ "Helpful description"
    end

    test "renders actions slot" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.header>
          Stuff
          <:actions>
            <button>New</button>
          </:actions>
        </.header>
        """)

      assert html =~ "Stuff"
      assert html =~ "<button>New</button>"
    end
  end
```

- [ ] **Step 2: Run test**

Run: `mix test test/mobile_car_wash_web/components/core_components_test.exs --only describe:header`
Likely passes already. If it does, you can move to refreshing classes; if not, debug the slot syntax against existing implementation.

- [ ] **Step 3: Refresh classes for new tokens**

Inside `def header(assigns) do`, look for classes like `text-primary-900`, `text-secondary-700` etc. Update:

| Old | New |
|---|---|
| `text-primary-900` (title) | `text-base-content` |
| `text-secondary-700` (subtitle) | `text-base-content/70` |

Increase headline weight + tracking to match spec ("Section heading 22/600/-0.4"):

```elixir
class="text-2xl font-semibold text-base-content tracking-tight"
```

- [ ] **Step 4: Run tests**

Run: `mix test`
Expected: 0 failures.

- [ ] **Step 5: Commit**

```bash
git add test/mobile_car_wash_web/components/core_components_test.exs lib/mobile_car_wash_web/components/core_components.ex
git commit -m "ui: header — refresh tokens, semibold + tighter tracking"
```

---

## Task 10: Add `modal` component (TDD)

**Files:**
- Modify: `test/mobile_car_wash_web/components/core_components_test.exs`
- Modify: `lib/mobile_car_wash_web/components/core_components.ex` (add new function near the top, after `flash/1`)

Spec: generic `<.modal>` with `id`, `show`, `on_cancel`, header/body/footer slots. Cash flow's existing modals will refactor to use this in Plan 4.

- [ ] **Step 1: Add tests**

Append to test file:

```elixir
  describe "modal/1" do
    test "renders with title and body" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.modal id="test-modal">
          <:title>Confirm</:title>
          Are you sure?
        </.modal>
        """)

      assert html =~ ~s(id="test-modal")
      assert html =~ "Confirm"
      assert html =~ "Are you sure?"
    end

    test "renders footer slot" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.modal id="m">
          <:title>Hi</:title>
          Body
          <:footer>
            <button>OK</button>
          </:footer>
        </.modal>
        """)

      assert html =~ "<button>OK</button>"
    end
  end
```

- [ ] **Step 2: Run tests, verify failure**

Run: `mix test test/mobile_car_wash_web/components/core_components_test.exs --only describe:modal`
Expected: compile error or "function modal/1 undefined".

- [ ] **Step 3: Add `modal/1`**

Insert in `core_components.ex`, immediately after the `flash/1` function (around line 81):

```elixir
  @doc """
  Renders a centered modal dialog.

  ## Examples

      <.modal id="confirm-modal">
        <:title>Delete this?</:title>
        This cannot be undone.
        <:footer>
          <.button variant="ghost" phx-click={hide("#confirm-modal")}>Cancel</.button>
          <.button variant="destructive" phx-click="delete">Delete</.button>
        </:footer>
      </.modal>

  Open with `show("#confirm-modal")` and close with `hide("#confirm-modal")`,
  or wire `phx-click` to a custom handler.
  """
  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :on_cancel, JS, default: %JS{}
  slot :title
  slot :inner_block, required: true
  slot :footer

  def modal(assigns) do
    ~H"""
    <div
      id={@id}
      class={["fixed inset-0 z-50 flex items-center justify-center p-4", !@show && "hidden"]}
      phx-mounted={@show && show("##{@id}")}
      role="dialog"
      aria-modal="true"
    >
      <div
        class="absolute inset-0 bg-base-content/40 backdrop-blur-sm"
        phx-click={hide("##{@id}") |> JS.exec(@on_cancel, "phx-cancel")}
      />
      <div class="relative bg-base-100 rounded-box border border-base-300 shadow-lg max-w-md w-full max-h-[90vh] overflow-auto">
        <div :if={@title != []} class="px-6 py-4 border-b border-base-300">
          <h2 class="text-lg font-semibold text-base-content">
            {render_slot(@title)}
          </h2>
        </div>
        <div class="px-6 py-4 text-sm text-base-content/80">
          {render_slot(@inner_block)}
        </div>
        <div :if={@footer != []} class="px-6 py-4 border-t border-base-300 flex justify-end gap-2">
          {render_slot(@footer)}
        </div>
      </div>
    </div>
    """
  end
```

- [ ] **Step 4: Run tests**

Run: `mix test test/mobile_car_wash_web/components/core_components_test.exs --only describe:modal`
Expected: both pass.

- [ ] **Step 5: Run full suite**

Run: `mix test`
Expected: 0 failures.

- [ ] **Step 6: Commit**

```bash
git add test/mobile_car_wash_web/components/core_components_test.exs lib/mobile_car_wash_web/components/core_components.ex
git commit -m "ui: add generic <.modal> component"
```

---

## Task 11: Add `status_pill` component (TDD)

**Files:**
- Modify: `test/mobile_car_wash_web/components/core_components_test.exs`
- Modify: `lib/mobile_car_wash_web/components/core_components.ex`

Spec: `<.status_pill status={:on_target|:underfunded|:paid|:over|:long_term}>{label}</.status_pill>`. Used in cash flow bucket cards and transactions table.

- [ ] **Step 1: Add tests**

Append:

```elixir
  describe "status_pill/1" do
    test "renders on_target as success" do
      assigns = %{}
      html = rendered_to_string(~H|<.status_pill status={:on_target}>On target</.status_pill>|)
      assert html =~ "bg-success/15"
      assert html =~ "text-success"
      assert html =~ "On target"
    end

    test "renders underfunded as warning" do
      assigns = %{}
      html = rendered_to_string(~H|<.status_pill status={:underfunded}>Underfunded</.status_pill>|)
      assert html =~ "bg-warning/15"
      assert html =~ "text-warning"
    end

    test "renders paid as success" do
      assigns = %{}
      html = rendered_to_string(~H|<.status_pill status={:paid}>Paid</.status_pill>|)
      assert html =~ "bg-success/15"
    end

    test "renders over as error" do
      assigns = %{}
      html = rendered_to_string(~H|<.status_pill status={:over}>Over</.status_pill>|)
      assert html =~ "bg-error/15"
    end

    test "renders long_term as neutral" do
      assigns = %{}
      html = rendered_to_string(~H|<.status_pill status={:long_term}>Long-term</.status_pill>|)
      assert html =~ "bg-base-200"
    end
  end
```

- [ ] **Step 2: Run tests, verify failure**

Run: `mix test test/mobile_car_wash_web/components/core_components_test.exs --only describe:status_pill`
Expected: function undefined.

- [ ] **Step 3: Add `status_pill/1`**

Add at end of `core_components.ex`, before the final `end` of the module:

```elixir
  @doc """
  Renders a small status indicator pill.

  ## Examples

      <.status_pill status={:on_target}>On target</.status_pill>
      <.status_pill status={:underfunded}>Underfunded</.status_pill>
  """
  attr :status, :atom,
    values: [:on_target, :underfunded, :paid, :over, :long_term],
    required: true

  slot :inner_block, required: true

  def status_pill(assigns) do
    classes =
      case assigns.status do
        :on_target -> "bg-success/15 text-success"
        :paid -> "bg-success/15 text-success"
        :underfunded -> "bg-warning/15 text-warning"
        :over -> "bg-error/15 text-error"
        :long_term -> "bg-base-200 text-base-content/60"
      end

    assigns = assign(assigns, :classes, classes)

    ~H"""
    <span class={[
      "inline-flex items-center text-[10px] font-bold uppercase tracking-wide px-2 py-0.5 rounded",
      @classes
    ]}>
      {render_slot(@inner_block)}
    </span>
    """
  end
```

- [ ] **Step 4: Run tests, verify pass**

Run: `mix test test/mobile_car_wash_web/components/core_components_test.exs --only describe:status_pill`
Expected: 5 tests pass.

- [ ] **Step 5: Run full suite**

Run: `mix test`
Expected: 0 failures.

- [ ] **Step 6: Commit**

```bash
git add test/mobile_car_wash_web/components/core_components_test.exs lib/mobile_car_wash_web/components/core_components.ex
git commit -m "ui: add <.status_pill> component (5 status variants)"
```

---

## Task 12: Add `progress_bar` component (TDD)

**Files:**
- Modify: `test/mobile_car_wash_web/components/core_components_test.exs`
- Modify: `lib/mobile_car_wash_web/components/core_components.ex`

Spec: `<.progress_bar value={0..1} variant={:cyan|:amber|:green|:red}>`. Thin horizontal bar.

- [ ] **Step 1: Add tests**

Append:

```elixir
  describe "progress_bar/1" do
    test "renders cyan variant by default at given value" do
      assigns = %{}
      html = rendered_to_string(~H|<.progress_bar value={0.42} />|)
      assert html =~ "bg-cyan-500"
      assert html =~ "width: 42%"
    end

    test "renders amber variant" do
      assigns = %{}
      html = rendered_to_string(~H|<.progress_bar value={0.8} variant={:amber} />|)
      assert html =~ "bg-warning"
      assert html =~ "width: 80%"
    end

    test "renders green variant" do
      assigns = %{}
      html = rendered_to_string(~H|<.progress_bar value={1.0} variant={:green} />|)
      assert html =~ "bg-success"
      assert html =~ "width: 100%"
    end

    test "renders red variant" do
      assigns = %{}
      html = rendered_to_string(~H|<.progress_bar value={0.05} variant={:red} />|)
      assert html =~ "bg-error"
      assert html =~ "width: 5%"
    end

    test "clamps value above 1.0 to 100%" do
      assigns = %{}
      html = rendered_to_string(~H|<.progress_bar value={1.5} />|)
      assert html =~ "width: 100%"
    end

    test "clamps value below 0 to 0%" do
      assigns = %{}
      html = rendered_to_string(~H|<.progress_bar value={-0.2} />|)
      assert html =~ "width: 0%"
    end
  end
```

- [ ] **Step 2: Run tests, verify failure**

Run: `mix test test/mobile_car_wash_web/components/core_components_test.exs --only describe:progress_bar`
Expected: function undefined.

- [ ] **Step 3: Add `progress_bar/1`**

Append to `core_components.ex` before final `end`:

```elixir
  @doc """
  Renders a thin horizontal progress bar.

  `value` is a float in 0.0..1.0 (clamped if outside).

  ## Examples

      <.progress_bar value={0.42} />
      <.progress_bar value={0.8} variant={:amber} />
  """
  attr :value, :float, required: true
  attr :variant, :atom, values: [:cyan, :amber, :green, :red], default: :cyan
  attr :class, :any, default: nil

  def progress_bar(assigns) do
    pct = round(max(0.0, min(1.0, assigns.value)) * 100)

    fill_class =
      case assigns.variant do
        :cyan -> "bg-cyan-500"
        :amber -> "bg-warning"
        :green -> "bg-success"
        :red -> "bg-error"
      end

    assigns = assign(assigns, pct: pct, fill_class: fill_class)

    ~H"""
    <div class={["h-1 w-full bg-base-200 rounded-full overflow-hidden", @class]}>
      <div class={["h-full rounded-full", @fill_class]} style={"width: #{@pct}%"} />
    </div>
    """
  end
```

- [ ] **Step 4: Run tests, verify pass**

Run: `mix test test/mobile_car_wash_web/components/core_components_test.exs --only describe:progress_bar`
Expected: 6 tests pass.

- [ ] **Step 5: Run full suite**

Run: `mix test`

- [ ] **Step 6: Commit**

```bash
git add test/mobile_car_wash_web/components/core_components_test.exs lib/mobile_car_wash_web/components/core_components.ex
git commit -m "ui: add <.progress_bar> with cyan/amber/green/red variants"
```

---

## Task 13: Add `empty_state` component (TDD)

**Files:**
- Modify: `test/mobile_car_wash_web/components/core_components_test.exs`
- Modify: `lib/mobile_car_wash_web/components/core_components.ex`

Spec: `<.empty_state icon title body action?>` for empty appointments lists, etc.

- [ ] **Step 1: Add tests**

Append:

```elixir
  describe "empty_state/1" do
    test "renders icon, title, body" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.empty_state icon="hero-inbox" title="Nothing here yet" body="Once you book, it'll show up here." />
        """)

      assert html =~ "hero-inbox"
      assert html =~ "Nothing here yet"
      assert html =~ "Once you book"
    end

    test "renders action slot" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.empty_state icon="hero-inbox" title="Empty" body="Add one.">
          <:action>
            <button>Add</button>
          </:action>
        </.empty_state>
        """)

      assert html =~ "<button>Add</button>"
    end
  end
```

- [ ] **Step 2: Run tests, verify failure**

Run: `mix test test/mobile_car_wash_web/components/core_components_test.exs --only describe:empty_state`
Expected: function undefined.

- [ ] **Step 3: Add `empty_state/1`**

Append to `core_components.ex`:

```elixir
  @doc """
  Renders an empty-state placeholder with icon, title, body, optional action.

  ## Examples

      <.empty_state icon="hero-calendar" title="No appointments" body="Book your first wash to get started." />
  """
  attr :icon, :string, required: true, doc: "hero-* icon name"
  attr :title, :string, required: true
  attr :body, :string, required: true
  slot :action

  def empty_state(assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center py-12 px-6 text-center">
      <div class="w-12 h-12 rounded-full bg-base-200 flex items-center justify-center mb-4">
        <.icon name={@icon} class="size-6 text-base-content/50" />
      </div>
      <h3 class="text-base font-semibold text-base-content mb-1">{@title}</h3>
      <p class="text-sm text-base-content/70 max-w-sm">{@body}</p>
      <div :if={@action != []} class="mt-4">
        {render_slot(@action)}
      </div>
    </div>
    """
  end
```

- [ ] **Step 4: Run tests, verify pass**

Run: `mix test test/mobile_car_wash_web/components/core_components_test.exs --only describe:empty_state`
Expected: 2 tests pass.

- [ ] **Step 5: Run full suite**

Run: `mix test`

- [ ] **Step 6: Commit**

```bash
git add test/mobile_car_wash_web/components/core_components_test.exs lib/mobile_car_wash_web/components/core_components.ex
git commit -m "ui: add <.empty_state> component"
```

---

## Task 14: Add `kpi_card` component (TDD)

**Files:**
- Modify: `test/mobile_car_wash_web/components/core_components_test.exs`
- Modify: `lib/mobile_car_wash_web/components/core_components.ex`

Spec: `<.kpi_card label value delta? sparkline_points? subtext?>`. Big monospace number, optional delta and sparkline.

- [ ] **Step 1: Add tests**

Append:

```elixir
  describe "kpi_card/1" do
    test "renders label and value" do
      assigns = %{}
      html = rendered_to_string(~H|<.kpi_card label="Cash on hand" value="$24,807" />|)
      assert html =~ "Cash on hand"
      assert html =~ "$24,807"
      assert html =~ "font-mono"
    end

    test "renders positive delta" do
      assigns = %{}
      html = rendered_to_string(~H|<.kpi_card label="Cash" value="$10" delta="+12.4%" delta_direction={:up} />|)
      assert html =~ "+12.4%"
      assert html =~ "text-success"
    end

    test "renders negative delta" do
      assigns = %{}
      html = rendered_to_string(~H|<.kpi_card label="Cash" value="$10" delta="-3.1%" delta_direction={:down} />|)
      assert html =~ "-3.1%"
      assert html =~ "text-error"
    end

    test "renders subtext" do
      assigns = %{}
      html = rendered_to_string(~H|<.kpi_card label="Cash" value="$10" subtext="vs last month" />|)
      assert html =~ "vs last month"
    end
  end
```

- [ ] **Step 2: Run tests, verify failure**

Run: `mix test test/mobile_car_wash_web/components/core_components_test.exs --only describe:kpi_card`
Expected: function undefined.

- [ ] **Step 3: Add `kpi_card/1`**

Append to `core_components.ex`:

```elixir
  @doc """
  Renders a KPI tile: label, big value, optional delta, optional subtext.

  Sparkline is rendered separately (callers pass an SVG via `:trailing` slot
  if they want one — keeps this component dependency-free).

  ## Examples

      <.kpi_card label="Cash on hand" value="$24,807" delta="+12.4%" delta_direction={:up} subtext="vs last month" />
  """
  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :delta, :string, default: nil
  attr :delta_direction, :atom, values: [:up, :down, nil], default: nil
  attr :subtext, :string, default: nil
  attr :class, :any, default: nil
  slot :trailing, doc: "optional element rendered to the right of the value (e.g. sparkline)"

  def kpi_card(assigns) do
    delta_color =
      case assigns.delta_direction do
        :up -> "text-success"
        :down -> "text-error"
        _ -> "text-base-content/60"
      end

    assigns = assign(assigns, :delta_color, delta_color)

    ~H"""
    <div class={["bg-base-100 border border-base-300 rounded-box p-5", @class]}>
      <div class="flex items-start justify-between gap-4">
        <div>
          <div class="text-[11px] font-semibold uppercase tracking-wide text-base-content/60">
            {@label}
          </div>
          <div class="flex items-baseline gap-2 mt-1.5">
            <div class="font-mono text-3xl font-bold tracking-tight text-base-content tabular-nums">
              {@value}
            </div>
            <div :if={@delta} class={["text-xs font-semibold", @delta_color]}>
              {@delta}
            </div>
          </div>
          <div :if={@subtext} class="text-xs text-base-content/60 mt-1">
            {@subtext}
          </div>
        </div>
        <div :if={@trailing != []}>
          {render_slot(@trailing)}
        </div>
      </div>
    </div>
    """
  end
```

- [ ] **Step 4: Run tests, verify pass**

Run: `mix test test/mobile_car_wash_web/components/core_components_test.exs --only describe:kpi_card`
Expected: 4 tests pass.

- [ ] **Step 5: Run full suite**

Run: `mix test`

- [ ] **Step 6: Commit**

```bash
git add test/mobile_car_wash_web/components/core_components_test.exs lib/mobile_car_wash_web/components/core_components.ex
git commit -m "ui: add <.kpi_card> component (label, value, delta, subtext, trailing slot)"
```

---

## Task 15: Add `bucket_card` component (TDD)

**Files:**
- Modify: `test/mobile_car_wash_web/components/core_components_test.exs`
- Modify: `lib/mobile_car_wash_web/components/core_components.ex`

Spec: `<.bucket_card label amount target_pct status status_label>` for cash flow bucket grid.

- [ ] **Step 1: Add tests**

Append:

```elixir
  describe "bucket_card/1" do
    test "renders label, amount, target percent, status pill" do
      assigns = %{}

      html =
        rendered_to_string(
          ~H|<.bucket_card label="Operating" amount="$8,420" target="of $10,000 goal" target_pct={0.84} status={:on_target} status_label="On target" />|
        )

      assert html =~ "Operating"
      assert html =~ "$8,420"
      assert html =~ "of $10,000 goal"
      assert html =~ "On target"
      assert html =~ "width: 84%"
    end

    test "renders underfunded status with amber bar" do
      assigns = %{}

      html =
        rendered_to_string(
          ~H|<.bucket_card label="Tax" amount="$3,150" target="of $5,000 goal" target_pct={0.63} status={:underfunded} status_label="Underfunded" />|
        )

      assert html =~ "bg-warning"
      assert html =~ "Underfunded"
    end

    test "renders empty progress bar when target_pct is nil" do
      assigns = %{}

      html =
        rendered_to_string(
          ~H|<.bucket_card label="Investment" amount="$0" target="no goal set" target_pct={nil} status={:long_term} status_label="Long-term" />|
        )

      refute html =~ "width: 0%"
      # Empty bar has no inner width div at all
      assert html =~ "Long-term"
    end
  end
```

- [ ] **Step 2: Run tests, verify failure**

Run: `mix test test/mobile_car_wash_web/components/core_components_test.exs --only describe:bucket_card`

- [ ] **Step 3: Add `bucket_card/1`**

Append to `core_components.ex`:

```elixir
  @doc """
  Renders a single bucket card for the cash flow page.

  ## Examples

      <.bucket_card
        label="Operating"
        amount="$8,420"
        target="of $10,000 goal"
        target_pct={0.84}
        status={:on_target}
        status_label="On target"
      />
  """
  attr :label, :string, required: true
  attr :amount, :string, required: true
  attr :target, :string, required: true, doc: "subtext line e.g. \"of $10,000 goal\""
  attr :target_pct, :float, default: nil, doc: "0.0..1.0 fill ratio; nil = empty bar"
  attr :status, :atom, required: true, values: [:on_target, :underfunded, :paid, :over, :long_term]
  attr :status_label, :string, required: true

  def bucket_card(assigns) do
    progress_variant =
      case assigns.status do
        :on_target -> :cyan
        :paid -> :green
        :underfunded -> :amber
        :over -> :red
        :long_term -> :cyan
      end

    assigns = assign(assigns, :progress_variant, progress_variant)

    ~H"""
    <div class="bg-base-100 border border-base-300 rounded-box p-4">
      <div class="flex items-start justify-between mb-2">
        <div class="text-[10px] font-semibold uppercase tracking-wide text-base-content/60">
          {@label}
        </div>
        <.status_pill status={@status}>{@status_label}</.status_pill>
      </div>
      <div class="font-mono text-xl font-bold text-base-content tabular-nums">
        {@amount}
      </div>
      <div class="text-[11px] text-base-content/60 mt-0.5">
        {@target}
      </div>
      <div class="mt-3">
        <.progress_bar :if={@target_pct} value={@target_pct} variant={@progress_variant} />
        <div :if={!@target_pct} class="h-1 w-full bg-base-200 rounded-full" />
      </div>
    </div>
    """
  end
```

- [ ] **Step 4: Run tests, verify pass**

Run: `mix test test/mobile_car_wash_web/components/core_components_test.exs --only describe:bucket_card`

- [ ] **Step 5: Run full suite**

Run: `mix test`

- [ ] **Step 6: Commit**

```bash
git add test/mobile_car_wash_web/components/core_components_test.exs lib/mobile_car_wash_web/components/core_components.ex
git commit -m "ui: add <.bucket_card> component (composes status_pill + progress_bar)"
```

---

## Task 16: Update style guide page to showcase all components

**Files:**
- Modify: `lib/mobile_car_wash_web/live/admin/style_guide_live.ex`

The existing `/admin/style_guide` page (767 lines) already has its own structure for showcasing components. Add new sections for the components added in Plan 1 so a developer (or you) can visually verify everything.

- [ ] **Step 1: Read the current style guide structure**

Run: `grep -n 'def\|<h2\|<section' lib/mobile_car_wash_web/live/admin/style_guide_live.ex | head -50`
Identify the pattern used to add a new "section" (heading + sample renderings). Match it.

- [ ] **Step 2: Add a "Buttons" section showing all 4 variants × 3 sizes**

Find the appropriate place in the render function (after existing sections; or replace the existing button section if there is one). Insert:

```heex
<section class="space-y-3">
  <h2 class="text-xl font-semibold text-base-content">Buttons</h2>
  <div class="flex flex-wrap gap-3 items-center">
    <.button>Primary</.button>
    <.button variant="secondary">Secondary</.button>
    <.button variant="ghost">Ghost</.button>
    <.button variant="destructive">Destructive</.button>
  </div>
  <div class="flex flex-wrap gap-3 items-center">
    <.button size="sm">Small</.button>
    <.button>Medium</.button>
    <.button size="lg">Large</.button>
  </div>
</section>
```

- [ ] **Step 3: Add a "Status pills" section**

```heex
<section class="space-y-3">
  <h2 class="text-xl font-semibold text-base-content">Status pills</h2>
  <div class="flex flex-wrap gap-2 items-center">
    <.status_pill status={:on_target}>On target</.status_pill>
    <.status_pill status={:paid}>Paid</.status_pill>
    <.status_pill status={:underfunded}>Underfunded</.status_pill>
    <.status_pill status={:over}>Over</.status_pill>
    <.status_pill status={:long_term}>Long-term</.status_pill>
  </div>
</section>
```

- [ ] **Step 4: Add a "Progress bars" section**

```heex
<section class="space-y-3">
  <h2 class="text-xl font-semibold text-base-content">Progress bars</h2>
  <div class="space-y-2 max-w-sm">
    <.progress_bar value={0.84} />
    <.progress_bar value={0.42} variant={:amber} />
    <.progress_bar value={1.0} variant={:green} />
    <.progress_bar value={0.05} variant={:red} />
  </div>
</section>
```

- [ ] **Step 5: Add a "Flash" section showing all 4 kinds**

```heex
<section class="space-y-3">
  <h2 class="text-xl font-semibold text-base-content">Flash messages</h2>
  <div class="space-y-2">
    <.flash kind={:info}>Info — your changes were saved.</.flash>
    <.flash kind={:success}>Success — booking confirmed.</.flash>
    <.flash kind={:warning}>Warning — tax reserve is underfunded.</.flash>
    <.flash kind={:error}>Error — payment failed.</.flash>
  </div>
</section>
```

(Note: these will all stack visually; that's expected for a style guide.)

- [ ] **Step 6: Add an "Empty state" section**

```heex
<section class="space-y-3">
  <h2 class="text-xl font-semibold text-base-content">Empty state</h2>
  <.empty_state
    icon="hero-calendar"
    title="No appointments yet"
    body="Book your first wash to see it here."
  >
    <:action>
      <.button>Book now</.button>
    </:action>
  </.empty_state>
</section>
```

- [ ] **Step 7: Add a "KPI card" section**

```heex
<section class="space-y-3">
  <h2 class="text-xl font-semibold text-base-content">KPI card</h2>
  <div class="grid grid-cols-1 md:grid-cols-2 gap-4 max-w-3xl">
    <.kpi_card
      label="Cash on hand"
      value="$24,807"
      delta="+12.4%"
      delta_direction={:up}
      subtext="vs $22,067 last month"
    />
    <.kpi_card
      label="Active subscribers"
      value="142"
      delta="-3"
      delta_direction={:down}
      subtext="vs 145 last week"
    />
  </div>
</section>
```

- [ ] **Step 8: Add a "Bucket cards" section**

```heex
<section class="space-y-3">
  <h2 class="text-xl font-semibold text-base-content">Bucket cards</h2>
  <div class="grid grid-cols-2 md:grid-cols-5 gap-3">
    <.bucket_card label="Operating" amount="$8,420" target="of $10,000 goal" target_pct={0.84} status={:on_target} status_label="On target" />
    <.bucket_card label="Tax reserve" amount="$3,150" target="of $5,000 goal" target_pct={0.63} status={:underfunded} status_label="Underfunded" />
    <.bucket_card label="Savings" amount="$10,200" target="of $15,000 goal" target_pct={0.68} status={:on_target} status_label="68% goal" />
    <.bucket_card label="Investment" amount="$0" target="no goal set" target_pct={nil} status={:long_term} status_label="Long-term" />
    <.bucket_card label="Salary" amount="$3,037" target="paid Apr 1" target_pct={1.0} status={:paid} status_label="Paid" />
  </div>
</section>
```

- [ ] **Step 9: Add a "Modal" section with toggle**

This needs a small handler since modals are show/hide. Add to the LiveView's `mount/3` (or replace existing) to default `:demo_modal_open` to false, and add a handler:

```elixir
  def handle_event("toggle_demo_modal", _, socket) do
    {:noreply, update(socket, :demo_modal_open, &(!&1))}
  end
```

In the render function, append the section:

```heex
<section class="space-y-3">
  <h2 class="text-xl font-semibold text-base-content">Modal</h2>
  <.button phx-click="toggle_demo_modal">Open demo modal</.button>
  <.modal id="demo-modal" show={@demo_modal_open}>
    <:title>Confirm action</:title>
    This is what a modal looks like in the new design system.
    <:footer>
      <.button variant="ghost" phx-click="toggle_demo_modal">Cancel</.button>
      <.button variant="primary" phx-click="toggle_demo_modal">Confirm</.button>
    </:footer>
  </.modal>
</section>
```

(Initialize `demo_modal_open: false` in `mount/3`.)

- [ ] **Step 10: Boot the dev server, navigate to the style guide, visually verify**

Run: `mix phx.server`
Open: `http://localhost:4000/admin/style_guide` (sign in as admin first if needed)

Visually verify each section renders correctly. If something looks broken (missing class, wrong color), debug now — this page is your reference for the rest of phase 1.

- [ ] **Step 11: Run full test suite**

Run: `mix test`
Expected: 0 failures.

- [ ] **Step 12: Commit**

```bash
git add lib/mobile_car_wash_web/live/admin/style_guide_live.ex
git commit -m "ui: showcase new design-system components in /admin/style_guide"
```

---

## Task 17: Final verification & checkpoint

**Files:** none modified — purely verification.

- [ ] **Step 1: Run the entire test suite**

Run: `mix test`
Expected: 0 failures.

- [ ] **Step 2: Verify test count grew by ~30 tests**

Run: `mix test 2>&1 | tail -3`
Compare against the baseline you noted in Task 0 Step 4. The count should be higher by roughly the number of `test "..."` blocks added across Tasks 5-15 (~30 tests).

- [ ] **Step 3: Boot dev server and click through key existing pages**

Run: `mix phx.server`
Visit each in a browser and confirm nothing looks broken (no missing colors, no jarring layout shifts):
- `http://localhost:4000/` (landing — old layout, but new colors should apply)
- `http://localhost:4000/sign-in` (auth)
- `http://localhost:4000/admin` (admin dashboard, sign in first)
- `http://localhost:4000/admin/cash_flow` (still uses old bucket diagram — that's expected; only colors should differ)
- `http://localhost:4000/admin/style_guide` (your new showcase)

If any page is visually broken (missing colors, layout collapse), STOP and fix before declaring Plan 1 complete.

- [ ] **Step 4: Verify asset bundle compiles**

Run: `mix assets.deploy`
Expected: exit 0. This is what production uses.

- [ ] **Step 5: Confirm git log**

Run: `git log --oneline main..HEAD | head -25`
You should see the per-task commits in chronological order. No "WIP" or "fix" or amend commits.

- [ ] **Step 6: Final checkpoint commit (if anything is uncommitted)**

Run: `git status`
If clean: nothing to commit. Plan 1 done.
If anything's left over: review with `git diff`, then `git add` + commit with a clear message.

- [ ] **Step 7: Report completion**

Plan 1 is complete. Foundation is in place for Plans 2-5. Hand off to user with a summary:
- Tokens swapped to Modern SaaS palette
- 5 existing components refreshed (button, input, flash, table, header)
- 6 new components added (modal, status_pill, progress_bar, empty_state, kpi_card, bucket_card)
- ~30 new tests
- Style guide page updated for visual reference at `/admin/style_guide`
- Existing 113-test baseline still green

Recommend the user open `/admin/style_guide` and eyeball it before approving Plan 2.

---

## What's NOT in Plan 1 (reminder)

These are explicitly deferred — do NOT implement them in Plan 1:

- New brand assets (logos, OG, favicon, email templates) → **Plan 2**
- Cash flow page redesign — replacing bucket diagram, Health summary band, mobile responsive layout → **Plan 4**
- Customer-facing redesigns (landing, booking, success), `marketing_components.ex` → **Plan 3**
- Wallaby setup + 5 E2E tests → **Plan 5**

If during Plan 1 you find yourself editing `landing_live.ex`, `cash_flow_live.ex`, or any `marketing_*` file, stop. That work belongs to a different plan.
