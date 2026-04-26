# Phase-1 redesign + Wallaby integration — Design

**Date:** 2026-04-26
**Status:** Draft (pending user review)
**Branch:** `claude/jolly-swirles-c8d1b8`
**Author:** Brainstormed with Claude

---

## TL;DR

Three pieces of work bundled into one phase-1 spec:

1. **Wallaby integration** — activate the unused dependency, configure ChromeDriver + sandbox, write 5 end-to-end browser tests covering the customer + admin + subscription flows.
2. **Design system reboot** — Modern SaaS direction (white/slate base, navy primary `#1e293b`, cyan accent `#06b6d4`, Inter typography, JetBrains Mono for financial figures), with a single dark "tech credibility" section deeper in the landing page.
3. **Customer funnel + cash flow page redesigns** — landing, booking, booking-success, plus a full polish pass on the admin cash flow page that addresses four ranked pain points (amateurish bucket diagram → cluttered layout → no proactive guidance → broken on mobile).

Sequencing: page-by-page starting with landing, extracting components into the shared library as they emerge, Wallaby suite written last against the finished UI. Estimated 10-15 days of focused work.

This spec is **phase 1 of 4**. Phases 2-4 (remaining customer pages, admin views, tech dashboard) get their own specs after this one ships.

---

## Scope

### In scope

- Wallaby setup + 5 E2E tests (booking golden path, customer auth + appointments, admin dispatch confirm, subscription signup, subscription cancel)
- Design tokens (palette, typography, spacing, radii, shadows) replacing the current daisyUI theme blocks
- Component vocabulary in `core_components.ex` + new `marketing_components.ex` (~18 components, ~6 net-new)
- Cash flow page (`admin/cash_flow_live.ex`) full redesign — replace bucket diagram with KPI hero + bucket cards, add Health summary band, mobile-responsive layout, keep all Ash logic / cascade behavior intact
- Landing page (`landing_live.ex`) full markup rewrite
- Booking page (`booking_live.ex`) markup rewrite — preserve state machine, validation, Stripe integration, geocoding
- Booking success page (`booking_success_live.ex`) full rewrite
- Brand asset rework: logos (light/dark/icon v2), OG share image, favicon, email templates, Stripe Checkout branding, theme-color meta tag
- Mobile-responsive behavior across all redesigned pages

### Explicitly out of scope (deferred to phase 2/3/4)

- Sign-in (`auth/sign_in_live.ex`), subscription manage, my-appointments redesigns → **phase 2**
- Admin dashboard, dispatch board, customers list, ops, vans, supplies, marketing, formation, etc. → **phase 3**
- Tech dashboard (`tech/tech_dashboard_live.ex`) → **phase 4** (mobile-first audit needed first)
- Native mobile app UI (separate project)
- Visual regression tooling (Percy / Chromatic)
- A/B testing framework
- Marketing site separation
- SEO / structured data improvements
- Performance optimization (CSS bundle size, image optimization)
- Accessibility WCAG AA audit (warrants its own phase-5 spec)
- Wallaby mobile-viewport tests (would double runtime — phase-2)
- Cash flow Wallaby coverage (relying on existing LiveView tests for that page)

---

## File architecture

