# Handoff — Photo Flow: Lightbox + Booking Prompt Slice

**Date:** 2026-07-12
**For:** the next agent picking up photo-flow work
**Repo:** MobileCarWash (Elixir / Phoenix LiveView / Ash / AshPostgres)
**Supersedes:** `HANDOFF-photoflow-next-slice.md` (its recommended slice shipped; its
backlog is folded into this document)
**Prereq shipped:** three photo slices are merged to `main`. Slice 1: on-device
downscale + background tech-overlay uploads. Slice 2: tile-based concurrent tech
capture + direct-to-Spaces presigned uploads. Slice 3 (this session): before/after
reveal + share on the customer status page. `mix precommit` green on the merged
tree (1444+ tests, 0 failures).

---

## What already shipped (the ground you're building on)

Everything in the previous handoff's "already shipped" section still holds
(downscale hook, tile capture, direct-to-Spaces transport, problem-photo modal,
`PhotoUpload` backend). New since then:

- **Before/after reveal** — `lib/mobile_car_wash_web/live/appointment_status_live.ex`.
  When an appointment is `:completed`, the photo section renders one draggable
  comparison slider per complete before/after pair (`@pairs`, priority order
  front → rear → driver_side → passenger_side → interior → wheels), an
  "More photos" strip for unpaired photos (`@unpaired_photos`), and no placeholder
  cells. All other statuses keep the live thumbnail grid. Soft-deleted photos are
  now filtered everywhere on this page (`load_photos/1`).
- **`BeforeAfterSlider` hook** — `assets/js/hooks/before_after_slider.js`. Pointer
  scrub (tap jumps, drag scrubs), one-time wipe animation on first ≥60%
  scroll-into-view (P 100→50 over 1.2 s ease-out), `prefers-reduced-motion` skips
  to rest. DOM contract: container `id="reveal-#{area}"`, `phx-update="ignore"`,
  children `img[data-role="before"]` + `div[data-role="divider"]`.
- **Share your wash** — CTA card + pair-picker modal on the completed status page;
  `ShareWashCard` hook (`assets/js/hooks/share_wash_card.js`) composes a branded
  1080×1350 card on canvas (Before/After chips, "Driveway Detail" wordmark,
  "Get $10 off your first wash · CODE" footer) and opens the native share sheet.
  Exclusive fallback ladder — exactly one feedback event per click:
  `share_degraded` (text-only share happened) or `share_fallback_done` with
  validated mode `"image" | "image_only" | "link"`. `ctx.roundRect` is
  feature-detected (arc fallback for iOS Safari < 16). Referral link/code come
  from `Referrals.share_link_for/1` (code parsed back out of the link — the
  in-memory struct may have a nil code pre-backfill).
- Spec + plan: `docs/superpowers/specs/2026-07-11-before-after-reveal-share-design.md`,
  `docs/superpowers/plans/2026-07-11-before-after-reveal-share.md`.

## Operational prerequisites still open (do these before/at next deploy)

1. **CORS on the Space** — allowed origin = production origin, methods = `PUT`
   **and `GET`** (GET is new: slider images load `crossorigin="anonymous"` and are
   drawn to a canvas; without CORS on GET the canvas taints and every share
   degrades to text-only), headers `content-type`, max age 3600. Details in the
   direct-to-spaces spec's deploy checklist.
2. **Manual phone verification** — now covers three things with no automated
   coverage: (a) the S3PUT upload path (shoot two checklist areas back-to-back,
   both tiles progress simultaneously, both land); (b) drag a before/after slider
   and watch the wipe play once; (c) share a card from a completed wash — the
   composed image (not just text) must reach the share sheet on iOS Safari and
   Android Chrome.

## The next slice — recommended: lightbox everywhere

From the original ranked list, the remaining candidates:

