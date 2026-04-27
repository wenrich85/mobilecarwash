# Phase-1, Plan 2 — Brand Assets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce the new visual brand assets (pin+drop logo SVGs, OG share image, favicon set), refactor the email system to use a shared Swoosh layout module, fix the email sender domain, and append deployment-checklist items so DNS and Stripe Dashboard work isn't forgotten before launch.

**Architecture:** Three concerns kept independent — (1) static SVG/PNG assets in `priv/static/images/`, (2) a new `MobileCarWash.Notifications.Email.Layout` module that all 11 transactional emails compose with, (3) two-line `root.html.heex` updates plus a deployment-checklist append. New files are `_v2` suffixed so the old assets stay one release for safety. TDD per layout helper; smoke tests per refactored email function.

**Tech Stack:** Phoenix 1.8, Swoosh, Tailwind v4 + daisyUI, librsvg (`rsvg-convert`) for SVG→PNG rasterization, ImageMagick (`convert`) for `.ico` multi-res packaging, ExUnit.

**Spec reference:** [docs/superpowers/specs/2026-04-26-plan2-brand-assets-design.md](docs/superpowers/specs/2026-04-26-plan2-brand-assets-design.md)

**File map for this plan:**

- New: `priv/static/images/logo_icon_v2.svg`, `logo_light_v2.svg`, `logo_dark_v2.svg`
- New: `priv/static/images/og-share-v2.svg`, `og-share-v2.png`
- New: `priv/static/images/favicon-v2.ico`, `favicon-v2-16.png`, `favicon-v2-32.png`, `apple-touch-icon-v2.png`, `android-chrome-v2-192.png`, `android-chrome-v2-512.png`
- New: `lib/mobile_car_wash/notifications/email/layout.ex`
- New: `test/mobile_car_wash/notifications/email/layout_test.exs`
- Modify: `lib/mobile_car_wash/notifications/email.ex` (sender constant + all 11 functions refactored)
- Modify: `lib/mobile_car_wash_web/components/layouts/root.html.heex` (favicon/icon links + theme-color)
- Modify or new: `test/mobile_car_wash/notifications/email_test.exs` (per-function smoke tests)
- Modify: deployment checklist file (location discovered in Task 17)

**Out of scope (deferred):**

- Photo/illustration assets
- `site.webmanifest` for PWA installability
- Push-notification icons (Plan 5)
- Real unsubscribe-link wiring (footer link is a placeholder)
- Deletion of existing `logo_*.svg` / `og-share.png` / favicon files
- Email subject-line copy improvements (style only)

---

## Task 0: Pre-flight verification

**Files:** none modified — read-only.

- [ ] **Step 1: Verify clean working tree on `main`**

Run: `git status && git branch --show-current`
Expected: branch `main`, "nothing to commit, working tree clean".

If on a different branch or dirty, stop and resolve.

- [ ] **Step 2: Verify the Plan 1 baseline is green**

Run: `mix test 2>&1 | tail -3`
Expected: `992 tests, 0 failures` (or more if other branches landed since Plan 1).

If failures, stop and investigate before adding Plan 2 work.

- [ ] **Step 3: Verify required external binaries are installed**

Run: `which rsvg-convert && which magick`
Expected: both print a path (e.g. `/opt/homebrew/bin/rsvg-convert`, `/opt/homebrew/bin/convert`).

If either is missing, install:
- Mac: `brew install librsvg imagemagick`
- Linux: `apt-get install librsvg2-bin imagemagick` (or distro equivalent)

- [ ] **Step 4: Note baseline test count**

Record the exact test count from Step 2 in your scratch notes — needed to confirm no regressions at the final checkpoint.

---

## Task 1: Create logo_icon_v2.svg

**Files:**
- Create: `priv/static/images/logo_icon_v2.svg`

- [ ] **Step 1: Write the file**

Create `priv/static/images/logo_icon_v2.svg` with this exact content:

```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 40" fill="none">
  <!-- Map pin body: rounded teardrop -->
  <path d="M16 3 C9 3 4 8 4 15 C4 22 16 35 16 35 C16 35 28 22 28 15 C28 8 23 3 16 3Z" fill="#1e293b"/>
  <!-- Water drop nested in the bulb -->
  <path d="M16 8 C16 8 12 13 12 16 C12 18 13.7 20 16 20 C18.3 20 20 18 20 16 C20 13 16 8 16 8Z" fill="#06b6d4"/>
</svg>
```

- [ ] **Step 2: Verify the file renders**

Run: `rsvg-convert -w 256 -h 320 -f png priv/static/images/logo_icon_v2.svg -o /tmp/icon_check.png && file /tmp/icon_check.png`
Expected: `PNG image data, 256 x 320, 8-bit/color RGBA, non-interlaced`.

Open `/tmp/icon_check.png` in Preview / image viewer. Should show: rounded slate-grey map pin with a small cyan water drop inside its bulb. No text, no extra ornaments.

If the shape looks wrong, the path data is off — re-check the SVG file matches Step 1 exactly.

- [ ] **Step 3: Commit**

```bash
git add priv/static/images/logo_icon_v2.svg
git commit -m "brand: add v2 icon SVG (pin + drop)"
```

---

## Task 2: Create logo_light_v2.svg

**Files:**
- Create: `priv/static/images/logo_light_v2.svg`

- [ ] **Step 1: Write the file**

Create `priv/static/images/logo_light_v2.svg` with this exact content:

```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 240 40" fill="none">
  <!-- Pin + drop, scaled to fit the 40-tall canvas -->
  <g transform="translate(0, 0) scale(1)">
    <path d="M16 3 C9 3 4 8 4 15 C4 22 16 35 16 35 C16 35 28 22 28 15 C28 8 23 3 16 3Z" fill="#1e293b"/>
    <path d="M16 8 C16 8 12 13 12 16 C12 18 13.7 20 16 20 C18.3 20 20 18 20 16 C20 13 16 8 16 8Z" fill="#06b6d4"/>
  </g>

  <!-- Wordmark: "Driveway Detail Co", Inter semibold, 18px, slate-900 -->
  <text x="44" y="25"
        font-family="Inter, system-ui, -apple-system, sans-serif"
        font-size="18"
        font-weight="600"
        letter-spacing="-0.4"
        fill="#0f172a">Driveway Detail Co</text>
</svg>
```

- [ ] **Step 2: Verify renders correctly**

Run: `rsvg-convert -w 480 -h 80 -f png priv/static/images/logo_light_v2.svg -o /tmp/light_check.png`
Open `/tmp/light_check.png`. Should show: slate pin with cyan drop on the left, then "Driveway Detail Co" in dark slate text to its right, single line. The text should be readable and not cropped.

- [ ] **Step 3: Commit**

```bash
git add priv/static/images/logo_light_v2.svg
git commit -m "brand: add v2 light-theme wordmark"
```

---

## Task 3: Create logo_dark_v2.svg

**Files:**
- Create: `priv/static/images/logo_dark_v2.svg`

- [ ] **Step 1: Write the file**

Create `priv/static/images/logo_dark_v2.svg`:

```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 240 40" fill="none">
  <!-- Inverted: cyan pin, slate-900 drop (cut-out effect) -->
  <g transform="translate(0, 0) scale(1)">
    <path d="M16 3 C9 3 4 8 4 15 C4 22 16 35 16 35 C16 35 28 22 28 15 C28 8 23 3 16 3Z" fill="#06b6d4"/>
    <path d="M16 8 C16 8 12 13 12 16 C12 18 13.7 20 16 20 C18.3 20 20 18 20 16 C20 13 16 8 16 8Z" fill="#0f172a"/>
  </g>

  <!-- Wordmark: light text for dark backgrounds -->
  <text x="44" y="25"
        font-family="Inter, system-ui, -apple-system, sans-serif"
        font-size="18"
        font-weight="600"
        letter-spacing="-0.4"
        fill="#f8fafc">Driveway Detail Co</text>
</svg>
```

