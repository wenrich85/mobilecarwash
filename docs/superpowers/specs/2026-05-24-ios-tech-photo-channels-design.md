# Design - iOS Technician Photo Channels

**Date:** 2026-05-24
**Status:** Approved for implementation
**Scope:** Phoenix API + DrivewayDetailCo iOS app

## Goal

Give technicians one clear place to capture and review job photos during an appointment. The experience should organize photos into channels that match the job lifecycle:

- **Before** - required six-part condition photos before checklist work starts.
- **During** - optional work-in-progress photos attached to the current checklist step when possible.
- **After** - required six-part completion photos before the job can be completed.
- **Customer Notes** - read-only customer problem-area photos already attached to the appointment.

The implementation should reuse the existing Phoenix upload API, photo storage, signed URLs, idempotency keys, offline upload queue, and appointment realtime updates. Tests should stay focused on behavior that can regress.

## Existing Context

Backend already has:

- `POST /api/v1/appointments/:id/photos` for technician multipart uploads.
- `DELETE /api/v1/appointments/:id/photos/:photo_id` for soft deletion.
- `Photo` types: `:before`, `:after`, `:problem_area`, `:step_completion`.
- `Photo.key_car_parts/0` returning the six required slots: front, rear, driver side, passenger side, interior, wheels.
- Photo replacement by `(appointment_id, photo_type, car_part)` and idempotent replay by `idempotency_key`.
- `AppointmentTracker.broadcast_photo/4`, which sends `photo_uploaded` events to appointment subscribers.
- Checklist responses with `photo_summary.before` and `photo_summary.after`.

iOS already has:

- `PhotoCaptureView` and `PhotoCaptureViewModel`.
- `PhotoType`, `CarPart`, `AppointmentPhoto`, and `PhotoUploadRequest`.
- Multipart upload support in `APIClient`.
- `PersistentQueue<PendingPhoto>` for offline upload replay.

The missing piece is product wiring: the technician does not yet have a complete photo hub connected to job detail/checklist, and the channels are not explicit in the UI.

## UX Design

### Job Detail Entry Point

`TechAppointmentDetailView` gets a `Photos` card below the progress strip. It shows compact channel status:

- `Before 3/6`
- `During 0`
- `After 0/6`
- `Customer 1`

The card opens the photo hub. It is visible for `on_site`, `in_progress`, and `completed` appointments. It is hidden for `confirmed` and `en_route` appointments.

### Photo Hub

Replace the current simple before/after picker with channel tabs:

- `Before`
- `During`
- `After`
- `Customer`

`Before` and `After` render the existing six-slot grid. Each tile shows a camera icon if empty, a check state if uploaded, and a short upload state if queued or uploading. Tapping a tile starts a capture/import action and uploads to the current appointment.

`During` renders a lighter feed-style view. It offers a single capture/import action and stores photos as `step_completion`. If the active checklist step is available, include `checklist_item_id`; otherwise upload the photo without a step link. Backend support for `step_completion` is part of this implementation, so the channel should be usable rather than disabled.

`Customer` is read-only. It lists `problem_area` photos uploaded by the customer, with caption/AI description when available. No delete or replace controls for technicians.

### Checklist Integration

Checklist header keeps the before/after summary pill. Add a `Photos` button from the checklist screen that opens the same photo hub for the appointment.

Checklist start and completion rules remain:

- Starting checklist work requires all six `Before` photos.
- Completing the appointment requires all six `After` photos.

If a required channel is incomplete, the tech sees the missing slots by name and can jump directly into that channel.

## API Design

### Photo Listing

The iOS hub needs the actual photo rows, not just summary counts. Add a read endpoint:

`GET /api/v1/appointments/:id/photos`

Response:

```json
{
  "data": [
    {
      "id": "uuid",
      "appointment_id": "uuid",
      "photo_type": "before",
      "car_part": "front",
      "url": "https://signed-url",
      "uploaded_at": "2026-05-24T14:30:00Z",
      "url_expires_at": "2026-05-24T20:30:00Z",
      "caption": null,
      "uploaded_by": "technician",
      "checklist_item_id": null
    }
  ]
}
```

Authorization matches the existing photo create/delete controller: assigned technician or admin only.

### Photo Upload

Keep the existing upload endpoint:

`POST /api/v1/appointments/:id/photos`

Extend it to accept:

- `photo_type=step_completion`
- optional `checklist_item_id`

For `before` and `after`, `car_part` remains required and restricted to the six required slots. For `step_completion`, `car_part` may be omitted. For `problem_area`, technician upload remains disallowed in this flow.

### Realtime

Keep using appointment channels. `photo_uploaded` payload should include enough data for both tech and customer screens to update without a full refetch:

```json
{
  "appointment_id": "uuid",
  "status": "in_progress",
  "photo_type": "before",
  "car_part": "front",
  "photo": { "...": "same shape as photo JSON" }
}
```

The tech dashboard already treats `photo_uploaded` as a refresh event. The photo hub can update local state optimistically after upload and optionally reconcile on channel events.

## iOS Data Model

Add a channel enum separate from backend `PhotoType`:

- `before` maps to `PhotoType.before`
- `during` maps to `PhotoType.stepCompletion`
- `after` maps to `PhotoType.after`
- `customer` maps to `PhotoType.problemArea` and is read-only

Add `stepCompletion` to `PhotoType`.

Add API support for:

- `photos(appointmentId:) async throws -> [AppointmentPhoto]`
- optional `checklistItemId` on `PhotoUploadRequest`

The view model owns:

- selected channel
- photos grouped by channel and car part
- queued uploads by idempotency key
- missing required before/after slots
- upload status message

## Error Handling

Use existing API error presentation patterns:

- 413 from backend -> "Photo is too large."
- invalid type or slot -> "That photo slot is not available."
- network failure -> queue upload and show "Will upload when connected."
- expired signed URL -> refetch photo list.

Queued uploads should not block the tech from continuing unless the required slot has not successfully reached the server. A queued before/after photo still counts as incomplete for the start/complete gates.

## Testing

Backend:

- Controller test for `GET /appointments/:id/photos` returning only active photos for an assigned tech.
- Controller test that `step_completion` upload is accepted with optional `checklist_item_id`.
- Keep existing before/after upload tests.

iOS:

- `PhotoCaptureViewModel` test groups loaded photos by channel and slot.
- Existing offline replay test remains.
- Add one test that before/after missing slots are computed correctly.

No broad UI snapshot tests are required for this pass.

## Rollout

1. Backend photo listing and `step_completion` upload support.
2. iOS model/API updates.
3. Photo hub UI and navigation from tech detail/checklist.
4. Gate messages that deep-link into the missing required channel.
5. Focused tests and simulator verification with the existing seeded in-progress appointment.