| Action | Path | Notes |
|---|---|---|
| Modify | `assets/css/app.css` | New tokens replacing existing daisyUI theme blocks |
| Modify | `lib/mobile_car_wash_web/components/core_components.ex` | Add `kpi_card`, `bucket_card`, `status_pill`, `progress_bar`, `empty_state`, `data_table`; refresh `button` / `input` / `card` / `modal` / `flash` |
| New | `lib/mobile_car_wash_web/components/marketing_components.ex` | Customer-facing only: `hero`, `service_tier_card`, `tech_section`, `testimonial`, `cta_band`, `feature_grid` |
| Modify | `lib/mobile_car_wash_web/live/landing_live.ex` | Full markup rewrite against new components |
| Modify | `lib/mobile_car_wash_web/live/booking_live.ex` | Markup rewrite (preserve event handlers + state machine + Stripe + geocoding) |
| Modify | `lib/mobile_car_wash_web/live/booking_success_live.ex` | Full rewrite |
| Modify | `lib/mobile_car_wash_web/live/admin/cash_flow_live.ex` | Replace bucket diagram region; restructure layout per Section "Cash flow redesign" |
| Modify | `lib/mobile_car_wash_web/live/admin/components/cash_flow_components.ex` | New `kpi_hero`, `bucket_grid`, `status_indicator`; remove `bucket_diagram` and any helpers it uses (animation, coin emoji, gradient defs) |
| Modify | `lib/mobile_car_wash_web/live/admin/style_guide_live.ex` | Update to showcase the new component vocabulary |
| Delete | `assets/js/hooks/diagram_scroll.js` | Auto-pan no longer needed — bucket diagram is gone |
| Modify | `assets/js/app.js` | Remove `DiagramScroll` hook registration |
| New | `lib/mobile_car_wash/cash_flow/health.ex` | Pure module: `summarize/1` + `salary_recommendation/1` |
| New | `test/mobile_car_wash/cash_flow/health_test.exs` | Unit tests for the health helper |
| New | `priv/static/images/logo_v2_light.svg`, `logo_v2_dark.svg`, `logo_v2_icon.svg` | Refreshed brand marks |
| New | `priv/static/images/og-share-v2.png` | Refreshed OG image (1200×630) |
| Replace | `priv/static/images/favicon-*.png` | Regenerate favicons from new icon |
| Modify | various Swoosh email templates | Restyle headers, buttons, type to match new system |
| Modify | `mix.exs` | Wallaby: change `runtime: false` → activate (drop the flag or set true) |
| Modify | `config/test.exs` | Wallaby + ChromeDriver + sql_sandbox config |
| Modify | `lib/mobile_car_wash_web/endpoint.ex` | Add `Phoenix.Ecto.SQL.Sandbox` plug under compile-env guard |
| Modify | `test/test_helper.exs` | Start Wallaby + base_url |
| New | `test/support/feature_case.ex` | Wallaby base case |
| New | `test/features/booking_golden_path_test.exs` | E2E test 1 |
| New | `test/features/customer_auth_test.exs` | E2E test 2 |
| New | `test/features/admin_dispatch_test.exs` | E2E test 3 |
| New | `test/features/subscription_signup_test.exs` | E2E test 4 |
| New | `test/features/subscription_cancel_test.exs` | E2E test 5 |
| Delete | `test/features/customer_booking_test.exs` | Misnamed `ConnCase` — replaced by real Wallaby tests |
| Delete | `test/features/guest_checkout_test.exs` | Misnamed `DataCase` — replaced by real Wallaby tests |
| Modify | `.gitignore` | Add `.superpowers/` entry |

### Constraints honored

