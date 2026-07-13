# Lightbox Everywhere — Design

**Date:** 2026-07-12
**Status:** Approved
**Slice:** Photo flow, slice 4 (follows before/after reveal + share)
**Handoff context:** `docs/superpowers/HANDOFF-photoflow-lightbox.md`

## Problem

No photo on any surface is tappable. Techs inspect customer problem photos at
80 px; customers can't view the reveal sliders, "More photos" strip, or their
own problem photos at any useful size. One shared tap-to-fullscreen component
fixes all of it.

## Decisions (from brainstorm)

| Question | Decision |
|---|---|
| Surface scope | **All** photo surfaces (six wiring points, see below) |
| Slider expand | Fullscreen **draggable slider**, reusing extracted scrub logic |
| Navigation | Gallery within a group: swipe, chevrons, arrow keys, "2 of 5" counter |
| Accessibility | Full a11y on the lightbox + `alt` on every touched image |
| Zoom | Fullscreen only; pinch-zoom/pan deferred |
| Architecture | **Pure client-side JS hook** (option A) — zero new server events/assigns |

## Architecture

Three pieces:

### 1. `assets/js/hooks/lightbox.js`

One hook instance per page, attached to the overlay root. Installs a single
delegated `click` listener on `document` for `[data-lightbox]` and
`[data-lightbox-slider]` elements.

On tap of a `[data-lightbox]` image it **snapshots the group at open time**:
`document.querySelectorAll('[data-lightbox="<group>"]')` in DOM order, capturing
`{src, alt}` into a plain array, then opens the overlay at the tapped index.
Navigation walks the snapshot, never the live DOM — an open lightbox is immune
to PubSub-driven re-renders (the bug class the share modal was patched for).
The next open re-snapshots.

Two display modes:

- **Image mode** — fullscreen `<img>`; swipe / chevrons / arrow keys move
  through the snapshot; ends clamp (no wrap); chevrons disable at the edges and
  are hidden for single-photo groups; counter "n of m".
- **Slider mode** — opened by `[data-lightbox-slider]` expand buttons;
  fullscreen before/after scrub via `slider_core`; single item — no swipe
  navigation, no chevrons, no counter, no caption line (horizontal drag
  belongs to the scrub). Scrub starts at P=50 (the page slider's post-wipe
  rest position).

Cleanup in `destroyed()`: remove the document listener, unlock scroll, drop
state (covers LiveView navigation while open).

### 2. `assets/js/slider_core.js`

The pointer-scrub logic (pointerdown/move/up → clip-path inset + divider
`left`) extracted from `before_after_slider.js` and shared by that hook and the
lightbox's slider mode. `BeforeAfterSlider` keeps its DOM contract, wipe
animation, IntersectionObserver, and `prefers-reduced-motion` behavior
unchanged — extraction must be behavior-preserving.

### 3. `<.lightbox_root />` — `MobileCarWashWeb.Components.Lightbox`

A function component rendering the overlay skeleton statically in HEEx, hidden
until opened, with `id="lightbox-root"`, `phx-hook="Lightbox"`, and
`phx-update="ignore"`. Skeleton contains: backdrop, stage (image container /
slider container / error message), close button, prev/next chevrons, counter,
caption line. Server-rendered skeleton means LiveView tests can assert the
dialog structure; the hook only toggles and hydrates it.

Rendered once in each LiveView that shows photos: `checklist_live.ex`,
`appointment_status_live.ex`, `appointments_live.ex`, `tech/job_live.ex`.

Both hooks registered in `assets/js/app.js` (`Lightbox` new; `BeforeAfterSlider`
already present).

## DOM contract

Plain photo (opt-in per `<img>`):

```heex
<img src={photo.file_path} alt={...} data-lightbox="problem-photos"
     class="... cursor-zoom-in" />
```

- Group = the `data-lightbox` value; membership and order = DOM order.
- Optional `data-lightbox-caption={photo.caption}`: shown in the overlay's
  caption line; the line is hidden when the attribute is absent or empty. The
  snapshot captures `{src, alt, caption}`.
- Fullscreen reuses the same `src` (single stored size; local path or 4-hour
  presigned GET URL — already loaded on the page, so browser cache makes the
  open instant).
- Every wired `<img>` gets real `alt` text: `photo.caption` when present,
  otherwise a descriptive fallback ("Problem photo", "Before — front", …).

Slider expand — a small `⤢` button absolutely positioned top-right over each
slider, **outside** the `phx-update="ignore"` container (sibling within a
shared relative wrapper) so it neither fights the drag gesture nor gets
clobbered by the hook:

