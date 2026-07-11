# Direct-to-Spaces Photo Uploads + Tile-Based Concurrent Capture

**Date:** 2026-07-11
**Status:** Approved (revised: tile-based concurrent tech capture added)
**Branch:** `feature/direct-to-spaces-uploads`

## Problem

Two problems, one slice:

1. **Server-proxied uploads.** In production, every photo crosses the network
   twice: phone → Phoenix over the LiveView websocket, then Phoenix →
   DigitalOcean Spaces via a synchronous `ExAws` PUT inside the LiveView
   process (`PhotoUpload.save_to_s3/5`). The second hop re-reads the whole
   file into memory and blocks the user's LiveView process — taps freeze
   until the PUT returns.

2. **Serialized tech capture.** The tech checklist funnels every photo
   through a full-screen overlay with a single upload slot and a Save
   button: one photo at a time, tap-heavy, and the grid gives no feedback
   about in-flight transfers. A tech documenting 12 areas waits on each
   upload before starting the next.

The on-device downscale hook (shipped 2026-07-11) already cut transfer sizes
to a few hundred KB. This slice removes the second network hop and makes
capture concurrent: the tech taps an area tile, shoots, and is immediately
back on the grid — the tile itself shows upload progress, then the saved
photo, or an error with a retry. Multiple areas upload simultaneously.

## Decisions made during brainstorming

- **Storage target is DigitalOcean Spaces** (S3-compatible, `AWS_S3_ENDPOINT`
  set in prod). Spaces supports presigned **PUT** but not POST upload
  policies, so presigned PUT is the mechanism. It also works unchanged on
  plain AWS S3.
- **Validation posture: presign constraints only.** The server generates the
  object key, pins the Content-Type into the signature, and uses a short
  expiry. No async byte verification. Rationale: photos are only served back
  through auth-gated presigned GETs to the owner / assigned tech / admin; the
  accept list (`.jpg .jpeg .png .webp`) excludes SVG, so a mislabeled file is
  a broken image, not an XSS vector.
- **Scope: both surfaces** — the customer problem-area uploader
  (`AppointmentsLive`) and the tech checklist (`ChecklistLive`) — via shared
  plumbing.
- **Dev and tests keep the channel path.** External uploads activate only
  when `photo_storage == :s3`. With `:local`, `allow_upload` gets no
  `external:` option.
- **Revision (user):** tech capture is tile-based and concurrent. The tech
  takes a photo, returns to the grid, and sees progress in the box where the
  image will live; success and failure are reported on the tile itself, not
  via flash. The full-screen overlay and its Save button are removed —
  photos auto-save when their transfer completes, and Retake remains the
  correction mechanism.

## Part 1 — Tech checklist: tile-based concurrent capture

### Upload configs

One upload config per tile, declared in a loop at mount:

```
for type <- [:before, :after], area <- @key_area_ids do
  allow_upload(socket, :"#{type}_#{area}",
    accept: ~w(.jpg .jpeg .png .webp),
    max_entries: 1,
    max_file_size: 10_000_000,
    auto_upload: true,
    progress: &handle_tile_progress/3,
    external: (if PhotoUpload.external_uploads?(), do: &presign_photo/2)
  )
end
```

12 configs (2 types × 6 areas). The config **name** encodes photo_type and
car_part — no entry-to-area bookkeeping, no races when several areas upload
at once. LiveView uploads different configs concurrently without any extra
work.

### Tile anatomy

Each grid tile is a `<label>` for its own hidden `.live_file_input`
(`capture="environment"` so tapping opens the rear camera directly). Tile
states, in order:

1. **Empty** — dashed border, area label + instruction (as today). Tapping
   opens the camera.
2. **Uploading** — `live_img_preview` of the shot fills the tile immediately,
   with a progress bar along the bottom edge. The tech is already free to
   tap the next tile.
3. **Saved** — the persisted photo renders (as today: ✓ badge, Retake
   button). A photo that finished uploading auto-saves; no Save button.
4. **Error** — the tile shows a short message on the image area
   ("Upload failed") with a **Try again** control that cancels the dead
   entry and reopens the camera. Save failures (`save_file` /
   `save_external_file` errors) render the same way via a
   `tile_errors` assign (`%{config_name => message}`); flash is no longer
   used for photo save results.

