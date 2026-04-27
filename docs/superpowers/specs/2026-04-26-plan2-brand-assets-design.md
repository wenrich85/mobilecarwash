# Plan 2 — Brand Assets Design

**Date:** 2026-04-26
**Status:** Draft (pending user review)
**Parent spec:** [2026-04-26-phase1-redesign-and-wallaby-design.md](2026-04-26-phase1-redesign-and-wallaby-design.md) — see "Brand assets" section
**Author:** Brainstormed with Claude

---

## TL;DR

Plan 2 of 5 in the phase-1 visual reboot. Replaces the old navy/steel-blue water-drop brand identity with a slate + cyan **pin-and-drop** mark, single-line "Driveway Detail Co" wordmark, refreshed OG share image, regenerated favicons, and a fully refactored email system using a shared Swoosh layout module. Also fixes a long-standing email-sender domain bug (`noreply@mobilecarwash.com` → `noreply@drivewaydetailcosa.com`).

Builds on Plan 1's design tokens (`#1e293b` slate primary, `#06b6d4` cyan accent, Inter typography). All Plan 2 work is `_v2`-suffixed alongside the existing assets — old files stay one release for safety, get deleted in a later cleanup.

---

## Scope

### In scope

- **3 logo SVGs** — icon-only, light-theme wordmark, dark-theme wordmark (pin+drop concept, slate-800 + cyan-500)
- **OG share image** — 1200×630 SVG source plus rasterized PNG for social platforms
- **Favicon set** — 16/32/180/192/512 PNG sizes plus a multi-res `.ico`, all derived from the new icon
- **Email system rewrite** — new `MobileCarWash.Notifications.Email.Layout` module providing `wrap_html/1`, `wrap_text/1`, `button/3`, `link/2`. All 11 existing email functions in `email.ex` refactored to use it.
- **Email sender update** — `@from` constant changed to `Driveway Detail Co <noreply@drivewaydetailcosa.com>`
- **Layout updates** — `root.html.heex` updated to reference the new logo/favicon files, and `theme-color` meta tag updated to `#1e293b`
- **Deployment checklist additions** — DNS records for the new sender domain (DKIM, SPF, DMARC) and Stripe Dashboard branding update

### Explicitly out of scope (deferred)

- Photo or illustration assets (no source available; OG image stays type-and-mark only)
- A `site.webmanifest` for PWA installability — separate follow-up
- Push-notification icons — Plan 5 (mobile work) territory
- Email subject-line copy improvements (style only, copy unchanged)
- Marketing email design (transactional emails only here)
- Unsubscribe page wired to a real route (footer link is a placeholder; real unsubscribe flow is a separate spec)
- Deletion of old `logo_*.svg` / `og-share.png` / favicon files — kept one release for safety

---

## File architecture

| Action | Path | Notes |
|---|---|---|
| New | `priv/static/images/logo_icon_v2.svg` | Pin+drop, 32×40 viewBox, no wordmark |
| New | `priv/static/images/logo_light_v2.svg` | Pin+drop + "Driveway Detail Co" wordmark for light backgrounds |
| New | `priv/static/images/logo_dark_v2.svg` | Inverted: cyan pin + slate-900 drop + slate-50 wordmark for dark backgrounds |
| New | `priv/static/images/og-share-v2.svg` | OG image source, 1200×630 |
| New | `priv/static/images/og-share-v2.png` | Rasterized PNG; built from the SVG via `rsvg-convert` |
| New | `priv/static/images/favicon-v2.ico`, `favicon-v2-16.png`, `favicon-v2-32.png`, `apple-touch-icon-v2.png` (180), `android-chrome-v2-192.png`, `android-chrome-v2-512.png` | All from `logo_icon_v2.svg` |
| New | `lib/mobile_car_wash/notifications/email/layout.ex` | Shared HTML + text layout helpers |
| Modify | `lib/mobile_car_wash/notifications/email.ex` | All 11 email functions refactored to use Layout; `@from` updated |
| Modify | `lib/mobile_car_wash_web/components/layouts/root.html.heex` | Update favicon/icon links to `_v2` paths; update `theme-color` to `#1e293b` |
| New | `test/mobile_car_wash/notifications/email/layout_test.exs` | Tests for `wrap_html/1`, `wrap_text/1`, `button/3`, `link/2` |
| New or Modify | `test/mobile_car_wash/notifications/email_test.exs` | Smoke test per email kind asserting wrap + recipient + subject |
| Modify | `docs/deployment_checklist.md` (or equivalent — locate during plan-write) | Append DNS + Stripe branding sections |