```heex
<button aria-label="View comparison fullscreen"
        data-lightbox-slider
        data-before-url={pair.before.file_path}
        data-after-url={pair.after.file_path}>
```

This consumes the previously-dead `data-before-url`/`data-after-url`
attributes (named backlog item): they move from the slider container to the
expand button, and the existing container-attribute tests are retargeted.

## Wiring points (six)

| # | Surface | File / location | Group |
|---|---|---|---|
| 1 | Problem strip (tech checklist) | `lib/mobile_car_wash_web/live/checklist_live.ex` problem-photos strip | `"problem-photos"` |
| 2 | Before/after tiles (tech checklist) | `checklist_live.ex` `photo_tile/1` | `"checklist-photos"` — main img only; the ghost-overlay img is decorative and excluded |
| 3 | Reveal sliders (customer status) | `lib/mobile_car_wash_web/live/appointment_status_live.ex` pairs section | slider mode, per-pair expand button |
| 4 | "More photos" strip, problem thumbs, during-wash grid (customer status) | `appointment_status_live.ex` | `"more-photos"`, `"problem-photos"`, `"wash-photos"` |
| 5 | Uploader preview grid | `lib/mobile_car_wash_web/components/photo_uploader.ex` `preview_grid/1` | `"uploaded-photos"` — img tap only; delete button untouched. Covers the appointments problem-photo modal and any future uploader consumer. |
| 6 | Customer problem photos (tech job brief) | `lib/mobile_car_wash_web/live/tech/job_live.ex` problem-photos grid | `"problem-photos"` (already has `alt` via `problem_photo_label/1`) |

## Interaction & accessibility

**Open:** tap thumbnail → overlay fades in (fade skipped under
`prefers-reduced-motion`); body scroll locked.

**Close:** ✕ button, Escape, or backdrop tap. Tapping the photo itself does
not close (accidental-hit protection mid-swipe). Close is immediate (no fade
out). On close: scroll restored, **focus returns to the opening element**.

**Navigate (image mode):** horizontal swipe (pointer events, ~40 px
threshold), on-screen chevrons, ←/→ keys.

**A11y:** overlay `role="dialog"` `aria-modal="true"`
`aria-label="Photo viewer"`; focus moves to the close button on open; Tab
cycles within the overlay's focusable set (close/prev/next); all buttons have
`aria-label`s; counter is `aria-live="polite"`; lightbox image `alt` mirrors
the source thumbnail's.

## Edge cases

- **DOM churn while open** (PubSub photo updates): harmless — navigation uses
  the open-time snapshot; next open re-snapshots.
- **LiveView navigation while open:** `destroyed()` cleans listener, scroll
  lock, state.
- **Image load failure** (e.g. presigned URL expired after 4 h idle):
  `onerror` swaps the stage to a plain "Couldn't load photo" message.
- **Open while open:** re-snapshots and replaces the stage; no stacking.

## Testing

LiveView tests (DOM contract is the API — zero new server events):

- Per surface: wired imgs carry the right `data-lightbox` group and non-empty
  `alt`; excluded images (ghost overlay) carry neither.
- Overlay root rendered once per page with `phx-hook="Lightbox"`,
  `phx-update="ignore"`, `role="dialog"`, `aria-modal="true"`, and
  close/prev/next buttons with `aria-label`s.
- Slider expand: one button per pair with `data-lightbox-slider` and correct
  before/after URLs; retarget the existing dead-attribute tests from the
  container to the button.
- Test style follows the reveal/share slice: `create_photo/4` fixture,
  DOM-contract assertions on `data-*`/ids.

JS layer: no JS test infra exists; hook and `slider_core` stay small to
compensate. Manual on-phone checklist addition: tap-to-open on each surface,
swipe/arrow navigation, Escape/backdrop close, fullscreen scrub, focus return,
and — the key regression risk — **the page slider still scrubs and wipes after
the `slider_core` extraction**.

## Out of scope

- Pinch-zoom / pan within the lightbox.
- Page-wide a11y sweep beyond the surfaces this slice touches.
- Other handoff backlog items (photo sort, duplicate-pair identity,
  modal-reappear edge, share-fallback copy).

## Process

All work in the `lightbox-everywhere` worktree off origin/main (1d2d81b —
includes the merged tech job brief). `mix precommit` gate before merge; fetch +
overlap check + merge origin/main + re-run precommit before pushing `HEAD:main`.
