# Direct-to-Spaces Photo Uploads

**Date:** 2026-07-11
**Status:** Approved
**Branch:** `feature/direct-to-spaces-uploads`

## Problem

In production, every photo crosses the network twice: phone → Phoenix over the
LiveView websocket, then Phoenix → DigitalOcean Spaces via a synchronous
`ExAws` PUT inside the LiveView process (`PhotoUpload.save_to_s3/5`). The
second hop re-reads the whole file into memory and blocks the user's LiveView
process for its duration — taps and events freeze until the PUT returns.

The on-device downscale hook (shipped 2026-07-11) already cut transfer sizes
to a few hundred KB. This slice removes the second hop entirely: the phone
uploads straight to Spaces with a presigned URL, and the server only ever
handles metadata.

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
- **Scope: both surfaces at once** — the customer problem-area uploader
  (`AppointmentsLive`) and the tech checklist overlay (`ChecklistLive`) —
  via shared plumbing. Tech-on-cellular is where the win is biggest.
- **Dev and tests keep the channel path.** External uploads activate only
  when `photo_storage == :s3`. With `:local`, `allow_upload` gets no
  `external:` option and behavior is byte-for-byte today's.

## Data flow (production)

1. User picks a photo. The `ImageDownscale` hook shrinks it on-device.
2. LiveView preflights the entry and invokes our `external:` callback
   (in-process, local crypto — fast):
   - generates the object key `appointments/<appointment_id>/<photo_type>_<uuid><ext>`
     (same naming scheme as today, so display/cleanup/AI are unaffected),
   - returns `%{uploader: "S3PUT", url: presigned_put_url, headers: %{"content-type" => type}, key: key}`.
3. The `S3PUT` JS uploader XHR-PUTs the file directly to Spaces, reporting
   progress into the entry — the existing progress bars work unchanged.
4. Consume time (customer: on-done progress callback; tech: Save button):
   `PhotoUpload.save_external_file/5` creates the Photo row with
   `file_path = key`. No bytes touch the server.
5. Downstream is untouched: `url_for/1` presigned GETs, the AI analyzer
   worker (fetches via `url_for`), PubSub broadcasts, retention cleanup.

## Components

### `MobileCarWash.Operations.PhotoUpload` (extend)

- `object_key(appointment_id, photo_type, original_filename)` — extracted so
  both paths name objects identically.
- `presign_put(key, content_type)` — `ExAws.S3.presigned_url(config, :put, bucket, key, ...)`
  with `expires_in: 300` and the Content-Type signed. Returns `{:ok, url} | {:error, reason}`.
- `external_entry_meta(entry, appointment_id, photo_type)` — builds the map
  the `external:` callback returns (uploader name, url, headers, key).
- `save_external_file(appointment_id, key, original_filename, photo_type, opts)` —
  creates the Photo record. Reuses idempotency, slot soft-delete
  (`soft_delete_existing_slot/3`), and AI enqueue by extracting today's
  record-creation block from `do_save_file_validated/6` into a shared private
  helper. Skips magic-byte validation (bytes never present) but keeps the
  extension allow-list check on `original_filename`.
- `external_uploads?/0` — `storage_backend() == :s3`. The single switch both
  LiveViews consult.

### `assets/js/uploaders/s3_put.js` (new)

LiveView external uploader: XHR PUT to `entry.meta.url` with
`entry.meta.headers`, wiring `xhr.upload.onprogress` to
`entry.progress(...)` and errors to `entry.error()`. Registered on the
LiveSocket as `uploaders: {S3PUT}`.

### `AppointmentsLive` and `ChecklistLive` (modify)

- When `PhotoUpload.external_uploads?()`, pass
  `external: &presign_photo/2` to their `allow_upload` configs (both customer
  configs; the one tech config). The callback authorizes implicitly — these
  LiveViews already verified ownership/assignment at mount, and the server
  picks the key.
- Consume callbacks pattern-match both meta shapes:
  `%{path: path}` → existing `save_file/5`; `%{key: key}` → `save_external_file/5`.
- Tech overlay `cancel_upload` / entry cancel: for an external entry that
  already finished its PUT, best-effort `PhotoUpload.delete_file(%{file_path: key})`
  so abandoning the overlay doesn't strand objects.

## Error handling

- **Presign failure** → the `external:` callback returns
  `{:error, reason, socket}` → entry error → rendered by the existing
  per-entry error display; add an `upload_error_to_string(:external_client_failure)`
  clause ("Upload failed — check your connection and try again.").
- **PUT failure** (CORS misconfig, network drop, expired URL) → `entry.error()`
  → same display. The entry can be removed and retried without leaving the
  overlay/modal.
- **Orphaned objects** (PUT succeeded, never consumed, cancel-delete failed):
  accepted. They are rare, ~400 KB each, invisible to users (no DB row), and
  carry no auth risk (private objects). Revisit with a Spaces lifecycle rule
  only if observed in practice.
- **Missing object at save time**: not guarded — a done entry implies a
  completed PUT.

## Security

- Object keys are server-generated; the client never chooses the destination.
- Presigned URLs expire in 5 minutes and are single-purpose (PUT, one key,
  pinned Content-Type).
- Accept list unchanged (`.jpg .jpeg .png .webp`). The 10 MB cap is enforced
  client-side by LiveView (`max_file_size`) but — unlike POST policies —
  presigned PUT cannot enforce a size limit server-side, so a hostile client
  with a valid session could PUT a larger object. Accepted as part of the
  presign-constraints-only decision: uploads require an authenticated
  owner/tech session, and retention cleanup bounds the exposure.
- Reads remain auth-gated: `PhotoController` (local) / presigned GET (Spaces)
  behind owner / assigned-tech / admin checks. Unchanged.

## Testing

- **Unit (`PhotoUploadTest`):** presign URL contains bucket, key, signature,
  5-minute expiry, and signs the `content-type` header; `object_key/3` shape;
  `save_external_file/5` creates the row with `file_path = key`, replaces an
  existing slot for tech before/after, enqueues the AI worker for
  customer `:problem_area` photos and not for tech photos, honors idempotency
  keys, rejects disallowed extensions.
- **Regression:** entire existing LiveView suite runs on the `:local`
  channel path — proves the conditional leaves dev behavior untouched.
- **Not automated:** the JS uploader (no JS test runner in the project) and
  real CORS behavior. Covered by the staging checklist below.

## Deploy checklist

1. Set CORS on the Space (DO control panel or `s3cmd`/`aws s3api` against the
   Spaces endpoint): allowed origin = the app's production origin, methods =
   `PUT`, allowed headers = `content-type`, max age 3600.
2. Deploy. No new env vars.
3. Verify on staging/prod from a real phone: upload a problem-area photo and
   a checklist photo; confirm the object lands in the Space, the Photo row
   exists, the image renders back, and AI tags arrive on the customer photo.
4. Rollback = revert the deploy; the channel path remains in the codebase.

## Out of scope

- Async byte verification of uploaded objects (decided against).
- Spaces lifecycle rules for orphan sweeping (revisit if orphans observed).
- Multipart uploads (photos are far below the 5 GB single-PUT limit).
- Any change to photo display, AI analysis, or retention cleanup.