### Constraints honored

- All 992 tests from Plan 1's baseline stay green
- No deletion of existing logo / OG / favicon files (safety; deferred to a cleanup pass)
- Email functions preserve their existing arity, recipient logic, subject text, and link content — only HTML markup and footer change
- Layout helpers use inline styles only (no `<style>` tags — many email clients strip them)

---

## Logo SVG specifications

### Icon-only (`logo_icon_v2.svg`)

**ViewBox:** `0 0 32 40`. Pin shape: rounded teardrop / Material-style map pin. Slate-800 fill (`#1e293b`). Drop nested in pin's bulb: small water-drop, cyan-500 fill (`#06b6d4`). No text, no shine highlight, no extra ornaments — maximum simplicity for clean rendering at favicon (16px) through app-icon (512px) sizes.

Path data:

```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 40" fill="none">
  <!-- Map pin body: rounded teardrop -->
  <path d="M16 3 C9 3 4 8 4 15 C4 22 16 35 16 35 C16 35 28 22 28 15 C28 8 23 3 16 3Z" fill="#1e293b"/>
  <!-- Water drop nested in the bulb -->
  <path d="M16 8 C16 8 12 13 12 16 C12 18 13.7 20 16 20 C18.3 20 20 18 20 16 C20 13 16 8 16 8Z" fill="#06b6d4"/>
</svg>
```

### Light-theme wordmark (`logo_light_v2.svg`)

**ViewBox:** `0 0 240 40`. Icon at `x=0..32`, "Driveway Detail Co" wordmark text at `x=44..` baseline-aligned to icon vertical center. Wordmark: Inter semibold (font-weight 600), 18px size, letter-spacing -0.4px, fill slate-900 (`#0f172a`). Font-family declares Inter with system fallbacks so the SVG renders sensibly even when opened standalone.

### Dark-theme wordmark (`logo_dark_v2.svg`)

**ViewBox:** `0 0 240 40` (same layout as light). Pin: cyan-500 fill (`#06b6d4`). Drop inside pin: slate-900 fill (`#0f172a`) — appears as a cut-out against the cyan pin. Wordmark text: slate-50 (`#f8fafc`).

### Rationale for three files (not a single `currentColor` SVG)

`currentColor` would let one SVG inherit fill from surrounding text. But the two-color mark needs **two distinct color references** (slate pin + cyan drop), email clients ignore CSS `color` on inline SVG, and three files matches the existing Phoenix pattern.

---

## OG share image

**Dimensions:** 1200×630 (Open Graph standard; also fits Twitter Card large image and LinkedIn).

**Background:** `#ffffff`.

**Layout (regions):**

- **Top-left brand strip** (40px from edges): pin+drop icon at 48×60, then "Driveway Detail Co" wordmark, Inter 600 / 24px / slate-900
- **Hero headline** (vertically centered, left-aligned, max width ~720px, 80px from left edge): "Your car, washed where you parked it." Inter 700 / 64px / -1.5px tracking / slate-900 / line-height 1.1
- **Subhead** (32px under headline): "Mobile detailing in San Antonio · Veteran-owned" Inter 400 / 22px / slate-500
- **Bottom-right accent shape:** rounded square 80×80 cyan-500, 40px from edges. Pure visual weight — no text.

### Generation pipeline

Authored as SVG (`og-share-v2.svg`), then rasterized to PNG (`og-share-v2.png`) since social platforms need PNG/JPG, not SVG:

```bash
rsvg-convert -w 1200 -h 630 -f png \
  priv/static/images/og-share-v2.svg \
  -o priv/static/images/og-share-v2.png
```

Both the SVG source AND the rasterized PNG are committed (the PNG as a build artifact). The PNG is what social platforms will fetch; regenerating it requires the SVG source plus `rsvg-convert` (or any SVG-to-PNG tool). Plan 2 includes `rsvg-convert` install instructions (`brew install librsvg` on Mac).

---

## Favicon set

