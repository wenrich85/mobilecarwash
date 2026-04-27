# Plan 3a — Marketing Components + Landing Page Design

**Date:** 2026-04-26
**Status:** Draft (pending user review)
**Parent spec:** [2026-04-26-phase1-redesign-and-wallaby-design.md](2026-04-26-phase1-redesign-and-wallaby-design.md) — see "Customer-facing redesigns" section
**Author:** Brainstormed with Claude

---

## TL;DR

First of three Plan-3 sub-plans (3a / 3b / 3c). Adds a `MarketingComponents` module with 6 customer-facing components (`hero`, `service_tier_card`, `tech_section`, `testimonial`, `cta_band`, `feature_grid`) and rewrites the landing page (`landing_live.ex`) to use them.

Builds on Plan 1's design tokens and Plan 2's brand assets. Booking page rewrite is **Plan 3b** (separate plan, ~3 days). Booking success page is **Plan 3c**.

---

## Scope

### In scope

- New `MobileCarWashWeb.MarketingComponents` module — 6 reusable customer-facing components
- Component test file (~15 tests, one describe block per component)
- Full markup rewrite of `lib/mobile_car_wash_web/live/landing_live.ex` against the new components
- Drafted copy throughout (this spec is the source of truth — see "Drafted copy" section)
- Update existing landing tests that assert old markup
- Drop unused `SubscriptionPlan` load from `mount/3` (subscriptions not on landing in new design)

### Explicitly out of scope (deferred)

- Booking page rewrite → **Plan 3b**
- Booking success page rewrite → **Plan 3c**
- Sign-in / register / subscription manage page redesigns → phase-2 spec
- Real testimonial copy (3 placeholder quotes ship; user replaces pre-launch)
- Real customer photography / illustrations
- A/B testing framework
- i18n / translations (English only)
- Mobile sticky-CTA button (could be added later as a separate spec)
- Smooth-scroll CSS for anchor links (one-line follow-up)
- Subscription plan promotion on landing (not in new design)

---

## File architecture

| Action | Path | Notes |
|---|---|---|
| New | `lib/mobile_car_wash_web/components/marketing_components.ex` | 6 customer-facing components |
| New | `test/mobile_car_wash_web/components/marketing_components_test.exs` | ~15 tests, one describe per component |
| Modify | `lib/mobile_car_wash_web/live/landing_live.ex` | Full template rewrite; mount/3 keeps loading ServiceType, drops SubscriptionPlan |
| Modify | `test/mobile_car_wash_web/live/landing_live_test.exs` | Update assertions for new markup |

### Constraints honored

- Plan 1's design tokens used everywhere (no new tokens)
- Plan 2's logo assets (`logo_light_v2.svg`, `logo_icon_v2.svg`) referenced in nav
- All ~1017 tests stay green; landing-specific tests get assertion updates
- `mount/3` keeps loading `ServiceType` records via Ash (data preserved, only render template changes)
- Layout root (`root.html.heex`) untouched — nav and footer come from the page template, not the layout

---

## Component vocabulary

### `<.hero>`

```elixir
attr :headline, :string, required: true
attr :subhead, :string, required: true
attr :trust_badge, :string, default: nil
slot :primary_cta, required: true
slot :secondary_cta
```

Centered hero with optional badge above headline (uppercase mono / cyan-700), large display headline (Inter 700 / 36-48px / -1.2px tracking), subhead (Inter 400 / 16px / slate-600), and one or two CTAs side by side. White background. Vertical padding 48px desktop / 36px mobile.

### `<.service_tier_card>`

```elixir
attr :name, :string, required: true
attr :price, :string, required: true
attr :duration, :string, required: true
attr :features, :list, required: true
attr :highlighted, :boolean, default: false
slot :cta, required: true
```

Vertical card. Tier label (slate-500 / uppercase / 12px), price (Inter 700 / 28px / mono), duration (slate-500 / 12px), feature list with `✓` prefixes, CTA button slot at bottom. Highlighted variant: `border-2 border-cyan-500` and a "MOST POPULAR" pill in the top-right.

### `<.tech_section>`

```elixir
attr :eyebrow, :string, default: "[ HOW WE'RE DIFFERENT ]"
attr :headline, :string, required: true
attr :subhead, :string, required: true
attr :bullets, :list, default: []
slot :preview
```

Two-column dark section. Slate-900 background with cyan radial-gradient glow in upper-right. Mono eyebrow label, Inter headline, slate-400 subhead, optional arrow-prefixed bullets in slate-300. Right column renders the `:preview` slot. Full-bleed background; content max-width 1280px.

### `<.testimonial>`

```elixir
attr :quote, :string, required: true
attr :name, :string, required: true
attr :vehicle, :string, default: nil
```

Single quote card: large opening quote mark in cyan, italic body (Inter 400 / 16px), attribution row with name (semibold) + optional vehicle (slate-500). White card on slate-50 background. The grid that holds testimonials is rendered by the consumer.

### `<.cta_band>`

```elixir
attr :headline, :string, required: true
attr :subhead, :string, required: true
slot :cta, required: true
```

