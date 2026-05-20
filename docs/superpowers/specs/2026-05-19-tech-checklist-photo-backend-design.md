# Design — iOS Technician Checklist & Photo Capture Backend (Slice 1)

**Date:** 2026-05-19
**Status:** Approved (brainstorming phase)
**Author:** Claude (Opus 4.7 1M)
**Context:** Slice 1 of the iOS technician revamp. The iOS app at `/Volumes/mac_external/sdgku/DrivewayDetailCo` currently has a placeholder technician surface; bringing it to web parity requires five backend additions. This design covers the **two most-used flows** (checklist execution + photo capture) plus the realtime channel that supports them.

---

## 1. Context

The iOS app's `Features/Tech/` module is a stub: it lists today's appointments and shows a status badge, but it cannot start a wash, drive a checklist, capture photos, or receive live updates. The Phoenix backend at `/Volumes/mac_external/Development/Business/MobileCarWash` has the technician REST surface for state transitions (`/api/v1/tech/appointments/:id/depart|arrive|start|complete`) but does **not** yet expose:

1. Checklist fetch + per-step transitions
2. Photo upload for native (bearer-auth) clients
3. Phoenix Channels for any client (LiveView-only PubSub today)
4. Earnings endpoint
5. Completed-history endpoint

This spec covers items **1, 2, and the appointment-scoped channel from item 3** — the minimum backend work required to unblock the iOS Checklist and Photo Capture screens. Items 4 and 5, and broader channel coverage (TechChannel, CustomerChannel, CatalogChannel), are deferred to Slice 2.

The full Slice 1 design — both iOS screens and the backend contracts derived from them — was brainstormed with screen mockups in the visual companion. The locked-in iOS layouts are recorded in this doc so the backend shape stays anchored to the consuming UI.

---

## 2. Scope

**In scope (Slice 1):**

- `GET /api/v1/checklists/:id` — full checklist state for one in-progress wash
- `POST /api/v1/checklists/:id/items/:item_id/start` — record a step start
- `POST /api/v1/checklists/:id/items/:item_id/complete` — record a step completion
- `POST /api/v1/appointments/:id/photos` — multipart upload, idempotent
- `DELETE /api/v1/appointments/:id/photos/:photo_id` — re-take support (also handled implicitly by re-POST with new idempotency_key)
- Signed-URL photo serving for iOS (presigned S3 in prod, JWT-signed local URL in dev)
- `MobileCarWashWeb.UserSocket` + `AppointmentChannel`
- Backend change: add `car_part` to `AppointmentTracker.broadcast_photo/2`

**Out of scope (Slice 2+):**

