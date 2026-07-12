# Tech Job Brief UX Design

Date: 2026-07-12
Status: Approved for planning

## Goal

Turn `/tech/appointments/:id` into the technician's single-job command screen.

The previous slice made `/tech` choose the next job and point the technician at the job brief. This slice makes that destination useful at a glance: the tech should understand the customer, vehicle, address, notes, problem photos, and one next action without scanning the full dashboard or checklist.

## Current State

`MobileCarWashWeb.Tech.JobLive` already exists and supports the core job transitions:

- Assigned technicians and admins can open `/tech/appointments/:id`.
- Other technicians are denied, including same-name technicians with different linked accounts.
- Confirmed jobs can transition to `:en_route` with `Head out`.
- En-route jobs can transition to `:on_site` with `Arrived`.
- On-site jobs can start a checklist and navigate to `/tech/checklist/:id`.
- Jobs with an existing checklist link to that checklist.

The page is functionally correct but too thin for field use. It renders one large card with basic service-stop details and an action section. It does not surface customer problem photos, does not make the next action the visual center of the page, and does not group prep information in the way a technician naturally checks it before leaving or starting work.

Existing photo infrastructure already supports this slice:

- `MobileCarWash.Operations.Photo` has `photo_type: :problem_area`.
- Customer problem-area uploads happen elsewhere and use `uploaded_by: :customer`.
- Secure display URLs are prepared with `MobileCarWash.Operations.PhotoUpload.apply_url/1`.
- `ChecklistLive` already loads problem photos for the same appointment.

## User Stories

- As a technician viewing a confirmed job, I can see one clear "Head out" action plus enough job context to leave confidently.
- As a technician en route, I can mark myself arrived without hunting through lower sections.
- As a technician on site, I can start the wash from the first screen.
- As a technician with an active checklist, I can continue the checklist from the first screen.
- As a technician, I can inspect customer problem-area photos before starting the wash.
- As a technician, I can still see customer, vehicle, address, service, appointment notes, and customer-uploaded captions when present.
- As a technician on a job with no problem photos or no notes, I see calm empty states rather than missing sections.
- As an admin, I can still view any job brief for support without being treated as the assigned technician.

## Recommended Approach

Use a "Job Command Brief" layout.

Keep the existing route and transition behavior, but reorganize the page around three regions:

1. Command header
   - Back link to `/tech`.
   - Status badge.
   - Customer name.
   - Service name and scheduled time.
   - A compact address summary.
   - One primary next-action control.
   - Short next-step copy derived from appointment status and checklist progress.

2. Prep checklist
   - Compact cards for service, vehicle, address, customer contact, and appointment notes.
   - Address card links to Apple Maps using the existing `maps_url/1` behavior.
   - Missing notes render "No appointment notes" instead of hiding context.
   - Missing optional fields degrade to existing fallback labels.

3. Problem photos
   - Display customer-uploaded `:problem_area` photos for the appointment.
   - Each photo shows its image, caption when present, and car part when present.
   - Use secure URLs prepared during load, not in the render loop.
   - If there are no problem photos, show a short empty state: "No customer problem photos".
   - Do not add photo upload, delete, editing, lightbox, or AI tagging controls in this slice.

The page should feel operational and dense, not like a marketing card. The first mobile viewport should answer "Where am I going, who is this for, and what do I do next?"

## Next Action Rules

The job brief uses the same state vocabulary as the dashboard:

- `:confirmed` with no checklist: `Head out`.
- `:en_route` with no checklist: `Arrived`.
- `:on_site` with no checklist: `Start wash`.
- Any appointment with `progress.checklist_id`: link to `/tech/checklist/:id`.
- `:pending`, `:completed`, and `:cancelled` with no checklist: show a non-clickable waiting/review state.
- Unknown statuses: show safe review copy and no state-changing action.

The primary action should appear once in the command header. The lower action/prep section can show supporting context, but it should not duplicate a different primary control.

## Data And Architecture

Modify `MobileCarWashWeb.Tech.JobLive` only, unless tests need helper updates.

Add these private helpers in `Tech.JobLive`:

- `load_problem_photos/1`
- `problem_photo_label/1`
- `photo_car_part_label/1`
- `job_command/2`
- `customer_contact_label/1`
- `notes_text/1`

Extend the existing `load_job/2` result to include `problem_photos`, loaded with:

```elixir
Photo
|> Ash.Query.filter(appointment_id == ^appointment.id and photo_type == :problem_area and is_nil(deleted_at))
|> Ash.Query.sort(inserted_at: :asc)
|> Ash.read!(authorize?: false)
|> Enum.map(&PhotoUpload.apply_url/1)
```

Import or alias `MobileCarWash.Operations.{Photo, PhotoUpload}` in `Tech.JobLive`.

Do not:

- Add migrations.
- Add Ash actions.
- Change `PhotoUpload`.
- Change customer upload behavior.
- Change checklist internals.
- Change appointment transition rules.
- Introduce a shared lightbox component; that remains a future photo-flow slice.

## Error Handling

- Existing access denial behavior remains: forbidden/not-found jobs redirect to `/tech` with a flash.
- Transition failures keep the existing flash errors.
- Photo loading should not crash the page for jobs that have no photos.
- Missing captions, car parts, notes, vehicle size, address coordinates, or phone values should render fallbacks.
- Problem photos use `PhotoUpload.apply_url/1` at load time so local and S3 storage both work with the current authorization model.

## Testing

Extend `test/mobile_car_wash_web/live/tech/job_live_test.exs`.

Coverage should include:

- Confirmed job renders the command header and exactly one `Head out` primary action.
- En-route job renders `Arrived` as the primary action.
- On-site job renders `Start wash` as the primary action.
- In-progress job with a checklist renders a primary `Continue checklist` link.
- Pending/completed/cancelled jobs render a non-clickable review or waiting state.
- Customer problem-area photos render with image URL, caption, and car-part label.
- No problem photos renders the empty problem-photo state.
- Internal authorization tests continue to pass for reassignment and other-technician denial.
- Existing transition tests continue to pass.

Focused verification:

```bash
mix test test/mobile_car_wash_web/live/tech/job_live_test.exs
```

Adjacent verification:

```bash
mix test test/mobile_car_wash_web/live/tech/tech_dashboard_live_test.exs test/mobile_car_wash_web/live/checklist_live_test.exs
```

Full verification before merge:

```bash
mix precommit
```

## Acceptance Criteria

- `/tech/appointments/:id` opens as a useful single-job brief, not merely a thin detail card.
- The first viewport shows one primary next action for actionable states.
- Customer problem-area photos are visible to the assigned technician and admins.
- Missing notes and missing photos have readable empty states.
- Existing authorization and job transition behavior remains intact.
- The slice does not change the data model, upload flow, or checklist behavior.
