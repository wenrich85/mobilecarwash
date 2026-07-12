# Before/After Reveal + Share — Design

**Date:** 2026-07-11
**Status:** Approved by owner (brainstorm 2026-07-11)
**Surfaces:** Customer appointment status page (`AppointmentStatusLive`)
**Depends on:** Photo slices 1 & 2 (merged to main at `cd30ef4`); tech capture and
direct-to-Spaces transport are done — this slice only consumes photos.

## Problem

The completed wash's status page renders before/after photos as small static
thumbnail pairs with `○`/`⋯` placeholders. This is the product's most emotionally
loaded moment — the customer seeing the transformation — and today it looks like a
debug view. There is also no way to show anyone: photos aren't shareable, and the
referral system (share link + $10 credit, live on the appointments page) never
meets the wow moment.

## Goals

1. Make opening the status page after a completed wash feel like a reveal.
2. Convert that moment into acquisition: one tap composes a branded before/after
   card and opens the phone's native share sheet with the customer's referral link.

## Non-goals (explicitly out of scope)

- Public share pages / OG unfurl (photos stay private; nothing new is publicly routable)
- Share analytics or tracking events
- Tap-to-fullscreen lightbox (separate backlog item)
- Booking-flow photo step
- Per-service key areas
- Any change to tech-side capture or upload transport

## Decisions made during brainstorm

| Question | Decision |
|---|---|
| Share output | Client-composed image via Web Share API (no server composition, no public page) |
| Pair choice | Customer picks in a modal; smart default = first complete pair in priority order |
| Reveal moment | One-time animated wipe per slider on first scroll-into-view |
| Card content | Photos + Before/After labels + wordmark + offer footer ("Get $10 off…" + referral code) |
| Approach | A — all client-side, two JS hooks, zero backend changes (over server-side libvips composition) |

## Architecture

All new behavior lives in one LiveView and two self-contained JS hooks. No schema
changes, no new routes, no new dependencies, no backend modules touched.

```
AppointmentStatusLive (completed status)
├── reveal section: one BeforeAfterSlider hook per complete pair
├── "More photos" strip: unpaired photos, existing thumbnail treatment
├── Share CTA card → opens picker modal (LiveView assigns, no JS state)
└── picker modal → Share button carries data-* → ShareWashCard hook
                                                  ├── canvas composition
                                                  └── navigator.share / fallback
```

### Page states

`AppointmentStatusLive` keeps its current behavior for every status except
`:completed`:

- **In-progress (and all other statuses):** the existing live thumbnail grid is
  untouched.
- **Completed:** the photo section switches to reveal mode:
  - One comparison slider per key area that has **both** a before and an after
    photo ("complete pair").
  - Areas with only one photo render in a small "More photos" thumbnail strip at
    the bottom — nothing hidden, no broken sliders.
  - Areas with no photos are dropped entirely (today they render `○` placeholder
    cells even on completed washes — this fixes that).
  - Section heading changes from "Photos" to a completion-toned "The reveal"
    treatment. Existing success banner above is unchanged.

Pair computation is a pure helper in the LiveView:
`complete_pairs(before_photos, after_photos)` matches on `car_part` across the six
key areas in fixed priority order: front → rear → driver_side → passenger_side →
interior → wheels. Photos already arrive URL-applied via `PhotoUpload.apply_url/1`.

### Component 1: `BeforeAfterSlider` JS hook

`assets/js/hooks/before_after_slider.js`, one instance per area. Client-side only —
nothing is sent to the server.

- **Anatomy:** a `4:3` rounded container; *after* image is the base layer, *before*
  image stacked on top clipped with `clip-path: inset(0 X% 0 0)`. A vertical
  divider line with a circular drag handle (chevrons) sits at the clip edge.
  Corner chips label "Before" / "After".
- **Interaction:** pointer events on the whole container — tap anywhere to jump the
  divider there, drag to scrub. Handle position and clip stay in sync; state lives
  in the hook.
- **One-time wipe:** let P = the divider position as % of container width, i.e.
  the portion showing the *before* image (P=100 → all before, P=0 → all after;
  `clip-path: inset(0 calc(100% − P) 0 0)` on the before layer). An
  IntersectionObserver watches the slider; the first time it is ≥60% visible,
  animate P from 100 to 50 over ~1.2 s with an ease-out curve. Once per slider per page load; no persistence (replaying on a
  later visit is acceptable — the moment matters, not the novelty).
- **Reduced motion:** if `prefers-reduced-motion: reduce`, skip the animation and
  rest at 50% immediately.
- **Images** carry `crossorigin="anonymous"` so the same bytes are CORS-clean in
  cache for the share hook's canvas (see CORS note below).

Visual polish (typography, chip styling, handle design) is refined at
implementation time under the `frontend-design` skill; the structure above is fixed.