- `TechChannel`, `CustomerChannel`, `CatalogChannel`
- Earnings endpoint
- Completed-history endpoint
- Step notes editing (the model field exists; iOS just doesn't surface it in V1)
- Customer-side photo viewing changes (existing session-auth `PhotoController` stays unchanged)
- Outgoing channel events (`tech:depart` etc. via channel) — REST stays authoritative

---

## 3. iOS screen designs (the anchor)

These are the mockups the backend contracts are derived from. Files persisted under `.superpowers/brainstorm/82386-1779236640/content/`.

### 3.1 Checklist screen — Layout C: split (active hero + mini list)

**Top region — Active step card:**
- Sticky timer card with green/yellow/red border (45s remaining → yellow, over → red)
- Active step number ("Active — Step 3 of 8"), step title, large timer value
- "Mark complete" primary button

**Mid region — Mini list of all steps:**
- Compact row per step: number bubble (✓ done, locked grey, active blue), title, estimated time
- Past steps dimmed; future steps locked-state styling

**Bottom region — Persistent photo status pill:**
- "Before 6/6" and "After 2/6" badges, always visible

**Header:**
- Vehicle + scheduled time ("Toyota Camry — 9:30 AM")
- Sub: "Step N of M · X% complete" with progress bar

### 3.2 Photo Capture screen — Layout A: grid (random access)

**Top:**
- Segmented toggle: Before / After (active type)
- Upload queue bar: "All uploads synced" / "N uploading…" / "N failed — retry"

**Body — 2×3 grid of 6 area cards:**
- Card per car part (front, rear, driver_side, passenger_side, interior, wheels)
- Each card shows: area name, thumbnail (or empty placeholder), upload status (✓ Uploaded / uploading / failed)
- Tap any card → camera → upload (queues if offline)
- Tap a filled card → re-take (replaces existing photo for that slot)

### 3.3 Data needs that drive the contracts

| Screen element | Backend field |
|---|---|
| Checklist header (customer name, vehicle, scheduled_at) | `data.appointment.{customer_name, vehicle, scheduled_at, service_name}` |
| Active step timer color | client-computed from `items[i].started_at` + `items[i].estimated_seconds` + clock |
| Mini list step status | `items[i].{step_number, title, completed, estimated_seconds}` |
| Photo status pill | `data.photo_summary.{before, after}.{done, total}` |
| Photo grid card status | photo records keyed by `(car_part, photo_type)`, with `url` / `uploaded_at` / upload-queue state (iOS-local) |
| Live updates while screen is open | `appointment:<id>` channel events |

---

## 4. Backend contracts

### 4.1 Checklist endpoints

```
GET    /api/v1/checklists/:id
POST   /api/v1/checklists/:id/items/:item_id/start
POST   /api/v1/checklists/:id/items/:item_id/complete
```

All three live in a new `MobileCarWashWeb.Api.V1.ChecklistsController`. Auth pipeline: `:api` + `MobileCarWashWeb.Plugs.RequireTechAuth` (the same plug guarding `/tech/*`).

**`GET /checklists/:id` response (200):**

```json
{
  "data": {
    "id": "uuid",
    "appointment_id": "uuid",
    "appointment": {
      "id": "uuid",
      "customer_name": "Jane Doe",
      "vehicle": { "make": "Toyota", "model": "Camry", "year": 2022 },
      "scheduled_at": "2026-05-19T09:30:00Z",
      "service_name": "Premium Wash"
    },
    "items": [
      {
        "id": "uuid",
        "step_number": 1,
        "title": "Pre-rinse vehicle",
        "estimated_seconds": 120,
        "started_at": "2026-05-19T09:32:00Z",
        "completed": true,
        "actual_seconds": 134,
        "notes": null
      }
    ],
    "photo_summary": {
      "before": { "done": 6, "total": 6 },
      "after":  { "done": 2, "total": 6 }
    }
  }
}
```

Server-side: loads the `AppointmentChecklist` + associated `ChecklistItem` rows + `Appointment` (with `Customer`, `Vehicle`, `ServiceType` preloads) + counts `Photo` rows grouped by `photo_type`. The 6 car-part areas are the canonical list from `@key_areas` in [checklist_live.ex:30-41](MobileCarWash/lib/mobile_car_wash_web/live/checklist_live.ex#L30-L41) — extract that into a module attribute on `Operations.Photo` (`@key_car_parts`) so both the LiveView and the controller use one source of truth. `total` in `photo_summary` is `length(@key_car_parts)` = 6.

**Errors:**
- `404 {"error": "not_found"}` — checklist doesn't exist OR doesn't belong to the signed-in tech (don't leak existence)
- `403 {"error": "forbidden"}` — signed-in customer is not technician/admin (handled by `RequireTechAuth`)

**`POST /items/:item_id/start` and `/complete`:**

Body: `{}`. Returns the updated item object:

```json
{ "data": { "id": "uuid", "step_number": 3, "title": "...", "started_at": "...", "completed": false, "actual_seconds": null, "estimated_seconds": 240, "notes": null } }
```

Server-side: wraps the same Ash actions on `ChecklistItem` that `ChecklistLive` invokes today via `WashOrchestrator`. **No state-machine changes** — just expose existing transitions. Sequential enforcement (only the next incomplete step may be started) lives in the existing `WashStateMachine`; if violated, return:

```
422 {"error": "not_transitionable", "message": "Step must be started in sequence"}
```

After `/complete`, the existing PubSub fanout to `AppointmentTracker.broadcast_step_progress/2` runs as it does for LiveView — meaning the iOS channel client gets the same `step_update` event "for free."

### 4.2 Photo upload + serving

```
POST   /api/v1/appointments/:id/photos
DELETE /api/v1/appointments/:id/photos/:photo_id
```

In a new `MobileCarWashWeb.Api.V1.AppointmentPhotosController`. Pipeline: `:api` + `RequireTechAuth` + a multipart parser carve-out (the existing endpoint's `Plug.Parsers` already accepts `:multipart`).

**`POST` — multipart/form-data fields:**

| Field | Type | Notes |
|---|---|---|
| `photo_type` | string | `"before"` \| `"after"` \| `"problem_area"` |
| `car_part` | string | `"front"` \| `"rear"` \| `"driver_side"` \| `"passenger_side"` \| `"interior"` \| `"wheels"` |
| `idempotency_key` | string (UUID) | Client-generated per capture attempt |
| `file` | binary | JPEG/HEIC, max 10MB; 413 if over |

**Idempotency:** new `idempotency_key` column on `Photo` (nullable for legacy, unique index when not null). The Ash `:upload` action looks up by `idempotency_key`:
- Found → return existing row (200, not 201)
- Not found → check for existing `(appointment_id, photo_type, car_part)`; if found, soft-delete it (sets `deleted_at`); insert new row with the new key.

A nightly Oban job (`Notifications.IdempotencyKeyCleanup`) nulls keys older than 30 days. The unique index treats NULL as not-equal so this doesn't conflict.

**POST response (201 new, 200 idempotent replay):**

```json
{
  "data": {
    "id": "uuid",
    "appointment_id": "uuid",
    "photo_type": "before",
    "car_part": "front",
    "url": "https://...signed.../front.jpg",
    "uploaded_at": "2026-05-19T09:31:12Z",
    "url_expires_at": "2026-05-19T15:31:12Z"
  }
}
```

**Thumbnails:** intentionally **not** generated in Slice 1. `PhotoUpload` has no image-processing dependency today (no `Mogrify`/`Image`/etc.) and the grid view of 12 full-size photos is acceptable on WiFi (iOS can show the local capture immediately while the network loads). Adding a thumbnail pipeline (Mogrify + S3 thumb keys + background worker) is a Slice 2 follow-up.

**`DELETE`** — sets `deleted_at` (soft delete) so historical broadcasts and audit logs remain consistent. Returns `{"ok": true}`. iOS uses this only for explicit "remove photo" UX; normal retake uses POST + new idempotency_key.

**Photo serving (signed URLs):**

The iOS client uses bearer JWT, not session cookies, so the existing `PhotoController` ([photo_controller.ex:39-58](MobileCarWash/lib/mobile_car_wash_web/controllers/photo_controller.ex#L39-L58)) can't serve photos to iOS. Instead, the POST response embeds **signed URLs that work without an Authorization header on the GET**:

- **Prod (S3 backend):** `ExAws.S3.presigned_url` with `expires_in: 21_600` (6 hours). The existing prod flow in `serve_s3_photo/3` already does this for the customer side; reuse the same helper.
- **Dev (local backend):** new helper `MobileCarWash.Operations.PhotoUpload.signed_local_url/2` — produces a URL like `/photos/signed/:appointment_id/:filename?exp=...&sig=...` where `sig` is an HMAC of `(filename, expiry)` using `:mobile_car_wash, :photo_url_secret`. A new tiny endpoint serves these (no auth, signature is the authz).

`url_expires_at` is returned alongside `url` so iOS can pre-emptively re-fetch the checklist before serving stale URLs. On any 403 from a photo GET, iOS treats it as "URL expired" and re-fetches.

### 4.3 AppointmentChannel + UserSocket

**Mount in `lib/mobile_car_wash_web/endpoint.ex`** (alongside the existing `/live` socket):

```elixir
socket "/socket", MobileCarWashWeb.UserSocket,
  websocket: [connect_info: [:peer_data, :user_agent], timeout: 45_000],
  longpoll: false
```

**`MobileCarWashWeb.UserSocket`:**

```elixir
defmodule MobileCarWashWeb.UserSocket do
  use Phoenix.Socket
  channel "appointment:*", MobileCarWashWeb.AppointmentChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    case AshAuthentication.Jwt.verify(token, :mobile_car_wash) do
      {:ok, %{"sub" => subject}, _} ->
        case AshAuthentication.subject_to_user(subject, MobileCarWash.Accounts.Customer) do
          {:ok, customer} -> {:ok, assign(socket, :current_customer, customer)}
          _ -> :error
        end
      _ -> :error
    end
  end

  def connect(_, _, _), do: :error

  @impl true
  def id(%{assigns: %{current_customer: %{id: id}}}), do: "customer_socket:#{id}"
  def id(_), do: nil
end
```

**`MobileCarWashWeb.AppointmentChannel`:**

```elixir
defmodule MobileCarWashWeb.AppointmentChannel do
  use Phoenix.Channel
  alias MobileCarWash.Scheduling.Appointment

  @impl true
  def join("appointment:" <> id, _payload, socket) do
    customer = socket.assigns.current_customer
    with {:ok, appt} <- Ash.get(Appointment, id, authorize?: false),
         true <- owns?(customer, appt) do
      Phoenix.PubSub.subscribe(MobileCarWash.PubSub, "appointment:#{id}")
      {:ok, %{appointment_id: id}, assign(socket, :appointment_id, id)}
    else
      _ -> {:error, %{reason: "unauthorized"}}
    end
  end

  @impl true
  def handle_info({:appointment_update, %{event: event} = payload}, socket) do
    push(socket, Atom.to_string(event), Map.delete(payload, :event))
    {:noreply, socket}
  end

  defp owns?(customer, appt) do
    customer.role == :admin or
      customer.id == appt.customer_id or
      tech_owns?(customer, appt)
  end

  defp tech_owns?(customer, appt) do
    # mirror PhotoController.assigned_technician?/2
  end
end
```

**`authorize?: false` is deliberate.** The channel module owns the authz check explicitly via `owns?/2`. Mirrors the pattern in [photo_controller.ex:67-86](MobileCarWash/lib/mobile_car_wash_web/controllers/photo_controller.ex#L67-L86) and [tech_appointments_controller.ex:113-123](MobileCarWash/lib/mobile_car_wash_web/controllers/api/v1/tech_appointments_controller.ex#L113-L123). Unit tests cover all four cases: owning customer, assigned tech, admin, and rejection.

**Events the channel pushes to the client** (Elixir → JSON event name):

| Source PubSub message | Channel event | Payload |
|---|---|---|
| `{:appointment_update, %{event: :step_update, items: [...], current_step, steps_done, steps_total, eta_minutes}}` | `step_update` | `{items, current_step, steps_done, steps_total, eta_minutes}` |
| `{:appointment_update, %{event: :photo_uploaded, photo_type, car_part, photo: {...}}}` | `photo_uploaded` | `{photo_type, car_part, photo: {id, url, thumb_url, uploaded_at}}` |
| `{:appointment_update, %{event: :started \| :departed \| :arrived \| :completed, status, message}}` | `status_changed` | `{status, event, message}` |
| `{:appointment_update, %{event: :assignment_changed}}` | `assignment_changed` | `{}` |

The channel is a pure consumer of the existing PubSub stream — **the only domain change** is item 7 below.

---

## 5. Resolved gotchas

| # | Concern | Resolution |
|---|---|---|
| 1 | Idempotency key storage | New `idempotency_key` column on `Photo`, unique index (NULL-tolerant). Nightly Oban job nulls keys older than 30 days. |
| 2 | Replace-on-retake broadcast | Fire `photo_uploaded` again with the new photo data. iOS merges by `(car_part, photo_type)`. No second event type. |
| 3 | Signed URL TTL | 6 hours. Response includes `url_expires_at`. iOS treats GET 403 as "re-fetch checklist." |
| 4 | Background upload + JWT rotation | iOS `APIClient.tokenProvider` is already a closure (lazy). No backend change; flag in iOS impl notes. |
| 5 | Channel join auth pattern | `Ash.get(Appointment, id, authorize?: false)` + explicit `owns?/2`. Unit tests for all four cases. |
| 6 | Complete-wash guard | **Add new guard** to `WashOrchestrator.complete_wash/1` ([wash_orchestrator.ex:36-50](MobileCarWash/lib/mobile_car_wash/scheduling/wash_orchestrator.ex#L36-L50)): before transitioning, query `Photo` for the appointment, group by `(car_part, photo_type)`, and refuse if any of the 6 `:after` slots is empty. Returns `{:error, {:photos_incomplete, missing_parts}}` which the existing `/tech/appointments/:id/complete` controller surfaces as `422 {"error": "photos_incomplete", "missing": ["wheels"]}`. iOS shows the error inline and highlights the missing card. (The existing orchestrator only checks state-machine transitions — no photo guard today.) |
| 7 | `broadcast_photo` needs `car_part` | Add `car_part` to `AppointmentTracker.broadcast_photo/2` ([appointment_tracker.ex:140-152](MobileCarWash/lib/mobile_car_wash/scheduling/appointment_tracker.ex#L140-L152)) + thread it through call sites in `ChecklistLive`. Update one existing test. |
| 8 | File size limits | 10MB cap, server returns 413. iOS compresses to JPEG quality 0.8 (~1-3MB typical). |

---

## 6. Implementation sequencing (recommendation for writing-plans)

1. **Migration + `Photo` resource update** — add `idempotency_key`, `deleted_at`, `car_part` constraint (atom enum) if not already.
2. **`AppointmentTracker.broadcast_photo/2` accepts `car_part`** (gotcha 7) — small, unblocks channel work and photo controller.
3. **`AppointmentPhotosController` (POST + DELETE)** — without the channel, photos are still functional over REST.
4. **Signed URL helper** — `PhotoUpload.signed_local_url/2` for dev, reuse prod presigner. Add the signed-URL serving endpoint.
5. **Complete-wash photo guard** (gotcha 6) — add the missing-After-photos check to `WashOrchestrator.complete_wash/1`. Depends on step 3 (photos must be uploadable to test it).
6. **`ChecklistsController` (GET + start + complete)** — wraps existing Ash actions.
7. **`UserSocket` + `AppointmentChannel`** — last so it can be tested end-to-end with the REST flows already working.
8. **Nightly Oban job** for idempotency key cleanup.

Order is roughly "innermost outward" — each step lands a working backend slice on its own, even before iOS catches up.

---

## 7. Testing strategy

- **Unit tests** for `AppointmentTracker.broadcast_photo/2` (existing + new `car_part`)
- **Controller tests** for both new controllers — happy paths + every error path (401, 403, 404, 413, 422)
- **Idempotency test** — same key returns same row; new key on existing slot replaces; cleanup job nulls old keys
- **Channel test** — `Phoenix.ChannelTest` with all four auth scenarios (owning customer, assigned tech, admin, stranger)
- **Channel event test** — broadcast on `appointment:<id>` PubSub topic, assert the right JSON event reaches the client socket
- **Integration test** — full flow: POST start step → broadcast → channel push → POST complete step → broadcast → channel push (in one test process)
- Match the existing project's testing style — `MobileCarWashWeb.ConnCase` for controllers, `MobileCarWashWeb.ChannelCase` for channels (create if it doesn't exist).

---

## 8. Out of scope (deferred to later slices)

- **Slice 2 candidates:** Earnings endpoint, Completed history endpoint, `TechChannel` (for tech-wide `appointment_assigned` and duty `status_changed`), `CatalogChannel`
- **Slice 3 candidates:** `CustomerChannel`, customer-side iOS app, outgoing channel events for transitions
- **Not planned at all:** changes to the existing LiveView photo upload flow, changes to customer-facing `PhotoController`, multi-tenant migration to `driveway_os`

---

## Appendix — iOS mockup files

Persistent design artifacts under `.superpowers/brainstorm/82386-1779236640/content/`:

- `checklist-layout.html` — three Checklist screen options; **Option C** approved
- `photo-capture.html` — three Photo Capture screen options; **Option A** approved