1. **Lightbox everywhere (recommended).** No photo on any surface is tappable.
   The tech inspects customer problem photos at 80 px
   (`checklist_live.ex` problem-photos strip); customers can't zoom the reveal
   sliders, the "More photos" strip, or their own problem photos. One shared
   tap-to-fullscreen component (LiveView-rendered overlay or a small JS hook)
   used by: tech checklist problem strip, customer status page (sliders get a
   discreet expand affordance — don't fight the drag gesture), appointments
   problem-photo modal. Small, high-leverage, pure-UI.
2. **Booking-flow photo step.** `BookingComponents.step_indicator` declares a
   `:photos` step that `booking_live.ex` never renders (`step_indicator` itself
   is uncalled). Cheaper alternative the prior brainstorm favored: prompt on the
   booking-success page ("Show your tech what to focus on") reusing the existing
   `PhotoUploader` component. Today customers only find "+ Problem Area Photos"
   on the appointments list.

## Follow-up backlog (triaged ship-as-is; pick up opportunistically)

New from this slice's reviews (all judged backlog-grade at final review):

- Duplicate live photos in a paired area vanish from view: `unpaired_photos/3`
  rejects by `car_part`, so a second live `before` for an area shows nowhere.
  Reject by photo identity instead. (Only reachable via the API path, which
  doesn't slot-replace.)
- `load_photos/1` has no sort — pair selection between duplicates and strip order
  are nondeterministic. Add `Ash.Query.sort(inserted_at: :asc)`.
- Slider container's `data-before-url`/`data-after-url` are dead attributes (the
  hook reads the `img` children); tests assert them. Consume or retarget tests.
- `open_share_modal` isn't gated on `status == :completed` (own-data only, no
  security impact; render already gates).
- Modal-reappear ultra-edge: after the empty-pairs guard hides an open modal,
  `@share_modal_open` stays true; a later reload that restores a pair pops the
  modal back up unprompted.
- Deepest share fallback (compose fails + no share sheet + clipboard blocked)
  shows "your link was shared instead" when nothing happened.
- Accessibility: sliders are pointer-only (no keyboard/ARIA); reveal/strip/modal
  images lack `alt`. Matches the page's existing patterns; fix as a theme.
- No test: nil/off-key-area `car_part` lands in "More photos"; in_progress→
  completed PubSub transition recomputing pairs (the marquee moment — prioritize
  this test); `select_share_area` unknown-area rejection branch.
- Carried from previous handoff: customer save-failure message placement;
  two-tap "Try again" on error tiles; idempotency row-count assertion;
  `s3_config/0` extraction; duplicate `%{key: key}` save blocks; per-surface
  `:too_many_files` copy; 2 pre-existing `photo_uploader_test.exs` compiler
  warnings; key areas static per service type.

## Process notes that will save you time

- Everything in the previous handoff's process notes still applies verbatim
  (concurrent Codex session in the main checkout — never work there; worktree
  setup with the `deps` symlink; `mix precommit` gate; verified LiveView-test
  facts; owner workflow: brainstorm → spec → plan → subagent execution → final
  review → merge options, then "merge and push" + cleanup).
- **`.superpowers/sdd/task-{1,5,6}-report.md` are tracked in git** (committed to
  main by an earlier session, and both concurrent sessions have since collided on
  them). If your subagents write SDD reports to `.superpowers/sdd/`, they will
  show as modifications to tracked files and can block merges — `git restore`
  them before merging (copy the contents to your session scratchpad first).
  Consider a cleanup commit that removes `.superpowers/` from tracking and
  gitignores it — coordinate with the other session before doing so.
- origin/main moves while you work (the Codex session ships to main too). Before
  pushing: `git fetch`, check file overlap (`git diff --name-only BASE..origin/main`),
  merge origin/main into your branch in the worktree, re-run `mix precommit` on
  the merged tree, then push `HEAD:main`.
- The reveal/share slice's LiveView tests are a good template for the lightbox
  slice: `create_photo/4` fixture, DOM-contract assertions on `data-*`/hook ids,
  `render_hook` for events with `Process.alive?(view.pid)` on crash-path tests.