- [ ] **Step 2: Verify renders correctly**

Render against a dark background to check contrast:
```bash
rsvg-convert -w 480 -h 80 -b '#0f172a' -f png priv/static/images/logo_dark_v2.svg -o /tmp/dark_check.png
```

Open `/tmp/dark_check.png`. Should show: cyan pin with a dark "cut-out" drop, then "Driveway Detail Co" in near-white text on dark slate background. Text and pin should both be clearly readable.

- [ ] **Step 3: Commit**

```bash
git add priv/static/images/logo_dark_v2.svg
git commit -m "brand: add v2 dark-theme wordmark"
```

---

## Task 4: Create og-share-v2.svg + rasterize to PNG

**Files:**
- Create: `priv/static/images/og-share-v2.svg`
- Create: `priv/static/images/og-share-v2.png` (build artifact)

- [ ] **Step 1: Write the SVG source**

Create `priv/static/images/og-share-v2.svg`:

```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1200 630" fill="none">
  <!-- White background -->
  <rect width="1200" height="630" fill="#ffffff"/>

  <!-- Top-left brand strip: pin icon + wordmark -->
  <g transform="translate(80, 80)">
    <!-- Pin icon, 48x60 -->
    <g transform="scale(1.5)">
      <path d="M16 3 C9 3 4 8 4 15 C4 22 16 35 16 35 C16 35 28 22 28 15 C28 8 23 3 16 3Z" fill="#1e293b"/>
      <path d="M16 8 C16 8 12 13 12 16 C12 18 13.7 20 16 20 C18.3 20 20 18 20 16 C20 13 16 8 16 8Z" fill="#06b6d4"/>
    </g>
    <!-- Wordmark, 24px Inter semibold, vertically centered to icon -->
    <text x="60" y="38"
          font-family="Inter, system-ui, sans-serif"
          font-size="24"
          font-weight="600"
          letter-spacing="-0.4"
          fill="#0f172a">Driveway Detail Co</text>
  </g>

  <!-- Hero headline, vertically centered -->
  <text x="80" y="320"
        font-family="Inter, system-ui, sans-serif"
        font-size="64"
        font-weight="700"
        letter-spacing="-1.5"
        fill="#0f172a">Your car, washed where</text>
  <text x="80" y="395"
        font-family="Inter, system-ui, sans-serif"
        font-size="64"
        font-weight="700"
        letter-spacing="-1.5"
        fill="#0f172a">you parked it.</text>

  <!-- Subhead -->
  <text x="80" y="450"
        font-family="Inter, system-ui, sans-serif"
        font-size="22"
        font-weight="400"
        fill="#64748b">Mobile detailing in San Antonio · Veteran-owned</text>

  <!-- Bottom-right cyan accent -->
  <rect x="1040" y="510" width="80" height="80" rx="16" fill="#06b6d4"/>
</svg>
```

- [ ] **Step 2: Rasterize to PNG**

Run:
```bash
rsvg-convert -w 1200 -h 630 -f png priv/static/images/og-share-v2.svg -o priv/static/images/og-share-v2.png
```

Expected: command exits 0; produces a ~30-80KB PNG file.

- [ ] **Step 3: Visually verify the PNG**

Run: `file priv/static/images/og-share-v2.png`
Expected: `PNG image data, 1200 x 630, 8-bit/color RGB, non-interlaced` (or RGBA).

Open the file in Preview / image viewer. Should show: white background, "Driveway Detail Co" branded strip in top-left, large dark "Your car, washed where you parked it." headline left-aligned, slate subtitle below it, cyan accent square in bottom-right. No clipped text, no rendering artifacts.

If text doesn't render (looks like boxes or wrong font), the system likely doesn't have Inter installed system-wide. The system font fallback should kick in — that's acceptable for the rasterized PNG since social platforms cache it; the SVG remains the canonical source.

- [ ] **Step 4: Commit**

```bash
git add priv/static/images/og-share-v2.svg priv/static/images/og-share-v2.png
git commit -m "brand: add v2 OG share image (SVG source + PNG)"
```

---

## Task 5: Generate favicon set

**Files:**
- Create: `priv/static/images/favicon-v2.ico`, `favicon-v2-16.png`, `favicon-v2-32.png`, `apple-touch-icon-v2.png`, `android-chrome-v2-192.png`, `android-chrome-v2-512.png`

- [ ] **Step 1: Generate the PNG sizes from logo_icon_v2.svg**

Run each command (each is one PNG):

```bash
rsvg-convert -w 16  -h 20  -f png priv/static/images/logo_icon_v2.svg -o priv/static/images/favicon-v2-16.png
rsvg-convert -w 32  -h 40  -f png priv/static/images/logo_icon_v2.svg -o priv/static/images/favicon-v2-32.png
rsvg-convert -w 180 -h 180 -f png -b '#1e293b' priv/static/images/logo_icon_v2.svg -o /tmp/apple-raw.png
rsvg-convert -w 192 -h 192 -f png -b '#1e293b' priv/static/images/logo_icon_v2.svg -o /tmp/android-192-raw.png
rsvg-convert -w 512 -h 512 -f png -b '#1e293b' priv/static/images/logo_icon_v2.svg -o /tmp/android-512-raw.png
```

The `-b '#1e293b'` background flag puts a slate-800 backplate on the apple-touch-icon and android-chrome icons (so they look like a proper app icon, not a tiny pin floating on transparent).

- [ ] **Step 2: Center-crop the apple/android icons to square**

The icon SVG has aspect 32×40. The above commands rasterized to non-square — apple-touch wants 180×180 square. Use ImageMagick to center the icon on a square slate-800 canvas:

```bash
magick -size 180x180 xc:'#1e293b' \
  \( /tmp/apple-raw.png -resize 144x180 \) \
  -gravity center -composite \
  priv/static/images/apple-touch-icon-v2.png

magick -size 192x192 xc:'#1e293b' \
  \( /tmp/android-192-raw.png -resize 154x192 \) \
  -gravity center -composite \
  priv/static/images/android-chrome-v2-192.png

magick -size 512x512 xc:'#1e293b' \
  \( /tmp/android-512-raw.png -resize 410x512 \) \
  -gravity center -composite \
  priv/static/images/android-chrome-v2-512.png
```

(The `144x180`, `154x192`, `410x512` widths preserve the 32:40 = 4:5 aspect ratio of the source within the square canvas, leaving slate-800 padding on left/right.)

- [ ] **Step 3: Build the multi-res .ico**

```bash
magick priv/static/images/favicon-v2-16.png priv/static/images/favicon-v2-32.png \
  priv/static/images/favicon-v2.ico
```

- [ ] **Step 4: Verify all 6 files exist and have non-zero size**

Run:
```bash
ls -la priv/static/images/favicon-v2* priv/static/images/apple-touch-icon-v2.png priv/static/images/android-chrome-v2-*.png
```

Expected: 6 files, all >0 bytes:
- `favicon-v2.ico` (~1-3 KB)
- `favicon-v2-16.png` (~300-800 bytes)
- `favicon-v2-32.png` (~500-1500 bytes)
- `apple-touch-icon-v2.png` (~3-8 KB)
- `android-chrome-v2-192.png` (~3-10 KB)
- `android-chrome-v2-512.png` (~10-30 KB)