Full-width centered conversion band. White background, slate-900 headline (24px), slate-500 subhead (14px), CTA button. Sits between testimonials and footer.

### `<.feature_grid>`

```elixir
attr :columns, :integer, default: 3, values: [2, 3, 4]
slot :item, required: true do
  attr :number, :string
  attr :title, :string, required: true
end
```

Numbered grid. Each `:item` slot gets a numbered cyan badge (28px rounded square), bold title (Inter 600 / 14px), body text (the slot's inner content / slate-500 / 13px). Used for "How it works" 3-step section.

### Component tests

`test/mobile_car_wash_web/components/marketing_components_test.exs` — one `describe` block per component (6 total), 2-3 tests each:
- Required attrs render their values
- Slots render correctly
- Variants emit expected classes (highlighted tier, columns count)
- ~15 tests total

---

## Landing page structure (top to bottom)

```
1. Top nav (rendered inline in landing_live, not a layout)
   ├── Logo (logo_light_v2.svg, ~32px tall)
   └── Right side: "Sign in" link + primary "Book a wash" button
   Mobile (< sm): hide "Sign in", keep logo + CTA only

2. <.hero>
   ├── trust_badge: "SAN ANTONIO · LICENSED & INSURED"
   ├── headline: "Your car, washed where you parked it."
   ├── subhead: "Book in 30 seconds. We come to you. Pay when it's done."
   ├── primary_cta: "Book my first wash" → /booking
   └── secondary_cta: "See pricing" → #pricing

3. <.feature_grid columns={3}>
   Section eyebrow: "HOW IT WORKS"
   Section heading: "Three steps. No hose hookup."
   Items:
   ├── 1. Book online — "Pick a service, pick a time, enter your address. 30 seconds."
   ├── 2. We come to you — "SMS update with our 15-minute arrival window. Self-contained van — no hose, no power needed."
   └── 3. Pay when done — "No deposit. Card charged after the job. Photos before and after for your records."

4. Pricing tiers (#pricing — id'd anchor)
   Section eyebrow: "PRICING"
   Section heading: "Two tiers. No hidden fees."
   Two <.service_tier_card> components side-by-side desktop / stacked mobile:
   ├── Basic Wash ($50, ~45 min) — exterior hand wash, wheels & tires, window streak-free, quick interior vacuum — CTA "Book Basic"
   └── Premium ($199.99, ~3 hours, highlighted) — everything in Basic + full interior wipe-down + shampoo carpets & seats + leather treatment + tire shine + wax coat + engine bay detail — CTA "Book Premium"
   Data source: ServiceType records loaded in mount/3; "MOST POPULAR" highlight hardcoded for Premium.

5. <.tech_section>
   ├── eyebrow: "[ HOW WE'RE DIFFERENT ]"
   ├── headline: "We tell you exactly when we'll arrive."
   ├── subhead: "Most mobile washes give you a 4-hour window. We give you 15 minutes — and SMS the moment we're 5 minutes out."
   ├── bullets: 3 strings (see Drafted Copy section)
   └── :preview slot: stylized SMS conversation (3 messages, slate-900 chat bubbles, cyan brand label)

6. Testimonials grid
   Section heading: "What customers say"
   3 <.testimonial> components in a 3-col grid (collapses to 2 at md, 1 at sm)
   ALL placeholder content marked <!-- COPY: TBD -->

7. <.cta_band>
   ├── headline: "Ready for a clean car without the trip?"
   ├── subhead: "First wash, no commitment. Book in 30 seconds."
   └── cta: "Book my first wash →" → /booking

8. Footer (rendered inline in landing_live)
   Single row, slate-50 bg, slate-500 text:
   Left: "© 2026 Driveway Detail Co. LLC · San Antonio, TX · Veteran-owned"
   Right: "Privacy" · "Terms" · "Sign in" links
```

### Data flow (preserved)

`mount/3` continues to load `ServiceType` records via Ash query (tenant-scoped if applicable).

`SubscriptionPlan` load is **dropped** from `mount/3` — subscriptions are not on landing in the new design (separate page in phase-2). If references to `@subscription_plans` exist in any helper component or partial referenced by landing, those references must be removed cleanly. Implementer should grep for `subscription_plans` in `landing_live.ex` and adjacent files.

---

## Drafted copy (this is the source of truth — final unless flagged)

### 1. Top nav

- Logo: `logo_light_v2.svg`
- Right links: "Sign in" link, "Book a wash" button

### 2. Hero

- Trust badge: **SAN ANTONIO · LICENSED & INSURED**
- Headline: **Your car, washed where you parked it.**
- Subhead: **Book in 30 seconds. We come to you. Pay when it's done.**
- Primary CTA: **Book my first wash** → `/booking`
- Secondary CTA: **See pricing** → `#pricing`

### 3. How it works

- Section eyebrow: **HOW IT WORKS**
- Section heading: **Three steps. No hose hookup.**
- Step 1: title **Book online** · body `Pick a service, pick a time, enter your address. 30 seconds.`
- Step 2: title **We come to you** · body `SMS update with our 15-minute arrival window. Self-contained van — no hose, no power needed.`
- Step 3: title **Pay when done** · body `No deposit. Card charged after the job. Photos before and after for your records.`

### 4. Pricing tiers

- Section eyebrow: **PRICING**
- Section heading: **Two tiers. No hidden fees.**

**Basic Wash** — `$50` — `~45 min`
- Exterior hand wash
- Wheels & tires
- Window streak-free finish
- Quick interior vacuum
- CTA: `Book Basic`

**Premium** — `$199.99` — `~3 hours` — *MOST POPULAR* badge
- Everything in Basic
- Full interior wipe-down
- Shampoo carpets & seats
- Leather treatment
- Tire shine + wax coat
- Engine bay detail
- CTA: `Book Premium`

### 5. Tech credibility section

- Eyebrow: `[ HOW WE'RE DIFFERENT ]` (mono font)
- Headline: **We tell you exactly when we'll arrive.**
- Subhead: `Most mobile washes give you a 4-hour window. We give you 15 minutes — and SMS the moment we're 5 minutes out.`
- Bullets:
  - `→ 15-minute arrival windows, not "morning" or "afternoon"`
  - `→ Live SMS updates as your tech approaches`
  - `→ Photos of your car before and after every wash`

**SMS preview content (right column):**
```
Driveway · 9:42 AM
Hi Maria — Jordan is 8 minutes away.
He'll text again when he's pulling up. 🚐

Driveway · 9:50 AM
Pulling into your driveway now.
Wash should take about 45 min.
```

### 6. Testimonials

- Section heading: **What customers say**
- 3 placeholder testimonials, each marked `<!-- COPY: TBD - replace with real customer quote pre-launch -->`:

> Placeholder 1: `"Showed up exactly on time and my car looked brand new. Worth every penny."` — `Maria G.` · `2023 Tesla Model 3`

> Placeholder 2: `"I work from home and didn't even have to stop my Zoom call. They just did their thing in the driveway."` — `Marcus T.` · `2021 Toyota 4Runner`

> Placeholder 3: `"The detail job on my truck was unreal. Carpets I'd written off look new again."` — `Brittany R.` · `2018 Ford F-150`

### 7. Final CTA band

- Headline: **Ready for a clean car without the trip?**
- Subhead: `First wash, no commitment. Book in 30 seconds.`
- CTA: **Book my first wash →** → `/booking`

### 8. Footer

- Left: `© 2026 Driveway Detail Co. LLC · San Antonio, TX · Veteran-owned`
- Right links: **Privacy** · **Terms** · **Sign in**

---

## Mobile behavior

Tailwind breakpoints — `sm` 640 / `md` 768 / `lg` 1024.

| Region | Mobile rule |
|---|---|
| Top nav | "Sign in" hides below `sm`, leaves logo + "Book a wash" button only |
| Hero | Headline drops to 30px; subhead stays 16px; CTAs stack vertically (full-width) below `sm` |
| How it works | 3-col grid → 1-col stack at `sm` |
| Pricing tiers | 2-col grid → 1-col stack at `sm`; Premium retains highlight + "MOST POPULAR" badge |
| Tech section | 2-col → 1-col stack; SMS preview drops below the type |
| Testimonials | 3-col → 2-col at `md` → 1-col at `sm` |
| CTA band | Already centered single-column; just scales |
| Footer | Right-aligned links wrap to second line below copyright on mobile |

**Touch targets:** all buttons + links ≥44×44px (Apple HIG). Pricing CTAs use `min-h-12` to enforce.

**Sticky elements:** none. Page scrolls cleanly.

---

## Risks

1. **Inter font swap-FOUC.** First visit before Inter caches: hero briefly renders in fallback fonts. Acceptable trade — `swap` is right for above-the-fold text.
2. **Existing landing tests assert old markup.** Implementer updates these as part of this plan, not separate cleanup.
3. **`SubscriptionPlan` removal may surface broken references** in helper components or partials. Grep for `subscription_plans` in adjacent files.
4. **Anchor `#pricing` jump smoothness.** Modern browsers handle it. CSS `scroll-behavior: smooth` is a one-line follow-up if desired.
5. **Real testimonials never get added.** Mitigation: explicit pre-launch checklist item — "Replace 3 placeholder testimonials in `landing_live.ex` with real customer quotes."
6. **Logo at small mobile widths.** Wordmark gets small below `sm`. Mitigation: swap to `logo_icon_v2.svg` (icon only) below `sm` breakpoint via Tailwind `hidden`/`block` utilities.

---

## Open questions / TBDs (carried forward)

1. **Real testimonial quotes** — replace before launch.
2. **Subscription plan promotion** — not on landing; add a separate page in phase-2 if subscriptions matter for early conversion.
3. **Mobile sticky CTA** — separate spec if conversion data shows we need it.
4. **`scroll-behavior: smooth` CSS** — one-line follow-up.

---

## Effort estimate

| Block | Estimate |
|---|---|
| MarketingComponents module + 6 components + tests | 0.5 day |
| Landing page template rewrite | 0.75 day |
| Updating existing landing tests | 0.25 day |
| **Total** | **~1.5 days** of focused work |