The full-screen photo overlay, `show_photo_upload` assign, and the
`show_upload` / `cancel_upload` / `save_photo` events are deleted.

### Auto-save flow

`handle_tile_progress(name, entry, socket)`: when `entry.done?`, consume the
entry, parse `{photo_type, car_part}` from `name`, and call
`PhotoUpload.save_file/5` (channel path) or `save_external_file/5` (external
path) with `uploaded_by: :technician`. On success: broadcast
`AppointmentTracker.broadcast_photo/2`, `reload_photos`, clear any tile
error, run `maybe_complete_wash`. On failure: postpone/cancel the entry and
put the message in `tile_errors[name]`.

Wash-gating logic (`before_photos_complete?`, after-photos unlock,
`maybe_complete_wash`) is unchanged — it reads persisted photos, which now
simply appear sooner.

### Downscale hook

`ImageDownscale` is delegation-based (it catches `change` events from any
descendant file input), so it attaches **once per grid section** — a wrapper
div around the before-grid and one around the after-grid — instead of per
input.

### Supersession note

This deletes the overlay Save-gating shipped earlier on 2026-07-11
(`feat(photos): make photo uploads feel instant`). The overlay tests in
`checklist_live_test.exs` ("photo upload overlay" describe block) are
replaced by tile-flow tests; the always-success-flash fix carries forward in
spirit as per-tile error reporting.

## Part 2 — Direct-to-Spaces transport

### Data flow (production)

1. User picks/takes a photo. `ImageDownscale` shrinks it on-device.
2. LiveView preflights the entry and invokes the `external:` callback
   (in-process, local crypto — fast):
   - generates the object key
     `appointments/<appointment_id>/<photo_type>_<uuid><ext>` (same naming
     scheme as today, so display/cleanup/AI are unaffected),
   - returns `%{uploader: "S3PUT", url: presigned_put_url, headers: %{"content-type" => type}, key: key}`.
3. The `S3PUT` JS uploader XHR-PUTs the file directly to Spaces, reporting
   progress into the entry — tile and modal progress bars work unchanged.
   Multiple tiles PUT in parallel from the browser.
4. Consume time (tech: on-done in `handle_tile_progress`; customer: on-done
   in `handle_photo_progress`): `PhotoUpload.save_external_file/5` creates
   the Photo row with `file_path = key`. No bytes touch the server.
5. Downstream is untouched: `url_for/1` presigned GETs, the AI analyzer
   worker (fetches via `url_for`), PubSub broadcasts, retention cleanup.

### Components

**`MobileCarWash.Operations.PhotoUpload` (extend)**

- `object_key(appointment_id, photo_type, original_filename)` — extracted so
  both paths name objects identically.
- `presign_put(key, content_type)` — `ExAws.S3.presigned_url(config, :put, bucket, key, ...)`
  with `expires_in: 300` and the Content-Type signed. Returns
  `{:ok, url} | {:error, reason}`.
- `external_entry_meta(entry, appointment_id, photo_type)` — builds the map
  the `external:` callback returns (uploader name, url, headers, key).
- `save_external_file(appointment_id, key, original_filename, photo_type, opts)` —
  creates the Photo record. Reuses idempotency, slot soft-delete
  (`soft_delete_existing_slot/3`), and AI enqueue by extracting today's
  record-creation block from `do_save_file_validated/6` into a shared
  private helper. Skips magic-byte validation (bytes never present) but
  keeps the extension allow-list check on `original_filename`.
- `external_uploads?/0` — `storage_backend() == :s3`. The single switch all
  upload configs consult.

**`assets/js/uploaders/s3_put.js` (new)**

LiveView external uploader: XHR PUT to `entry.meta.url` with
`entry.meta.headers`, wiring `xhr.upload.onprogress` to
`entry.progress(...)` and errors to `entry.error()`. Registered on the
LiveSocket as `uploaders: {S3PUT}`.

**`AppointmentsLive` (modify)**

- Conditional `external:` on both existing configs; consume callback
  pattern-matches `%{path: path}` → `save_file/5` vs `%{key: key}` →
  `save_external_file/5`.