Open `apple-touch-icon-v2.png` in Preview. Should show: slate-800 square background, white-ish pin centered, with cyan drop visible inside the pin's bulb. Looks like a proper iOS app icon.

- [ ] **Step 5: Commit**

```bash
git add priv/static/images/favicon-v2.ico priv/static/images/favicon-v2-16.png priv/static/images/favicon-v2-32.png priv/static/images/apple-touch-icon-v2.png priv/static/images/android-chrome-v2-192.png priv/static/images/android-chrome-v2-512.png
git commit -m "brand: add v2 favicon set (ico + 5 PNG sizes)"
```

---

## Task 6: Update root.html.heex (favicon links + theme-color)

**Files:**
- Modify: `lib/mobile_car_wash_web/components/layouts/root.html.heex`

- [ ] **Step 1: Read the current favicon and theme-color tags**

Run: `grep -n 'favicon\|theme-color\|apple-touch' lib/mobile_car_wash_web/components/layouts/root.html.heex`
Note the current tag block (around lines 22-31 in Plan 1's state).

- [ ] **Step 2: Replace the theme-color tag**

Find:
```heex
<meta name="theme-color" content="#1E2A38" />
```

Replace with:
```heex
<meta name="theme-color" content="#1e293b" />
```

- [ ] **Step 3: Replace the favicon link block**

Find the existing favicon links (currently pointing to `~p"/favicon.ico"` and `~p"/images/logo_icon.svg"`):

```heex
    <link rel="icon" type="image/x-icon" href={~p"/favicon.ico"} />
    <link rel="icon" type="image/svg+xml" href={~p"/images/logo_icon.svg"} />
    <link rel="apple-touch-icon" href={~p"/images/logo_icon.svg"} />
```

Replace with:

```heex
    <link rel="icon" type="image/x-icon" href={~p"/images/favicon-v2.ico"} />
    <link rel="icon" type="image/png" sizes="16x16" href={~p"/images/favicon-v2-16.png"} />
    <link rel="icon" type="image/png" sizes="32x32" href={~p"/images/favicon-v2-32.png"} />
    <link rel="apple-touch-icon" sizes="180x180" href={~p"/images/apple-touch-icon-v2.png"} />
    <link rel="icon" type="image/png" sizes="192x192" href={~p"/images/android-chrome-v2-192.png"} />
    <link rel="icon" type="image/png" sizes="512x512" href={~p"/images/android-chrome-v2-512.png"} />
```

- [ ] **Step 4: Verify the file compiles**

Run: `mix compile --warnings-as-errors 2>&1 | tail -5`
Expected: `Generated mobile_car_wash app` with no errors.

- [ ] **Step 5: (Optional but recommended) Boot dev server, verify the favicon shows**

Run: `mix phx.server` (separate terminal)
Open `http://localhost:4000` in a browser. Open DevTools → Network → filter to "img". Reload. Confirm `favicon-v2.ico` and `favicon-v2-32.png` load with HTTP 200. Look at the browser tab — should show the new pin icon.

Stop the server (Ctrl-C) when done.

- [ ] **Step 6: Commit**

```bash
git add lib/mobile_car_wash_web/components/layouts/root.html.heex
git commit -m "brand: wire v2 favicons + theme-color in root layout"
```

---

## Task 7: Create Email.Layout module (skeleton + wrap_html)

**Files:**
- Create: `lib/mobile_car_wash/notifications/email/layout.ex`
- Create: `test/mobile_car_wash/notifications/email/layout_test.exs`

- [ ] **Step 1: Write the failing test**

Create `test/mobile_car_wash/notifications/email/layout_test.exs`:

```elixir
defmodule MobileCarWash.Notifications.Email.LayoutTest do
  use ExUnit.Case, async: true
  alias MobileCarWash.Notifications.Email.Layout

  describe "wrap_html/1" do
    test "produces a doctype html document" do
      html = Layout.wrap_html("<p>Hello</p>")
      assert html =~ "<!doctype html>"
      assert html =~ "<html"
      assert html =~ "</html>"
    end

    test "includes meta charset and viewport" do
      html = Layout.wrap_html("<p>Hi</p>")
      assert html =~ ~s(charset="utf-8")
      assert html =~ ~s(name="viewport")
    end

    test "includes the inline SVG logo in the header" do
      html = Layout.wrap_html("<p>Body</p>")
      assert html =~ "<svg"
      assert html =~ "Driveway Detail Co"
    end

    test "wraps the content_html in the body slot" do
      html = Layout.wrap_html(~s(<p class="signal">UNIQUE_BODY_CONTENT</p>))
      assert html =~ "UNIQUE_BODY_CONTENT"
    end

    test "footer contains the legal name" do
      html = Layout.wrap_html("<p>x</p>")
      assert html =~ "Driveway Detail Co. LLC"
      assert html =~ "San Antonio"
    end
  end
end
```

- [ ] **Step 2: Run the test, verify failure**

Run: `mix test test/mobile_car_wash/notifications/email/layout_test.exs`
Expected: compile error — `MobileCarWash.Notifications.Email.Layout` is undefined.

- [ ] **Step 3: Create the module with `wrap_html/1`**

Create `lib/mobile_car_wash/notifications/email/layout.ex`:

```elixir
defmodule MobileCarWash.Notifications.Email.Layout do
  @moduledoc """
  Shared HTML and text layout helpers for transactional emails.

  All transactional emails use `wrap_html/1` (HTML body) and `wrap_text/1`
  (text body) to get a consistent header (logo) and footer (legal). Inline
  SVG logo avoids dependency on external image fetches that hurt sender
  reputation in some clients.

  Buttons are styled inline (no `<style>` tag — many email clients strip
  them).
  """

  @doc """
  Wraps content HTML in the branded email document layout.

  Returns a complete `<!doctype html>...</html>` string.
  """
  def wrap_html(content_html) when is_binary(content_html) do
    """
    <!doctype html>
    <html lang="en">
    <head>
      <meta charset="utf-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1" />
      <title>Driveway Detail Co</title>
    </head>
    <body style="margin:0;padding:0;background:#f1f5f9;font-family:'Inter',-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f1f5f9;padding:32px 16px;">
        <tr>
          <td align="center">
            <table role="presentation" width="600" cellpadding="0" cellspacing="0" style="max-width:600px;background:#ffffff;border-radius:12px;padding:24px;">
              <tr>
                <td style="padding-bottom:16px;border-bottom:1px solid #e2e8f0;">
                  #{header_logo_svg()}
                </td>
              </tr>
              <tr>
                <td style="padding:24px 0;color:#0f172a;font-size:14px;line-height:1.55;">
                  #{content_html}
                </td>
              </tr>
              <tr>
                <td style="padding-top:16px;border-top:1px solid #e2e8f0;text-align:center;color:#64748b;font-size:12px;">
                  <p style="margin:0 0 8px;">Driveway Detail Co. LLC · San Antonio, TX · Veteran-owned</p>
                  <p style="margin:0;">
                    <a href="https://drivewaydetailcosa.com/privacy" style="color:#06b6d4;text-decoration:none;">Privacy</a> ·
                    <a href="https://drivewaydetailcosa.com/terms" style="color:#06b6d4;text-decoration:none;">Terms</a> ·
                    <a href="https://drivewaydetailcosa.com/unsubscribe" style="color:#06b6d4;text-decoration:none;">Unsubscribe</a>
                  </p>
                </td>
              </tr>
            </table>
          </td>
        </tr>
      </table>
    </body>
    </html>
    """
  end

  defp header_logo_svg do
    # Inline pin+drop + wordmark. Slate fill so it reads on white card bg.
    """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 240 40" width="180" height="30" style="display:block;">
      <path d="M16 3 C9 3 4 8 4 15 C4 22 16 35 16 35 C16 35 28 22 28 15 C28 8 23 3 16 3Z" fill="#1e293b"/>
      <path d="M16 8 C16 8 12 13 12 16 C12 18 13.7 20 16 20 C18.3 20 20 18 20 16 C20 13 16 8 16 8Z" fill="#06b6d4"/>
      <text x="44" y="25" font-family="'Inter',sans-serif" font-size="18" font-weight="600" letter-spacing="-0.4" fill="#0f172a">Driveway Detail Co</text>
    </svg>
    """
  end
end
```

- [ ] **Step 4: Run the test, verify pass**

Run: `mix test test/mobile_car_wash/notifications/email/layout_test.exs`
Expected: 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/mobile_car_wash/notifications/email/layout.ex test/mobile_car_wash/notifications/email/layout_test.exs
git commit -m "email: add Layout module with wrap_html/1"
```

---

## Task 8: Add wrap_text/1 helper

**Files:**
- Modify: `lib/mobile_car_wash/notifications/email/layout.ex`
- Modify: `test/mobile_car_wash/notifications/email/layout_test.exs`

- [ ] **Step 1: Add failing test**

Append to the test file before the module's closing `end`:

```elixir
  describe "wrap_text/1" do
    test "produces header with brand name and separator" do
      text = Layout.wrap_text("Hello.")
      assert text =~ "Driveway Detail Co"
      assert text =~ "================="
    end

    test "includes the body content" do
      text = Layout.wrap_text("UNIQUE_TEXT_BODY")
      assert text =~ "UNIQUE_TEXT_BODY"
    end

    test "footer mentions the legal name" do
      text = Layout.wrap_text("body")
      assert text =~ "Driveway Detail Co. LLC"
      assert text =~ "San Antonio"
    end
  end
```

- [ ] **Step 2: Run, verify failure**

Run: `mix test test/mobile_car_wash/notifications/email/layout_test.exs --only describe:wrap_text`
Expected: undefined function `wrap_text/1`.

- [ ] **Step 3: Add `wrap_text/1` to the Layout module**

Append before the final `end` of `MobileCarWash.Notifications.Email.Layout`:

```elixir
  @doc """
  Wraps content text with a plain-text header and footer.
  """
  def wrap_text(content_text) when is_binary(content_text) do
    """
    Driveway Detail Co
    =================

    #{content_text}

    ---
    Driveway Detail Co. LLC · San Antonio, TX · Veteran-owned
    Privacy: https://drivewaydetailcosa.com/privacy
    Terms:   https://drivewaydetailcosa.com/terms
    Unsubscribe: https://drivewaydetailcosa.com/unsubscribe
    """
  end
```

- [ ] **Step 4: Run tests**

Run: `mix test test/mobile_car_wash/notifications/email/layout_test.exs`
Expected: 8 tests pass (5 wrap_html + 3 wrap_text).

- [ ] **Step 5: Commit**

```bash
git add lib/mobile_car_wash/notifications/email/layout.ex test/mobile_car_wash/notifications/email/layout_test.exs
git commit -m "email: add Layout.wrap_text/1"
```

---

## Task 9: Add button/3 helper

**Files:**
- Modify: `lib/mobile_car_wash/notifications/email/layout.ex`
- Modify: `test/mobile_car_wash/notifications/email/layout_test.exs`

- [ ] **Step 1: Add failing test**

Append before the module's closing `end`:

```elixir
  describe "button/3" do
    test "defaults to :primary variant with cyan background" do
      html = Layout.button("Click me", "https://example.com/x")
      assert html =~ ~s(href="https://example.com/x")
      assert html =~ "Click me"
      assert html =~ "background:#06b6d4"
      assert html =~ "color:#ffffff"
    end

    test ":secondary variant uses slate background" do
      html = Layout.button("Cancel", "https://example.com/x", :secondary)
      assert html =~ "background:#f1f5f9"
      assert html =~ "color:#0f172a"
    end

    test "wraps as inline-styled anchor (no <style> tags)" do
      html = Layout.button("X", "https://example.com")
      assert html =~ "<a "
      refute html =~ "<style"
    end
  end
```

- [ ] **Step 2: Run, verify failure**

Run: `mix test test/mobile_car_wash/notifications/email/layout_test.exs --only describe:button`
Expected: undefined function `button/2` or `button/3`.

- [ ] **Step 3: Add `button/3` to the Layout module**

Append before the final `end`:

```elixir
  @doc """
  Renders a branded CTA button as inline-styled HTML.

  Variants:
    * `:primary` (default) — cyan background, white text
    * `:secondary` — slate background, dark text
  """
  def button(label, url, variant \\ :primary)
      when is_binary(label) and is_binary(url) and variant in [:primary, :secondary] do
    {bg, fg} =
      case variant do
        :primary -> {"#06b6d4", "#ffffff"}
        :secondary -> {"#f1f5f9", "#0f172a"}
      end

    """
    <a href="#{url}" style="display:inline-block;background:#{bg};color:#{fg};padding:12px 24px;border-radius:8px;text-decoration:none;font-weight:600;font-family:'Inter',sans-serif;font-size:14px;">#{label}</a>
    """
  end
```

- [ ] **Step 4: Run tests**

Run: `mix test test/mobile_car_wash/notifications/email/layout_test.exs`
Expected: 11 tests pass (5 wrap_html + 3 wrap_text + 3 button).

- [ ] **Step 5: Commit**

```bash
git add lib/mobile_car_wash/notifications/email/layout.ex test/mobile_car_wash/notifications/email/layout_test.exs
git commit -m "email: add Layout.button/3 (primary + secondary variants)"
```

---

## Task 10: Add link/2 helper

**Files:**
- Modify: `lib/mobile_car_wash/notifications/email/layout.ex`
- Modify: `test/mobile_car_wash/notifications/email/layout_test.exs`

- [ ] **Step 1: Add failing test**

Append before the module's closing `end`:

```elixir
  describe "link/2" do
    test "produces an inline-styled anchor in cyan" do
      html = Layout.link("the docs", "https://example.com/docs")
      assert html =~ ~s(href="https://example.com/docs")
      assert html =~ "the docs"
      assert html =~ "color:#06b6d4"
      assert html =~ "<a "
    end

    test "no <style> tags or class attributes" do
      html = Layout.link("x", "https://x.example")
      refute html =~ "<style"
      refute html =~ "class="
    end
  end
```

- [ ] **Step 2: Run, verify failure**

Run: `mix test test/mobile_car_wash/notifications/email/layout_test.exs --only describe:link`
Expected: undefined function `link/2`.

- [ ] **Step 3: Add `link/2` to the Layout module**

Append before the final `end`:

```elixir
  @doc """
  Renders an inline cyan-styled anchor for body-text links.
  """
  def link(label, url) when is_binary(label) and is_binary(url) do
    ~s(<a href="#{url}" style="color:#06b6d4;text-decoration:none;">#{label}</a>)
  end
```

- [ ] **Step 4: Run tests**

Run: `mix test test/mobile_car_wash/notifications/email/layout_test.exs`
Expected: 13 tests pass (5 + 3 + 3 + 2).

- [ ] **Step 5: Commit**

```bash
git add lib/mobile_car_wash/notifications/email/layout.ex test/mobile_car_wash/notifications/email/layout_test.exs
git commit -m "email: add Layout.link/2 (inline cyan anchor)"
```

---

## Task 11: Update sender constant in email.ex

**Files:**
- Modify: `lib/mobile_car_wash/notifications/email.ex`

- [ ] **Step 1: Find the @from constant**

Run: `grep -n '@from' lib/mobile_car_wash/notifications/email.ex`
Expected: a single line like `@from {"Mobile Car Wash", "noreply@mobilecarwash.com"}`.

- [ ] **Step 2: Replace it**

Find:
```elixir
  @from {"Mobile Car Wash", "noreply@mobilecarwash.com"}
```

Replace with:
```elixir
  @from {"Driveway Detail Co", "noreply@drivewaydetailcosa.com"}
```

- [ ] **Step 3: Verify compile**

Run: `mix compile --warnings-as-errors 2>&1 | tail -3`
Expected: `Generated mobile_car_wash app` with no errors.

- [ ] **Step 4: Commit**

```bash
git add lib/mobile_car_wash/notifications/email.ex
git commit -m "email: update sender to Driveway Detail Co <noreply@drivewaydetailcosa.com>"
```

---

## Task 12: Refactor 4 transactional emails to use Layout

**Files:**
- Modify: `lib/mobile_car_wash/notifications/email.ex`

This task refactors the first batch of 4 emails: `verify_email`, `booking_confirmation`, `payment_receipt`, `booking_cancelled`. Each one keeps its existing arity, recipient logic, subject text, and link content. Only the HTML and text bodies change.

- [ ] **Step 1: Add the alias near the top of the module**

In `lib/mobile_car_wash/notifications/email.ex`, find the existing `import Swoosh.Email` line. Immediately after it, add:

```elixir
  alias MobileCarWash.Notifications.Email.Layout
```

- [ ] **Step 2: Refactor `verify_email/2`**

Replace the entire `def verify_email(customer, verification_link) do ... end` block with:

```elixir
  @doc """
  Email verification link — sent after signup. 24-hour lifetime; link
  carries a one-shot JWT with the customer's subject + email baked in.
  """
  def verify_email(customer, verification_link) do
    inner_html = """
    <h2 style="margin:0 0 12px;font-size:20px;color:#0f172a;">Welcome, #{customer.name}!</h2>
    <p>Thanks for signing up with Driveway Detail Co. Please verify your
    email so we can send you booking confirmations, reminders, and receipts.</p>
    <p style="margin:24px 0;">#{Layout.button("Verify my email", verification_link)}</p>
    <p style="color:#64748b;font-size:12px;">The link expires in 24 hours.
    If you didn't create this account, you can safely ignore this email.</p>
    """

    inner_text = """
    Welcome, #{customer.name}!

    Thanks for signing up with Driveway Detail Co. Please verify your email
    so we can send you booking confirmations, reminders, and receipts.

    Verify: #{verification_link}

    The link expires in 24 hours. If you didn't create this account, you
    can safely ignore this email.
    """

    new()
    |> to({customer.name, to_string(customer.email)})
    |> from(@from)
    |> subject("Verify your email for Driveway Detail Co")
    |> html_body(Layout.wrap_html(inner_html))
    |> text_body(Layout.wrap_text(inner_text))
  end
```

- [ ] **Step 3: Refactor `booking_confirmation/4`**

Find the existing `def booking_confirmation(appointment, service_type, customer, address) do ... end` block. Replace with:

```elixir
  @doc """
  Booking confirmation email — sent after successful payment.
  """
  def booking_confirmation(appointment, service_type, customer, address) do
    inner_html = """
    <h2 style="margin:0 0 12px;font-size:20px;color:#0f172a;">Your booking is confirmed!</h2>
    <p>Hi #{customer.name},</p>
    <p>We've received your booking for <strong>#{service_type.name}</strong>.</p>
    <table cellpadding="0" cellspacing="0" style="margin:16px 0;">
      <tr><td style="padding:4px 16px 4px 0;color:#64748b;font-size:13px;">Service</td><td style="padding:4px 0;font-weight:600;">#{service_type.name}</td></tr>
      <tr><td style="padding:4px 16px 4px 0;color:#64748b;font-size:13px;">When</td><td style="padding:4px 0;font-weight:600;">#{appointment.scheduled_at}</td></tr>
      <tr><td style="padding:4px 16px 4px 0;color:#64748b;font-size:13px;">Where</td><td style="padding:4px 0;font-weight:600;">#{address}</td></tr>
    </table>
    <p style="color:#64748b;font-size:13px;">We'll text you the day before with our 15-minute arrival window.</p>
    """

    inner_text = """
    Your booking is confirmed!

    Hi #{customer.name},

    We've received your booking for #{service_type.name}.

    Service: #{service_type.name}
    When: #{appointment.scheduled_at}
    Where: #{address}

    We'll text you the day before with our 15-minute arrival window.
    """

    new()
    |> to({customer.name, to_string(customer.email)})
    |> from(@from)
    |> subject("Booking Confirmed - #{service_type.name}")
    |> html_body(Layout.wrap_html(inner_html))
    |> text_body(Layout.wrap_text(inner_text))
  end
```

- [ ] **Step 4: Refactor `payment_receipt/3`**

Find `def payment_receipt(customer, payment, service_name) do ... end`. Replace with:

```elixir
  @doc """
  Payment receipt — sent after a successful charge.
  """
  def payment_receipt(customer, payment, service_name) do
    amount_dollars = :erlang.float_to_binary(payment.amount_cents / 100, decimals: 2)

    inner_html = """
    <h2 style="margin:0 0 12px;font-size:20px;color:#0f172a;">Payment received</h2>
    <p>Hi #{customer.name},</p>
    <p>Thanks for your payment. Here are the details:</p>
    <table cellpadding="0" cellspacing="0" style="margin:16px 0;">
      <tr><td style="padding:4px 16px 4px 0;color:#64748b;font-size:13px;">Service</td><td style="padding:4px 0;font-weight:600;">#{service_name}</td></tr>
      <tr><td style="padding:4px 16px 4px 0;color:#64748b;font-size:13px;">Amount</td><td style="padding:4px 0;font-weight:600;">$#{amount_dollars}</td></tr>
      <tr><td style="padding:4px 16px 4px 0;color:#64748b;font-size:13px;">Receipt #</td><td style="padding:4px 0;font-weight:600;font-family:monospace;">#{payment.id}</td></tr>
    </table>
    """

    inner_text = """
    Payment received

    Hi #{customer.name},

    Service: #{service_name}
    Amount: $#{amount_dollars}
    Receipt: #{payment.id}
    """

    new()
    |> to({customer.name, to_string(customer.email)})
    |> from(@from)
    |> subject("Payment Receipt — Driveway Detail Co")
    |> html_body(Layout.wrap_html(inner_html))
    |> text_body(Layout.wrap_text(inner_text))
  end
```

- [ ] **Step 5: Refactor `booking_cancelled/3`**

Find `def booking_cancelled(customer, appointment, service_name) do ... end`. Replace with:

```elixir
  @doc """
  Cancellation confirmation email.
  """
  def booking_cancelled(customer, appointment, service_name) do
    inner_html = """
    <h2 style="margin:0 0 12px;font-size:20px;color:#0f172a;">Your booking was cancelled</h2>
    <p>Hi #{customer.name},</p>
    <p>Your booking for <strong>#{service_name}</strong> on #{appointment.scheduled_at} has been cancelled.</p>
    <p>If this was a mistake or you'd like to rebook, you can do so anytime.</p>
    <p style="margin:24px 0;">#{Layout.button("Book again", "https://drivewaydetailcosa.com/book")}</p>
    """

    inner_text = """
    Your booking was cancelled

    Hi #{customer.name},

    Your booking for #{service_name} on #{appointment.scheduled_at} has been cancelled.

    Book again: https://drivewaydetailcosa.com/book
    """

    new()
    |> to({customer.name, to_string(customer.email)})
    |> from(@from)
    |> subject("Booking Cancelled — #{service_name}")
    |> html_body(Layout.wrap_html(inner_html))
    |> text_body(Layout.wrap_text(inner_text))
  end
```

- [ ] **Step 6: Verify compile**

Run: `mix compile --warnings-as-errors 2>&1 | tail -3`
Expected: `Generated mobile_car_wash app` with no errors. If you see "function Layout.wrap_html/1 is undefined", confirm the alias from Step 1 was added.

- [ ] **Step 7: Commit**

```bash
git add lib/mobile_car_wash/notifications/email.ex
git commit -m "email: refactor 4 transactional emails to use Layout module

verify_email, booking_confirmation, payment_receipt, booking_cancelled
now compose inner content + Layout.wrap_html/1/wrap_text/1. Subject,
recipient, link contents preserved."
```

---

## Task 13: Refactor 4 status-update emails to use Layout

**Files:**
- Modify: `lib/mobile_car_wash/notifications/email.ex`

Refactors `appointment_reminder`, `wash_completed`, `tech_on_the_way`, `tech_arrived`.

- [ ] **Step 1: Refactor `appointment_reminder/4`**

Find `def appointment_reminder(appointment, service_type, customer, address) do ... end`. Replace with:

```elixir
  @doc """
  Appointment reminder — sent ~24 hours before the scheduled time.
  """
  def appointment_reminder(appointment, service_type, customer, address) do
    inner_html = """
    <h2 style="margin:0 0 12px;font-size:20px;color:#0f172a;">Reminder: your wash is tomorrow</h2>
    <p>Hi #{customer.name},</p>
    <p>Just a heads-up — your <strong>#{service_type.name}</strong> is scheduled for #{appointment.scheduled_at}.</p>
    <p>We'll be at #{address}. Expect a text from us with our 15-minute arrival window.</p>
    """

    inner_text = """
    Reminder: your wash is tomorrow

    Hi #{customer.name},

    Your #{service_type.name} is scheduled for #{appointment.scheduled_at}.
    Address: #{address}

    Expect a text from us with our 15-minute arrival window.
    """

    new()
    |> to({customer.name, to_string(customer.email)})
    |> from(@from)
    |> subject("Reminder: #{service_type.name} tomorrow")
    |> html_body(Layout.wrap_html(inner_html))
    |> text_body(Layout.wrap_text(inner_text))
  end
```

- [ ] **Step 2: Refactor `wash_completed/3`**

Find `def wash_completed(customer, appointment, service_name) do ... end`. Replace with:

```elixir
  @doc """
  Wash-completed email — sent when the technician marks the job done.
  """
  def wash_completed(customer, appointment, service_name) do
    inner_html = """
    <h2 style="margin:0 0 12px;font-size:20px;color:#0f172a;">Your wash is complete</h2>
    <p>Hi #{customer.name},</p>
    <p>Your <strong>#{service_name}</strong> wrapped up at #{appointment.completed_at || "moments ago"}.</p>
    <p>If you have a minute, we'd love your feedback — it helps us keep improving.</p>
    <p style="margin:24px 0;">#{Layout.button("Leave a review", "https://drivewaydetailcosa.com/review")}</p>
    """

    inner_text = """
    Your wash is complete

    Hi #{customer.name},

    Your #{service_name} wrapped up. Thanks for choosing Driveway Detail Co.

    Leave a review: https://drivewaydetailcosa.com/review
    """

    new()
    |> to({customer.name, to_string(customer.email)})
    |> from(@from)
    |> subject("Your #{service_name} is complete")
    |> html_body(Layout.wrap_html(inner_html))
    |> text_body(Layout.wrap_text(inner_text))
  end
```

- [ ] **Step 3: Refactor `tech_on_the_way/4`**

Find `def tech_on_the_way(customer, appointment, service_name, technician_name) do ... end`. Replace with:

```elixir
  @doc """
  "Tech on the way" — sent when the technician departs for the customer.
  """
  def tech_on_the_way(customer, appointment, service_name, technician_name) do
    inner_html = """
    <h2 style="margin:0 0 12px;font-size:20px;color:#0f172a;">#{technician_name} is on the way</h2>
    <p>Hi #{customer.name},</p>
    <p>#{technician_name} just left and is heading your way for your <strong>#{service_name}</strong>.</p>
    <p style="color:#64748b;font-size:13px;">Estimated arrival: #{appointment.eta || "shortly"}.</p>
    """

    inner_text = """
    #{technician_name} is on the way

    Hi #{customer.name},

    #{technician_name} just left and is heading your way for your #{service_name}.
    Estimated arrival: #{appointment.eta || "shortly"}.
    """

    new()
    |> to({customer.name, to_string(customer.email)})
    |> from(@from)
    |> subject("#{technician_name} is on the way")
    |> html_body(Layout.wrap_html(inner_html))
    |> text_body(Layout.wrap_text(inner_text))
  end
```

- [ ] **Step 4: Refactor `tech_arrived/4`**

Find `def tech_arrived(customer, _appointment, service_name, technician_name) do ... end`. Replace with:

```elixir
  @doc """
  "Tech arrived" — sent when the technician arrives at the location.
  """
  def tech_arrived(customer, _appointment, service_name, technician_name) do
    inner_html = """
    <h2 style="margin:0 0 12px;font-size:20px;color:#0f172a;">#{technician_name} has arrived</h2>
    <p>Hi #{customer.name},</p>
    <p>#{technician_name} just pulled up to start your <strong>#{service_name}</strong>.</p>
    <p style="color:#64748b;font-size:13px;">No need to do anything — we'll handle the rest.</p>
    """

    inner_text = """
    #{technician_name} has arrived

    Hi #{customer.name},

    #{technician_name} just pulled up to start your #{service_name}.
    No need to do anything — we'll handle the rest.
    """

    new()
    |> to({customer.name, to_string(customer.email)})
    |> from(@from)
    |> subject("#{technician_name} has arrived")
    |> html_body(Layout.wrap_html(inner_html))
    |> text_body(Layout.wrap_text(inner_text))
  end
```

- [ ] **Step 5: Verify compile**

Run: `mix compile --warnings-as-errors 2>&1 | tail -3`
Expected: clean.

- [ ] **Step 6: Commit**

```bash
git add lib/mobile_car_wash/notifications/email.ex
git commit -m "email: refactor 4 status-update emails to use Layout module

appointment_reminder, wash_completed, tech_on_the_way, tech_arrived
now compose with Layout helpers."
```

---

## Task 14: Refactor 3 subscription/admin emails to use Layout

**Files:**
- Modify: `lib/mobile_car_wash/notifications/email.ex`

Refactors `subscription_created`, `subscription_cancelled`, `deadline_reminder`.

- [ ] **Step 1: Refactor `subscription_created/2`**

Find `def subscription_created(customer, plan) do ... end`. Replace with:

```elixir
  @doc """
  Subscription welcome email — sent after a customer signs up for a plan.
  """
  def subscription_created(customer, plan) do
    inner_html = """
    <h2 style="margin:0 0 12px;font-size:20px;color:#0f172a;">Welcome to #{plan.name}</h2>
    <p>Hi #{customer.name},</p>
    <p>Your subscription to <strong>#{plan.name}</strong> is active. You'll get
    your first wash this period — we'll reach out soon to schedule.</p>
    <p style="color:#64748b;font-size:13px;">Manage your subscription anytime in your account.</p>
    <p style="margin:24px 0;">#{Layout.button("Manage subscription", "https://drivewaydetailcosa.com/subscriptions/manage")}</p>
    """

    inner_text = """
    Welcome to #{plan.name}

    Hi #{customer.name},

    Your subscription to #{plan.name} is active. You'll get your first wash
    this period — we'll reach out soon to schedule.

    Manage: https://drivewaydetailcosa.com/subscriptions/manage
    """

    new()
    |> to({customer.name, to_string(customer.email)})
    |> from(@from)
    |> subject("Welcome to #{plan.name}")
    |> html_body(Layout.wrap_html(inner_html))
    |> text_body(Layout.wrap_text(inner_text))
  end
```

- [ ] **Step 2: Refactor `subscription_cancelled/2`**

Find `def subscription_cancelled(customer, plan) do ... end`. Replace with:

```elixir
  @doc """
  Subscription cancellation confirmation.
  """
  def subscription_cancelled(customer, plan) do
    inner_html = """
    <h2 style="margin:0 0 12px;font-size:20px;color:#0f172a;">Subscription cancelled</h2>
    <p>Hi #{customer.name},</p>
    <p>Your <strong>#{plan.name}</strong> subscription has been cancelled. You won't
    be charged again.</p>
    <p>If you change your mind, you can resubscribe anytime.</p>
    <p style="margin:24px 0;">#{Layout.button("Resubscribe", "https://drivewaydetailcosa.com/subscriptions", :secondary)}</p>
    """

    inner_text = """
    Subscription cancelled

    Hi #{customer.name},

    Your #{plan.name} subscription has been cancelled. You won't be charged again.

    Resubscribe anytime: https://drivewaydetailcosa.com/subscriptions
    """

    new()
    |> to({customer.name, to_string(customer.email)})
    |> from(@from)
    |> subject("Subscription Cancelled — #{plan.name}")
    |> html_body(Layout.wrap_html(inner_html))
    |> text_body(Layout.wrap_text(inner_text))
  end
```

- [ ] **Step 3: Refactor `deadline_reminder/4` (admin email)**

Find `def deadline_reminder(task, category, days_before, admin_email) do ... end`. Replace with:

```elixir
  @doc """
  Internal admin reminder for an upcoming compliance deadline.
  """
  def deadline_reminder(task, category, days_before, admin_email) do
    days_label =
      cond do
        days_before == 0 -> "TODAY"
        days_before == 1 -> "in 1 day"
        true -> "in #{days_before} days"
      end

    inner_html = """
    <h2 style="margin:0 0 12px;font-size:20px;color:#0f172a;">Compliance deadline #{days_label}</h2>
    <p><strong>#{task}</strong> (#{category}) is due #{days_label}.</p>
    <p style="color:#64748b;font-size:13px;">This is an internal admin reminder.</p>
    """

    inner_text = """
    Compliance deadline #{days_label}

    #{task} (#{category}) is due #{days_label}.

    This is an internal admin reminder.
    """

    new()
    |> to(admin_email)
    |> from(@from)
    |> subject("[Driveway Admin] #{task} due #{days_label}")
    |> html_body(Layout.wrap_html(inner_html))
    |> text_body(Layout.wrap_text(inner_text))
  end
```

- [ ] **Step 4: Verify compile**

Run: `mix compile --warnings-as-errors 2>&1 | tail -3`
Expected: clean.

- [ ] **Step 5: Verify all 11 emails are now refactored**

Run: `grep -c "Layout.wrap_html" lib/mobile_car_wash/notifications/email.ex`
Expected: 11 (one per refactored function).

If less, you missed one — re-check Tasks 12, 13, 14.

- [ ] **Step 6: Commit**

```bash
git add lib/mobile_car_wash/notifications/email.ex
git commit -m "email: refactor 3 subscription/admin emails to use Layout module

subscription_created, subscription_cancelled, deadline_reminder
complete the 11-function refactor."
```

---

## Task 15: Add per-email smoke tests

**Files:**
- Create or Modify: `test/mobile_car_wash/notifications/email_test.exs`

- [ ] **Step 1: Check whether the test file exists**

Run: `test -f test/mobile_car_wash/notifications/email_test.exs && echo EXISTS || echo MISSING`

If it exists, you'll APPEND new test functions. If missing, you'll create the file from scratch.

- [ ] **Step 2: Write the failing tests**

If the file is MISSING, create `test/mobile_car_wash/notifications/email_test.exs` with this complete content:

```elixir
defmodule MobileCarWash.Notifications.EmailTest do
  use ExUnit.Case, async: true
  alias MobileCarWash.Notifications.Email

  defp customer, do: %{name: "Maria", email: "maria@example.com"}
  defp plan, do: %{name: "Monthly Premium"}
  defp service_type, do: %{name: "Premium Wash"}
  defp appointment, do: %{scheduled_at: "Apr 28, 2026 at 10:00 AM", completed_at: nil, eta: "9:50 AM"}
  defp payment, do: %{id: "py_test123", amount_cents: 9999}
  defp address, do: "123 Main St, San Antonio, TX"

  defp assert_branded_email(email, expected_subject_substr) do
    assert email.subject =~ expected_subject_substr
    assert email.from == {"Driveway Detail Co", "noreply@drivewaydetailcosa.com"}
    assert email.html_body =~ "Driveway Detail Co. LLC"
    assert email.text_body =~ "Driveway Detail Co. LLC"
  end

  test "verify_email/2 wraps with Layout and sets correct subject" do
    email = Email.verify_email(customer(), "https://example.com/verify/abc")
    assert_branded_email(email, "Verify your email")
    assert email.html_body =~ "https://example.com/verify/abc"
  end

  test "booking_confirmation/4 wraps with Layout" do
    email = Email.booking_confirmation(appointment(), service_type(), customer(), address())
    assert_branded_email(email, "Booking Confirmed")
    assert email.html_body =~ "Premium Wash"
    assert email.html_body =~ "123 Main St"
  end

  test "appointment_reminder/4 wraps with Layout" do
    email = Email.appointment_reminder(appointment(), service_type(), customer(), address())
    assert_branded_email(email, "Reminder")
  end

  test "deadline_reminder/4 wraps with Layout" do
    email = Email.deadline_reminder("Renew LLC filing", "Legal", 3, "admin@drivewaydetailcosa.com")
    assert email.subject =~ "Renew LLC filing"
    assert email.from == {"Driveway Detail Co", "noreply@drivewaydetailcosa.com"}
    assert email.html_body =~ "Driveway Detail Co. LLC"
  end

  test "payment_receipt/3 wraps with Layout and shows formatted amount" do
    email = Email.payment_receipt(customer(), payment(), "Premium Wash")
    assert_branded_email(email, "Payment Receipt")
    assert email.html_body =~ "$99.99"
    assert email.html_body =~ "py_test123"
  end

  test "wash_completed/3 wraps with Layout" do
    email = Email.wash_completed(customer(), %{appointment() | completed_at: "Apr 28, 2026 at 11:30 AM"}, "Premium Wash")
    assert_branded_email(email, "complete")
  end

  test "tech_on_the_way/4 wraps with Layout" do
    email = Email.tech_on_the_way(customer(), appointment(), "Premium Wash", "Jordan")
    assert_branded_email(email, "Jordan is on the way")
  end

  test "tech_arrived/4 wraps with Layout" do
    email = Email.tech_arrived(customer(), appointment(), "Premium Wash", "Jordan")
    assert_branded_email(email, "Jordan has arrived")
  end

  test "booking_cancelled/3 wraps with Layout" do
    email = Email.booking_cancelled(customer(), appointment(), "Premium Wash")
    assert_branded_email(email, "Booking Cancelled")
  end

  test "subscription_created/2 wraps with Layout" do
    email = Email.subscription_created(customer(), plan())
    assert_branded_email(email, "Welcome to Monthly Premium")
  end

  test "subscription_cancelled/2 wraps with Layout" do
    email = Email.subscription_cancelled(customer(), plan())
    assert_branded_email(email, "Subscription Cancelled")
  end
end
```

If the file EXISTS already, do not delete what's there. Instead, add the same tests as new `test "..." do ... end` blocks before the module's closing `end`. Make sure the existing `defp` helpers don't conflict — rename the new helpers to e.g. `_v2_customer/0` if needed.

- [ ] **Step 3: Run the tests**

Run: `mix test test/mobile_car_wash/notifications/email_test.exs`
Expected: 11 tests, 0 failures.

If any test fails because of a difference in how the email constructs its body (e.g., `appointment.scheduled_at` is a `DateTime` not a string in real callers), adjust the test fixtures to match the production data shape. Don't change the production email functions to satisfy the test.

- [ ] **Step 4: Commit**

```bash
git add test/mobile_car_wash/notifications/email_test.exs
git commit -m "email: add smoke test per email function

Asserts subject, from, and that Layout wrapping happened (footer present
in both html and text bodies)."
```

---

## Task 16: Run full test suite to catch regressions

**Files:** none modified.

- [ ] **Step 1: Run the full suite**

Run: `mix test 2>&1 | tail -3`
Expected: at least the Plan 1 baseline of 992 tests + 11 new email tests + 13 new layout tests = 1016 tests, 0 failures.

If failures exist, triage:
- If they're in existing tests asserting OLD email body content (e.g. asserting on `mobilecarwash.com` or the steel-blue color), update those assertions to match the new branded output.
- If they're in unrelated tests, that's a pre-existing issue; investigate separately.

- [ ] **Step 2: If any test changes were needed, commit**

```bash
git add -p   # selectively stage just the assertion updates
git commit -m "test: update email assertions for new branded layout"
```

If no test changes were needed, skip this commit.

---

## Task 17: Append deployment checklist additions

**Files:**
- Modify: deployment checklist file (location to be discovered)

- [ ] **Step 1: Find the deployment checklist file**

Run: `find . -type f -iname "*deploy*" -not -path "./_build/*" -not -path "./deps/*" | head -10`

Look for a file like `docs/deployment_checklist.md`, `DEPLOYMENT.md`, or similar. The user's MEMORY.md references `[Deployment Checklist](deployment_checklist.md)` (in their personal memory store, NOT the repo) — so the in-repo file may have a slightly different name.

If no matching file is found, create one at `docs/deployment_checklist.md`.

- [ ] **Step 2: Append the new sections**

Append to the end of the discovered (or newly-created) file:

```markdown
## Pre-deploy: email sender domain change (Plan 2)

The email sender changed from `noreply@mobilecarwash.com` to
`noreply@drivewaydetailcosa.com`. Before deploying:

- [ ] Add SPF record to drivewaydetailcosa.com DNS:
      `v=spf1 include:<email-provider-spf> ~all`
      (substitute the actual provider — SendGrid, Mailgun, AWS SES, etc.)
- [ ] Add DKIM record(s) per email provider's instructions
      (typically a CNAME or TXT at a provider-specific selector).
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

- [ ] **Step 3: Commit**

```bash
git add docs/deployment_checklist.md  # adjust path if you created elsewhere
git commit -m "docs: add Plan 2 deployment checklist (email DNS + Stripe branding)"
```

---

## Task 18: Final verification

**Files:** none modified.

- [ ] **Step 1: Run the full test suite once more**

Run: `mix test 2>&1 | tail -3`
Expected: ≥1016 tests, 0 failures (Plan 1's 992 + 13 layout + 11 email smoke + any preserved tests).

- [ ] **Step 2: Verify compile is clean with --warnings-as-errors**

Run: `mix compile --warnings-as-errors 2>&1 | tail -5`
Expected: `Generated mobile_car_wash app` with no errors and no warnings.

- [ ] **Step 3: Verify formatting**

Run: `mix format --check-formatted 2>&1 | tail -3`
Expected: no output (clean).

If formatting is off, run `mix format` and commit:
```bash
mix format
git add -A
git commit -m "chore: mix format"
```

- [ ] **Step 4: Verify production asset build**

Run: `mix assets.deploy 2>&1 | tail -10`
Expected: exit 0, no warnings.

- [ ] **Step 5: Boot dev server, manual smoke test**

Run: `mix phx.server` (separate terminal)
Open `http://localhost:4000`. Confirm:
- New favicon visible in browser tab (slate pin)
- Page renders normally (no broken layout from the favicon-link changes)

Open `http://localhost:4000/admin/style_guide` (sign in as admin if needed). Confirm everything from Plan 1 still renders correctly.

Stop the server.

- [ ] **Step 6: Verify the OG image previews correctly**

Run: `open priv/static/images/og-share-v2.png` (Mac) or otherwise view the file.
Confirm: 1200×630, white background, "Driveway Detail Co" branding top-left, hero headline left-aligned, cyan accent square bottom-right. No clipped text.

- [ ] **Step 7: Confirm commit log**

Run: `git log --oneline main~30..HEAD | head -25`
You should see Plan 2's per-task commits (Tasks 1-17). All commits should have descriptive messages — no WIP/fixup messes.

- [ ] **Step 8: Report Plan 2 complete**

Plan 2 is complete. Summary for the user:

- 3 new logo SVGs (icon, light wordmark, dark wordmark)
- New OG share image (SVG source + rasterized PNG)
- 6-file favicon set (multi-res .ico + 5 PNGs)
- Email.Layout module + 13 layout tests
- All 11 email functions refactored + 11 smoke tests
- Sender updated to `noreply@drivewaydetailcosa.com`
- root.html.heex updated for new favicons + theme-color
- Deployment checklist appended with DNS + Stripe branding tasks

Old `logo_*.svg`, `og-share.*`, and favicon files are still present for one-release safety.

Recommend the user open `/admin/style_guide` and confirm the new favicon shows in the browser tab; review the OG image PNG; and complete the DNS / Stripe Dashboard tasks from the deployment checklist before promoting to prod.

---

## What's NOT in Plan 2 (reminder)

These are explicitly deferred — do NOT implement them in Plan 2:

- Cash flow page redesign → **Plan 4**
- Customer-facing redesigns (landing, booking, success) → **Plan 3**
- Wallaby setup + 5 E2E tests → **Plan 5**
- `site.webmanifest` for PWA → follow-up after Plan 5
- Real unsubscribe-flow wiring → separate spec
- Deletion of old logo / OG / favicon files → cleanup pass after Plan 5
- Push-notification icons → Plan 5 (mobile work)
