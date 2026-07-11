# Handoff — Photo Flow: Next Slice

**Date:** 2026-07-11
**For:** the next agent picking up photo-flow work
**Repo:** MobileCarWash (Elixir / Phoenix LiveView / Ash / AshPostgres)
**Prereq shipped:** two photo slices are merged to `main` and pushed. Slice 1 (merge `7241297`): on-device downscale + background tech-overlay uploads. Slice 2 (merge `1240277`): tile-based concurrent tech capture + direct-to-Spaces presigned uploads. `mix precommit` green on the merged tree (1433 tests, 0 failures). Feature branches and worktrees deleted.

---

## What already shipped (the ground you're building on)

**Capture and transport are done.** Do not redesign these — extend them.

- **On-device downscale** — `assets/js/hooks/image_downscale.js`, hook `ImageDownscale`. Resizes to ≤1600 px JPEG before LiveView sees the file. Attached to *wrappers* of file inputs (never the input itself — the input carries LiveView's internal `data-phx-hook="Phoenix.LiveFileUpload"`, which wins over `phx-hook`, so a hook on the input silently never mounts).
- **Tech checklist tile capture** — `lib/mobile_car_wash_web/live/checklist_live.ex`. 12 upload configs named `:"#{type}_#{area}"` (`:before_front` … `:after_wheels`); the config name encodes photo_type + car_part. Tiles are camera-direct (`capture="environment"`), upload concurrently with per-tile progress, auto-save on completion (`handle_tile_progress/3` → `save_tile_file/5`), and report failures on the tile (`@tile_errors`) with a Try-again control. No flash messages for photo results anywhere — keep it that way.
- **Direct-to-Spaces transport** — active only when `photo_storage == :s3` (prod; DigitalOcean Spaces via `AWS_S3_ENDPOINT`). `PhotoUpload.external_entry_meta/3` presigns a 5-minute PUT with the Content-Type derived server-side from the filename (`MIME.from_path`); JS uploader `S3PUT` (`assets/js/uploaders/s3_put.js`, 30 s timeout) sends bytes browser→bucket; `PhotoUpload.save_external_file/5` records metadata only. Dev/test keep the channel path — the conditional lives in `tile_upload_opts/0` (checklist) and `problem_photo_opts/0` (appointments).
- **Customer problem-photo modal** — `lib/mobile_car_wash_web/live/appointments_live.ex` + shared `MobileCarWashWeb.PhotoUploader` component. Per-entry error cards; save failures render in the modal (`@photo_save_error`) instead of crashing; shared error copy in `PhotoUploader.error_message/1`.
- **Backend** — `lib/mobile_car_wash/operations/photo_upload.ex`: `object_key/3`, `presign_put/2`, `external_uploads?/0`, `save_external_file/5`, shared `create_photo_record/5`. Slot replacement (soft-delete same type+part), idempotency keys, AI-analysis enqueue (customer `:problem_area` only) all shared by both save paths. Failed external saves best-effort delete the bucket object on both surfaces.

Design + plan for slice 2: `docs/superpowers/specs/2026-07-11-direct-to-spaces-uploads-design.md` and `docs/superpowers/plans/2026-07-11-direct-to-spaces-uploads.md`.

---

## Operational prerequisites still open (do these before/at next deploy)

1. **CORS on the Space** — allow method `PUT` from the production origin with header `content-type` (max age 3600). Hard prerequisite: without it every production upload fails with `:external_client_failure` (rendered on the tile, but still a failure). Spec's deploy checklist has details.
2. **Manual phone verification** — the S3PUT JS path and real CORS behavior have no automated coverage. Shoot two checklist areas back-to-back: both tiles must show progress simultaneously; both photos must land (object in Space + Photo row + renders back). Also upload a customer problem photo and confirm AI tags arrive.

---

## The next slice — recommended: before/after reveal + share

From the 2026-07-11 brainstorm, the remaining ranked candidates:

1. **Before/after reveal + share (recommended).** The completed wash's status page (`lib/mobile_car_wash_web/live/appointment_status_live.ex`) renders before/after as small static thumbnail pairs with `○`/`⋯` placeholders — the product's most emotionally loaded moment, wasted. Build: a draggable before/after comparison slider per area for completed washes, plus a "Share your wash" action that composes the best pair into a shareable card and plugs into the existing referral system (share-link + credit already live on `appointments_live.ex` — see `MobileCarWash.Marketing.Referrals.share_link_for/1`). This converts the wow moment into acquisition. Design-heavy: run `superpowers:brainstorming` + the `frontend-design` skill; photos pair by `car_part` via the same six key areas.
2. **Lightbox everywhere.** No photo on any surface is tappable; the tech inspects customer problem photos at 80 px (`checklist_live.ex` problem-photos strip). One shared tap-to-fullscreen component. Small; could ride along with slice 1 or precede it.
3. **Booking-flow photo step.** `BookingComponents.step_indicator` declares a `:photos` step that `booking_live.ex` never renders (designed, never shipped — `step_indicator` itself is uncalled). Cheaper alternative: prompt on the booking-success page ("Show your tech what to focus on"). Today customers only find "+ Problem Area Photos" on the appointments list.

## Follow-up backlog (reviewed, triaged ship-as-is; pick up opportunistically)

- Customer save-failure message could move from the modal body onto the failed entry card itself.
- "Try again" on an error tile returns it to capture state; the tech taps again to open the camera (two taps). Acceptable; could become a single-tap label after cancel.
- Idempotency test asserts same photo id but not row count; external-path tests don't cover `:caption`/`:checklist_item_id`; only `.jpg`/`.gif` extensions exercised.
- `s3_region`/`ExAws.Config.new` lookup duplicated across `presign_put/1`, `presign_url/1`, `delete_file/1` — extract `s3_config/0`.
- The two `%{key: key}` save-and-cleanup blocks (checklist + appointments) are near-duplicates.
- Checklist `:too_many_files` copy is the shared generic "Too many photos at once." (was "One photo at a time."). Owner accepted; revisit only if per-surface copy becomes a theme.
- `test/mobile_car_wash_web/components/photo_uploader_test.exs` has 2 pre-existing compiler warnings (unused import, unused stub).
- Key areas are static for all services — an interior-only detail still demands exterior before photos. Derive from service type someday.

---

## Process notes that will save you time

- **Concurrent sessions are real.** The owner often runs a second (Codex) session in the main checkout. NEVER work in `/Users/wrich/Documents/MobileCarWash` directly — create a git worktree (e.g. under `/Users/wrich/Documents/MobileCarWash-worktrees/`), and put scratch/briefs/ledgers in the *worktree's* `.superpowers/`, not the main repo's (a main-repo report file got overwritten by the other session mid-run). Before any merge/push, check the main checkout for that session's unpushed commits — merge onto `origin/main` in your worktree and push `HEAD:main` rather than publishing their WIP.
- **Worktree setup:** symlink deps to save a fetch (`ln -s /Users/wrich/Documents/MobileCarWash/deps deps`) — but never `git add -A` (the symlink is not gitignored). `_build` compiles fresh (~1–2 min).
- **Quality gate:** `mix precommit` (format + compile + full suite, ~3.5 min). Zero compiler warnings is enforced by review here.
- **Verified LiveView-test facts (don't re-derive):** `render_upload/3` percent is *incremental* (50 then 50, not 50 then 100); an oversized file makes `render_upload` return `{:error, [[ref, :too_large]]}` — it does not raise; a file under 4 bytes deterministically fails saves with "File too small to validate" (handy for error-path tests); `preflight_upload/1` returns the external callback's atom-keyed meta; external uploads drive end-to-end through `render_upload` with no network (see the "external uploads (s3 backend)" describes in `checklist_live_test.exs` / `appointments_photo_upload_test.exs` for the pattern).
- **Workflow the owner expects:** superpowers skills — brainstorm → spec (committed) → plan (committed) → subagent-driven execution with per-task review → final whole-branch review → present merge options; then "merge and push" and delete branches/worktrees.