- `PhotoUploader.entry_preview` gains per-entry error display (message +
  remove control) so customer failures also report on the picture itself.

**`ChecklistLive` (rework per Part 1)**

- Tile configs, `handle_tile_progress/3`, `presign_photo/2`, `tile_errors`
  assign; overlay removed.
- Entry cancel on a completed external upload: best-effort
  `PhotoUpload.delete_file(%{file_path: key})` so retakes/cancels don't
  strand objects.

## Error handling

- **Presign failure** → the `external:` callback returns an error → entry
  error → tile/entry error display.
- **PUT failure** (CORS misconfig, network drop, expired URL) →
  `entry.error()` → `:external_client_failure` → tile shows "Upload failed"
  + Try again; customer modal shows the message on the entry. New
  `upload_error_to_string(:external_client_failure)` clause.
- **Save failure** (DB/validation) → tile error via `tile_errors`; entry is
  cancelled so the tile is immediately retakeable. No success flash — all
  photo feedback lives on the tile/entry.
- **Orphaned objects** (PUT succeeded, never consumed, cancel-delete
  failed): accepted. Rare, ~400 KB each, invisible to users (no DB row), no
  auth risk (private objects). Revisit with a Spaces lifecycle rule only if
  observed.
- **Missing object at save time**: not guarded — a done entry implies a
  completed PUT.

## Security

- Object keys are server-generated; the client never chooses the
  destination.
- Presigned URLs expire in 5 minutes and are single-purpose (PUT, one key,
  pinned Content-Type).
- Accept list unchanged (`.jpg .jpeg .png .webp`). The 10 MB cap is enforced
  client-side by LiveView (`max_file_size`) but — unlike POST policies —
  presigned PUT cannot enforce a size limit server-side, so a hostile client
  with a valid session could PUT a larger object. Accepted as part of the
  presign-constraints-only decision: uploads require an authenticated
  owner/tech session, and retention cleanup bounds the exposure.
- Reads remain auth-gated: `PhotoController` (local) / presigned GET
  (Spaces) behind owner / assigned-tech / admin checks. Unchanged.

## Testing

- **Unit (`PhotoUploadTest`):** presign URL contains bucket, key, signature,
  5-minute expiry, and signs the `content-type` header; `object_key/3`
  shape; `save_external_file/5` creates the row with `file_path = key`,
  replaces an existing slot for tech before/after, enqueues the AI worker
  for customer `:problem_area` photos and not for tech photos, honors
  idempotency keys, rejects disallowed extensions.
- **Tile flow (`ChecklistLiveTest`, channel path):** replaces the overlay
  describe block. Each area tile renders its own file input with
  `capture="environment"`; uploading to `before_front` shows a progress bar
  in that tile; completion auto-saves (Photo row with `car_part: :front`,
  `photo_type: :before`) with no Save button and no flash; two areas
  uploading concurrently each show their own progress; an upload error
  renders on the tile with a Try again control; a save failure surfaces in
  `tile_errors` on the tile.
- **Customer entry errors (`AppointmentsPhotoUploadTest`):** a failed entry
  shows its error on the preview card.
- **Regression:** the rest of the suite runs on the `:local` channel path —
  proves the conditional leaves dev behavior untouched.
- **Not automated:** the JS uploader and real CORS behavior (no JS test
  runner). Covered by the staging checklist below.

## Deploy checklist

1. Set CORS on the Space (DO control panel or `s3cmd`/`aws s3api` against
   the Spaces endpoint): allowed origin = the app's production origin,
   methods = `PUT`, allowed headers = `content-type`, max age 3600.
2. Deploy. No new env vars.
3. Verify on staging/prod from a real phone: shoot two checklist areas
   back-to-back and confirm both tiles show progress simultaneously, both
   photos land in the Space with Photo rows, and both render back; upload a
   customer problem-area photo and confirm AI tags arrive.
4. Rollback = revert the deploy; the channel path remains in the codebase.

## Out of scope

- Async byte verification of uploaded objects (decided against).
- Spaces lifecycle rules for orphan sweeping (revisit if orphans observed).
- Multipart uploads (photos are far below the 5 GB single-PUT limit).
- Auto-advance "next area" prompts (tiles make capture order free-form).
- Any change to photo display, AI analysis, or retention cleanup.