- Existing 113-test suite stays green throughout (no behavior changes, only markup + components — assertion text updates are part of each page's work)
- Tailwind + daisyUI stay (no framework swap — one churn at a time)
- Stripe Elements styling updated via Stripe.js options to match new palette
- Existing `style_guide_live.ex` becomes the living documentation

---

## Design system

### Tokens

**Brand palette**

| Token | Hex | Use |
|---|---|---|
| `surface` | `#f8fafc` | Page background |
| `card` | `#ffffff` | Card background |
| `primary` | `#1e293b` | Primary buttons, dark sections |
| `accent` | `#06b6d4` | Accent (cyan), conversion CTAs, highlights |
| `ink` | `#0f172a` | Body text, headlines |

**Semantic palette**

| Token | Hex | Use |
|---|---|---|
| `success` | `#16a34a` | Confirmed, paid, on target |
| `warning` | `#f59e0b` | Underfunded, attention |
| `danger` | `#dc2626` | Errors, withdrawals |
| `info` | `#0e7490` | Auto / system actions |

**Neutral ramp:** Tailwind native `slate-50` (`#f8fafc`) through `slate-900` (`#0f172a`).

**Typography**

| Style | Spec |
|---|---|
| Display heading | Inter 32/700/-1px tracking |
| Section heading | Inter 22/600/-0.4px tracking |
| Body | Inter 14/400/1.55 line-height |
| Label | Inter 11/600/uppercase/0.5px tracking |
| Financial figure | JetBrains Mono 16+/600/tabular numerals |

**Spacing scale:** Tailwind native (4/8/12/16/24/32/48/64/96 px).
**Radii:** sm 4px, md 8px (default), lg 12px, xl 16px, 2xl 24px (cards).
**Shadows:** sm (inputs), md (cards at rest), lg (hover/elevated).
**Container max-width:** marketing 1280px, admin 1440px.

### Component vocabulary

**Marketing-only** (`marketing_components.ex`):
- `<.hero headline subhead primary_cta secondary_cta? trust_strip?>`
- `<.service_tier_card name price duration features cta highlighted={false}>`
- `<.tech_section>` — the dark cyan-glow section with route-map / SMS preview
- `<.testimonial quote name vehicle?>` — placeholder data initially
- `<.cta_band>` — full-width navy band with conversion CTA
- `<.feature_grid columns={2|3|4}>` — icon + headline + body items

**Application UI** (`core_components.ex`):
- `<.button variant={:primary|:secondary|:ghost|:destructive} size={:sm|:md|:lg}>` (refresh)
- `<.input>`, `<.select>`, `<.textarea>` (refresh)
- `<.card>` with optional `:header`, `:body`, `:footer` slots
- `<.modal>` (refresh)
- `<.kpi_card label value delta? sparkline? subtext?>`
- `<.bucket_card label amount target_pct status status_label>`
- `<.status_pill status={:on_target|:underfunded|:paid|:over|:long_term}>`
- `<.progress_bar value variant={:cyan|:amber|:green|:red}>`
- `<.empty_state icon title body action?>`
- `<.flash>`, `<.toast>` (refresh)
- `<.data_table columns rows>`
- `<.nav>` (admin top nav refresh)

**Estimated count to build/refresh:** 18 components, ~6 net-new.

---

## Cash flow page redesign

### Layout (top to bottom)

1. **Page header** — "Cash flow" title + breadcrumb label, month selector, "+ Add transaction" CTA
2. **Health summary band** — gradient cyan banner with proactive guidance sentence + flag list. Source: `CashFlow.Health.summarize/1`.
3. **KPI hero card** — total cash on hand (sum of all bucket balances), MoM delta, comparison line, sparkline (last 7 weeks of weekly totals)
4. **Bucket grid** — 5 cards (Operating / Tax / Savings / Investment / Salary). Each: label, status pill, dollar amount (mono), "of $X goal", thin progress bar in semantic color.
5. **Action row** — 4 secondary buttons (Deposit / Withdraw / Rebalance / Pay salary) — each opens the existing modal
6. **Recent transactions table** — date, description, flow direction, signed amount (color-coded ± monospace), status pill (CLEARED / AUTO / PENDING). "View all" link.

### Pain → solution mapping

| Pain (ranked) | Solution |
|---|---|
| A — diagram looks amateurish | Replace SVG bucket art + animated coins with KPI card grid (Mercury / Wise vibe). No emoji, no animation. |
| B — cluttered | Strict 6-region vertical stack with 16px gaps. Hierarchy: status → cash → buckets → actions → history. |
| C — doesn't tell a story | New Health summary band at top. Computed from bucket states + thresholds. Examples: "Healthy — pay yourself $X" / "Operating low, $Y short of buffer" / "Tax reserve underfunded by $Z, recommend cascade now". |
| D — mobile broken | Bucket grid 5→2→1 col at md/sm. KPI hero stacks (sparkline below number). Transactions become card-list on sm. Action row 4-col → 2x2 on sm. |

### What stays

- All Ash actions, balance guards, cascade logic, PubSub broadcasting, transaction logging — **untouched**
- All 5 modal forms (deposit, withdraw, transfer, salary, config) — keep behavior, restyle only
- LiveView event handlers — kept (animation toggle becomes a no-op until removed in next release)

### What gets removed

- `bucket_diagram/1` in `cash_flow_components.ex` (the animated SVG)
- `DiagramScroll` JS hook (`assets/js/hooks/diagram_scroll.js`)
- Animation toggle UI
- Coin emoji + flow path animations
- `animations_enabled` socket assign (kept one release for safety, then removed)

### New helper

**`MobileCarWash.CashFlow.Health`** — pure module, no Ash deps:
- `summarize(state) :: %{status: :healthy | :warning | :critical, headline: String.t(), details: [String.t()]}` — takes bucket balances + thresholds + monthly opex
- `salary_recommendation(state) :: integer()` — max safe salary draw given current state, used by the headline

Tested independently in `test/mobile_car_wash/cash_flow/health_test.exs`.

---

## Customer-facing redesigns

### Landing page

Top-to-bottom regions:

1. **Top nav** — logo + "How it works" / "Pricing" / "Sign in" / "Book a wash" CTA
2. **Hero** — trust badge ("San Antonio · Licensed & Insured"), headline, subhead, dual CTA (primary + "See pricing")
3. **How it works** — 3-step grid (Book / We come / Pay when done) with numbered cyan badges
4. **Pricing tiers** — 2 cards: Basic Wash $50, Premium $199.99 (the higher-tier card gets the cyan border + "MOST POPULAR" badge to draw the eye to the higher AOV option). Per-tier Book button.
5. **Tech credibility section** (dark cyan-glow strip) — "We tell you exactly when we'll arrive." 15-min windows, live SMS, before/after photos. Right side: stylized SMS conversation preview.
6. **CTA band** — final conversion push
7. **Footer** — minimal: copyright, location, Privacy / Terms

Data sources unchanged: `ServiceType` + `SubscriptionPlan` from Ash.

**Copy:** all hero / section / tier copy marked `<!-- COPY: TBD -->`. Requires a copy pass before merge.

### Booking page (`booking_live.ex`)

Behavior preserved, markup rewritten.

- **Sticky progress indicator** at top: `Address → Service → Time → Pay → Done`. Current step in cyan.
- **Single-column 600px max-width** content area
- **Per step:** section heading (22/600), helper subhead, large 48px-tap-target inputs, primary CTA at bottom, secondary "Back" link
- **Address step** — single input with autocomplete, map preview below once selected
- **Service step** — 2 service tier cards, pick one
- **Time step** — calendar grid + time-slot chips. Mobile: scrollable horizontal date strip.
- **Pay step** — Stripe Payment Element embedded, trust copy ("No charge until job complete"), summary card right (desktop) / above (mobile) with service + time + total
- **Mobile sticky footer CTA** pinned to bottom

**State machine, validation, Stripe integration, geocoding, route-distance pricing — unchanged.**

### Booking success page (`booking_success_live.ex`)

1. **Success header** — large cyan check icon, "Booking confirmed", "We've sent confirmation to {email}" subhead
2. **Booking summary card** — date/time, service name, address, total
3. **"What happens next"** — 3-step explainer (text the day before / 15-min arrival window / card charged after job + photo proof)
4. **Calendar download** — "Add to Apple/Google calendar" button with `.ics`
5. **Track appointment CTA** — primary button → `/appointments`
6. **Soft upsell** — small dismissible banner: "Save 20% with a monthly plan →"

---

## Wallaby integration

### Setup

**`mix.exs`** — change `{:wallaby, "~> 0.30", only: :test, runtime: false}` to `{:wallaby, "~> 0.30", only: :test}`.

**`config/test.exs`** additions:

```elixir
config :mobile_car_wash, MobileCarWashWeb.Endpoint,
  http: [port: 4002],
  server: true

config :wallaby,
  driver: Wallaby.Chrome,
  chromedriver: [
    headless: true,
    binary: System.get_env("CHROMEDRIVER_PATH", "chromedriver")
  ],
  screenshot_on_failure: true,
  screenshot_dir: "test/screenshots",
  base_url: "http://localhost:4002"

config :mobile_car_wash, sql_sandbox: true
```

**`lib/mobile_car_wash_web/endpoint.ex`** — add sandbox plug under compile-env guard:

```elixir
if Application.compile_env(:mobile_car_wash, :sql_sandbox) do
  plug Phoenix.Ecto.SQL.Sandbox, repo: MobileCarWash.Repo
end
```

**`test/test_helper.exs`** — start Wallaby:

```elixir
{:ok, _} = Application.ensure_all_started(:wallaby)
Application.put_env(:wallaby, :base_url, MobileCarWashWeb.Endpoint.url())
Ecto.Adapters.SQL.Sandbox.mode(MobileCarWash.Repo, :manual)
ExUnit.start()
```

**`test/support/feature_case.ex`** — base case:

```elixir
defmodule MobileCarWashWeb.FeatureCase do
  use ExUnit.CaseTemplate
  using do
    quote do
      use Wallaby.Feature
      import MobileCarWashWeb.Router.Helpers
      @endpoint MobileCarWashWeb.Endpoint
    end
  end
end
```

**Dev / CI:** add `chromedriver` to `Brewfile` (Mac) and CI install (`brew install chromedriver` / `apt-get install chromium-driver`). Document local-run command: `mix test --only feature`. Tag each test with `@tag :feature` so they're excluded from default `mix test` runs.

**Cleanup:** delete `test/features/customer_booking_test.exs` and `test/features/guest_checkout_test.exs` (misnamed `ConnCase` / `DataCase` — replaced by real Wallaby tests).

### Test plan (5 tests)

**Test 1 — `booking_golden_path_test.exs`**
- Given a guest visitor + 2 seeded service tiers (Basic $50, Premium $199.99) + 1 future open `AppointmentBlock`
- When they: visit landing → click "Book a wash" → enter address (mocked geocode → fixed lat/lng inside service area) → pick the Premium tier → pick the open block → fill name/email/phone + Stripe Payment Element (test card 4242…) → click "Confirm booking"
- Then: lands on `/booking/success` with confirmation visible; DB has 1 new `Appointment` `status: :pending` and a Stripe PaymentIntent id

**Test 2 — `customer_auth_test.exs`**
- Given a registered customer with 2 past appointments
- When they sign in via `/sign-in` → click "My appointments"
- Then list shows both appointments chronologically with correct status pills

**Test 3 — `admin_dispatch_test.exs`**
- Given an admin user + 3 pending appointments for today
- When they sign in → navigate to `/admin/dispatch` → click "Confirm" on appointment #2
- Then row updates to `status: :confirmed` (status-pill change visible), button changes Confirm → Cancel

**Test 4 — `subscription_signup_test.exs`**
- Given a guest visitor + 1 active subscription plan ($79/mo)
- When they hit `/subscriptions` → click "Subscribe" → complete Stripe checkout (test card)
- Then redirected to `/subscription/success`, DB has 1 new `Subscription` row + Stripe subscription id

**Test 5 — `subscription_cancel_test.exs`**
- Given a customer with an active subscription
- When they sign in → navigate to `/subscriptions/manage` → click "Cancel" → confirm modal
- Then subscription `status: :canceled`, confirmation message visible

### Mocking strategy

- **Stripe** — real HTTP to Stripe test mode using the success test card (4242 4242 4242 4242). No mocking of the Stripe library itself.
- **Geocoding** — `Mox` stub returning fixed coordinates inside the 78261 service area. Real geocoder stays for prod.
- **SMS / Twilio** — `Mox` stub. Stub asserts the message was constructed correctly (no real SMS during tests).
- **Email / Swoosh** — already in test mode; assert via `Swoosh.TestAssertions`.

### Runtime estimate

~8-15s per test with ChromeDriver + Stripe round-trip. 5 tests ≈ 60-90s. Run as separate `--only feature` target; CI parallelizable via `--max-cases`.

---

## Brand assets

| Asset | Action | Notes |
|---|---|---|
| Logos (light/dark/icon) | Create v2 SVGs at `priv/static/images/logo_v2_*.svg` | Cyan-accented mark + Inter wordmark "Driveway Detail Co". Existing files stay until v2 ships, then deleted. 1-2 hour design pass on the SVG outputs is approved scope. |
| OG share image | Replace `og-share.png` with `og-share-v2.png` (1200×630) | New design: hero headline + cyan-accented mark + service van photo |
| Favicon | Regenerate from new icon | 16 / 32 / 180 / 192 / 512 sizes |
| Email templates | Restyle Swoosh templates | Confirmation, subscription welcome, cancellation, password reset |
| Stripe Checkout branding | Update via Stripe Dashboard `branding` settings | Match payment page to site palette |
| `<meta name="theme-color">` | Set to `#1e293b` (primary ink) | Mobile browser chrome |

---

## Mobile strategy

**Breakpoints:** Tailwind defaults — `sm` 640 / `md` 768 / `lg` 1024 / `xl` 1280.

| Page | Mobile rule |
|---|---|
| Landing | Hero stacks vertically; 3-step grid → 1-col stack at sm; pricing tiers stack vertically (Premium still highlighted); tech section flips to single column |
| Booking | Single column always; sticky bottom CTA; date/time picker becomes scrollable horizontal strip |
| Booking success | Already single column; just scales |
| Cash flow | Bucket grid 5→2→1 col; KPI sparkline drops below number; transactions become card list; action row stays 2x2 |

**Touch targets:** primary actions ≥44×44px (Apple HIG); inputs ≥48px tall.

---

## Risks

1. **Stripe Elements styling collision** — Stripe iframes need explicit color/font config via Stripe.js options. If forgotten, Payment Element looks 2015 on a 2026 page. **Mitigation:** dedicated subtask in implementation plan.
2. **OAuth provider button branding** — out of scope today; flagged for phase 2 if added.
3. **Email rendering across clients** — restyled emails should be Litmus / EmailOnAcid reviewed. Out of scope, noted as follow-up.
4. **Copy review burden falls on PR diff** — implementer drafts copy using best judgement; user reviews in PR. Watch claims especially (insurance, bonded, "licensed") — must be true and verifiable, not aspirational marketing.
5. **No visual regression tooling** — CSS changes can silently break a page nobody Wallaby-tests. Mitigation: existing 113-test LiveView suite catches structural breaks; visual breaks caught by manual eyeball during dev.
6. **Animated bucket diagram nostalgia** — spec deletes it. If you miss it, that's a phase-2 "fun mode" toggle, not the default.
7. **Existing 113 tests assert HTML strings** — many tests look for specific text or class names. Markup rewrites will break some. Plan: re-run suite after each page rewrite, fix assertions inline as part of each page's work.
8. **Brand convention** — wordmark is "Driveway Detail Co", legal copy is "Driveway Detail Co. LLC". Implementer must use the right one in the right place (wordmark in hero/nav/buttons; full LLC name in footer / Terms / Privacy / receipts).

---

## Resolved decisions (formerly open questions)

1. **Brand name** — wordmark = "Driveway Detail Co". Legal/footer copy = "Driveway Detail Co. LLC". Domain stays `drivewaydetailcosa.com`.
2. **Pricing tiers** — 2 tiers, matching existing seed code: Basic Wash $50, **Premium $199.99** (renamed from "Deep Clean & Detail"). The 3-tier mockup from brainstorming is replaced by this 2-tier reality.
3. **Hero / section copy** — implementer to draft using best judgement; user reviews in PR diff.
4. **Logo SVG outputs** — 1-2 hour design pass granted.
5. **Subscription price for Test 4** — $79/mo confirmed.

---

## Effort estimate

| Block | Estimate |
|---|---|
| Design system tokens + base components | 1-2 days |
| Cash flow page redesign | 1-2 days |
| Landing page redesign | 1-2 days |
| Booking page rewrite (1308 lines) | 2-3 days |
| Booking success page | 0.5 day |
| Brand asset rework | 1 day (plus your design refinement time) |
| Wallaby setup + 5 tests | 2 days |
| Bug fixing + existing-test updates | 1-2 days |
| **Total** | **~10-15 days** of focused work |

---

## Subsequent phases (out of scope here)

- **Phase 2** — auth/sign-in, subscription manage, my-appointments redesigns against the same system (~1 week)
- **Phase 3** — admin dashboard, dispatch, customers, ops redesigns (~1-2 weeks)
- **Phase 4** — tech dashboard mobile-first redesign (~3-5 days)

Each phase gets its own spec + plan + implementation cycle.