### Component 2: Share flow

**Entry point.** Below the sliders on a completed wash: one hero CTA — "Share your
wash" — full-width primary button inside a gradient card matching the appointments
page "Share & earn" card, with the "$10 credit" incentive line. Renders only when
at least one complete pair exists (the page is already customer-authenticated —
`mount` rejects any viewer who doesn't own the appointment). Mount computes `share_link = Referrals.share_link_for(customer)` exactly as
`appointments_live.ex` does (this also backfills legacy customers' referral codes).

**Picker modal (LiveView-rendered).** `phx-click` sets `@share_modal_open`; no JS
state. Shows shareable pairs as horizontally swipeable side-by-side thumbnails.
Smart default preselected: first complete pair in priority order. Selecting a pair
is a `phx-click` assigning `@share_area`. One "Share" button confirms. With a
single pair the modal still opens with it preselected — the confirm step doubles as
a preview of what's about to be shared.

**Composition (`ShareWashCard` hook, `assets/js/hooks/share_wash_card.js`).** The
Share button carries `data-` attributes: before URL, after URL, area label,
referral code, reward dollars, share link, share text. On click the hook:

1. Loads both images via `new Image()` with `crossorigin="anonymous"` (typically
   already in HTTP cache from the sliders).
2. Draws an offscreen canvas at **1080×1350 (4:5 portrait)**: the two photos
   stacked vertically with "Before"/"After" corner labels, a thin divider, and a
   bottom footer strip — wordmark text "Driveway Detail" left, "Get $10 off your
   first wash · CODE" right. All text via canvas `fillText` with the system font
   stack; no image assets.
3. Exports `canvas.toBlob("image/jpeg", 0.9)` → `File`.

**Share.** If `navigator.canShare({files: [file]})`:
`navigator.share({files, text, url})` with text
"Look what Driveway Detail did for my car ✨ Get $10 off your first wash:" + the
referral link. Otherwise (desktop Chrome/Firefox): download the JPEG and copy
share text + link to the clipboard, then show "Image saved — link copied"
confirmation inside the modal.
If the clipboard write fails after a successful download, the hook reports mode "image_only" and the modal shows "Image saved".

### Error handling

- **Image load failure or tainted-canvas `SecurityError`** (CORS misconfig):
  degrade to sharing text + link only via `navigator.share`/clipboard — the
  customer still shares *something*. The hook `pushEvent`s `share_degraded`; the
  LiveView renders a soft notice in the modal ("Couldn't attach the photo").
- **User-cancelled share sheet** (`AbortError`): silently ignored.
- **No flash messages anywhere** — matches the established photo-flow convention.

## Files touched

| File | Change |
|---|---|
| `lib/mobile_car_wash_web/live/appointment_status_live.ex` | Reveal-mode render branch, share CTA, picker modal, `@share_modal_open`/`@share_area`/`@share_link` assigns, `share_degraded` handler, `complete_pairs/2` helper |
| `assets/js/hooks/before_after_slider.js` | New hook: drag + wipe + reduced-motion |
| `assets/js/hooks/share_wash_card.js` | New hook: compose + share + fallbacks |
| `assets/js/app.js` | Register both hooks |

## Testing

LiveView tests in the existing `test/mobile_car_wash_web/live/appointment_status_live_test.exs`:

- Completed appointment with full pairs renders slider containers; hook ids and
  `data-` attributes carry the right photo URLs per area.
- Incomplete pairs fall to the "More photos" strip; empty areas render nothing.
- In-progress appointment still renders the live grid untouched.
- Share CTA hidden when no complete pair exists.
- Modal opens; smart default picks front first, and next-in-priority when front is
  incomplete; selecting an area updates the Share button's `data-` attributes.
- `share_degraded` event renders the soft notice.
- Referral link present with `?ref=CODE`.

JS hooks have no automated coverage (no JS test infra in this codebase — consistent
with `ImageDownscale`/`S3PUT`). They join the manual phone verification checklist:
drag a slider, watch the wipe, share a card end-to-end on iOS Safari and Android
Chrome.

Gate: `mix precommit` green, zero compiler warnings.

## Deploy checklist addition

The Spaces CORS rule (already pending for `PUT` from slice 2) must **also allow
`GET`** from the production origin. Without it, `crossorigin="anonymous"` image
loads fail (or the canvas taints) and every share degrades to text-only. Same
config, same deploy, one rule.

## Risks

- **Canvas/CORS on real devices** is the only genuinely untestable-in-CI surface.
  Mitigation: explicit degradation path (text-only share) + manual phone
  verification before calling the slice done.
- **Web Share API file support** is absent on desktop Firefox/Chrome-on-Linux —
  handled by the download-plus-clipboard fallback, not treated as an error.