All sizes derived from `logo_icon_v2.svg` via `rsvg-convert` (one-shot generation at plan execution time; resulting PNG/ICO files are committed as build artifacts alongside the canonical SVG source). At 16px the cyan drop becomes invisible; only the slate pin silhouette shows — that's intentional and acceptable, the pin alone is iconic.

| File | Size | Purpose |
|---|---|---|
| `favicon-v2.ico` | 16+32 multi-res | Old browser fallback |
| `favicon-v2-16.png` | 16×16 | Modern browser tab |
| `favicon-v2-32.png` | 32×32 | HiDPI browser tab |
| `apple-touch-icon-v2.png` | 180×180 | iOS Home Screen |
| `android-chrome-v2-192.png` | 192×192 | Android Home Screen |
| `android-chrome-v2-512.png` | 512×512 | PWA / install banner |

`root.html.heex` updated to point its existing `<link rel="icon">` / `apple-touch-icon` tags at the `_v2` paths.

---

## theme-color meta tag

In `root.html.heex` line 22:

- **Was:** `<meta name="theme-color" content="#1E2A38" />`
- **Becomes:** `<meta name="theme-color" content="#1e293b" />`

(Old navy primary → new slate-800. Visually nearly identical but uses the new design token.)

---

## Email system rewrite

### New module: `MobileCarWash.Notifications.Email.Layout`

Four public functions:

```elixir
defmodule MobileCarWash.Notifications.Email.Layout do
  def wrap_html(content_html), do: ...
  def wrap_text(content_text), do: ...
  def button(label, url, variant \\ :primary), do: ...
  def link(label, url), do: ...
end
```

**`wrap_html/1` produces:** doctype + minimal `<html>` head with `meta charset` and `meta viewport`; `<body>` styled max-width 600px centered, slate-100 page background, white card with 24px padding, system font stack (with Inter fallback). **Header:** `logo_light_v2.svg` rendered inline as SVG at 32px height, left-aligned (so email clients render it without external image fetches). **Body slot:** the per-email content. **Footer:** centered `<p>` with "Driveway Detail Co. LLC · San Antonio, TX · Veteran-owned" plus a separate line linking Privacy / Terms / Unsubscribe (placeholders — real unsubscribe flow is out of scope).

**`wrap_text/1` produces:** plain-text header `Driveway Detail Co\n=================\n\n`, then body slot, then footer `\n\n---\nDriveway Detail Co. LLC · San Antonio, TX · Veteran-owned\n`.

**`button/3` variants:**

- `:primary` (default) — cyan-500 background, white text, 12px×24px padding, 8px border-radius
- `:secondary` — slate-100 background, slate-900 text, same dimensions

All inline-styled (no `<style>` tags, no class refs).

**`link/2`** — inline cyan-styled `<a>` for body-text links.

### Refactor of all 11 existing email functions

Each function in `lib/mobile_car_wash/notifications/email.ex` follows the same pattern: build inner HTML + inner text, wrap each via the layout module, set subject + recipient + sender as before. The 11 functions:

1. `verify_email/2`
2. `booking_confirmation/4`
3. `appointment_reminder/4`
4. `deadline_reminder/4` (admin email)
5. `payment_receipt/3`
6. `wash_completed/3`
7. `tech_on_the_way/4`
8. `tech_arrived/4`
9. `booking_cancelled/3`
10. `subscription_created/2`
11. `subscription_cancelled/2`

Subject text, recipient, link contents, and sender (after the `@from` update below) are preserved per-function. Only HTML markup and the wrapping layout change.

### Sender update

```elixir
@from {"Driveway Detail Co", "noreply@drivewaydetailcosa.com"}
```

(Was `{"Mobile Car Wash", "noreply@mobilecarwash.com"}` — both name and address wrong.)

### Tests

- `test/mobile_car_wash/notifications/email/layout_test.exs` (new):
  - `wrap_html/1` produces a `<!doctype html>` document containing the inline SVG logo
  - `wrap_html/1` footer contains "Driveway Detail Co. LLC"
  - `wrap_text/1` produces the header line "Driveway Detail Co" with separator
  - `button/3` defaults to `:primary` and produces inline cyan styles
  - `button/3` with `:secondary` produces slate styles
  - `link/2` produces an inline cyan-styled `<a>` tag

- `test/mobile_car_wash/notifications/email_test.exs` (modify if exists; create if not):
  - One smoke test per email function asserting subject contains expected text, recipient is the customer's email, and HTML body contains the layout's footer string (proves wrapping happened)

---

## Deployment checklist additions

Append to the existing deployment checklist (location to be discovered during plan-write — likely `docs/deployment_checklist.md` or similar per user's MEMORY.md):

```markdown
## Pre-deploy: email sender domain change (Plan 2)

The email sender changed from `noreply@mobilecarwash.com` to
`noreply@drivewaydetailcosa.com`. Before deploying:

- [ ] Add SPF record to drivewaydetailcosa.com DNS:
      `v=spf1 include:<email-provider-spf> ~all`
      (substitute the actual provider — SendGrid, Mailgun, AWS SES, etc.)
- [ ] Add DKIM record(s) per email provider's instructions
      (typically a CNAME or TXT at a provider-specific selector)
- [ ] Add DMARC record:
      Start: `v=DMARC1; p=none; rua=mailto:dmarc@drivewaydetailcosa.com`
      After 1–2 weeks of monitoring with no false positives, tighten to
      `p=quarantine`, then `p=reject`.
- [ ] Verify deliverability with a test email to a Gmail account; check
      that DKIM and SPF show "PASS" in the message headers.
- [ ] Keep the `mobilecarwash.com` MX/SPF/DKIM in place for 30 days
      after launch in case any in-flight email still references the old sender.

## Pre-deploy: Stripe Checkout branding (Plan 2)

The visual reboot needs Stripe to match. In Stripe Dashboard
(Settings → Branding):

- [ ] Upload new icon (`logo_icon_v2.svg` exported as 128×128 PNG)
- [ ] Set primary color to `#06b6d4` (cyan)
- [ ] Set background color to `#ffffff`
- [ ] Update the customer-facing business name to "Driveway Detail Co"
```

---

## Risks

1. **Hand-coded SVG quality.** The pin+drop path data is producible from text, but a polished designer might curve it differently. The plan grants a 1–2 hour design pass on the SVG output; if the v0 looks rough, refine in Figma/Illustrator before merge.
2. **Email DNS records missed.** If DKIM/SPF/DMARC aren't configured before the sender change ships, deliverability tanks silently. The checklist addresses this; **don't merge Plan 2 until the DNS records are in place** (or stage with a feature flag — but flag work is out of scope for Plan 2).
3. **Inline SVG in emails.** Some legacy email clients (older Outlook, Lotus Notes) don't render inline SVG. Affected users see broken images in the email header. Acceptable trade — modern clients (Gmail, Apple Mail, Outlook 2016+) render fine, and avoiding a hosted-image fetch protects sender reputation.
4. **OG image rasterization dependency.** Requires `rsvg-convert` (librsvg) installed locally for one-shot PNG generation. Plan 2 includes the install instruction; if developers skip it, the SVG is the canonical source and the PNG can be regenerated at any time.
5. **Old asset files persist.** The old `logo_*.svg`, `og-share.*`, and favicon files are NOT deleted in Plan 2. Some risk that browsers cache them; cleanup pass after Plan 5 will delete them.

---

## Resolved decisions (from brainstorming)

1. **Logo mark:** pin + drop hybrid (map pin shape with water drop nested inside).
2. **Wordmark:** single-line "Driveway Detail Co", Inter semibold (not the old two-tier "DRIVEWAY / DETAIL CO").
3. **OG image style:** clean type + mark on white background; no photo/illustration (none available).
4. **Email refactor approach:** total rewrite using a shared Swoosh layout module (not inline restyle, not extracted helpers).
5. **Email sender:** update to `noreply@drivewaydetailcosa.com` plus DNS deployment checklist.
6. **Naming:** all new files use `_v2` suffix; old files kept one release for safety.

---

## Effort estimate

| Block | Estimate |
|---|---|
| Logo SVGs (icon + 2 wordmarks) | 1 day (includes design refinement pass) |
| OG image SVG + PNG | 0.5 day |
| Favicon regeneration (6 files) | 0.5 day |
| `Email.Layout` module + tests | 0.5 day |
| Refactor of 11 email functions + tests | 1 day |
| `root.html.heex` updates + sender update + checklist additions | 0.5 day |
| Bug fixing + visual verification | 0.5 day |
| **Total** | **~4 days** of focused work |
