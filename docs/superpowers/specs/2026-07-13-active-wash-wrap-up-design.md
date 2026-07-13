# Active Wash Command Flow And Wrap-Up Design

Date: 2026-07-13
Status: Approved for planning

## Goal

Turn `/tech/checklist/:id` into a guided active-wash command screen and add a real operational wrap-up step.

The technician should always know the next action during a wash: finish before photos, start the next step, complete the active step, take after photos, or wrap up. When the wash is done, the tech should record final notes and supply usage, see the job earnings summary, and move cleanly back to the workday flow.

## Current State

`MobileCarWashWeb.ChecklistLive` already has strong operational foundations:

- Before photos are required before starting checklist steps.
- After photos are required before the wash can complete.
- Photo capture is tile-based, concurrent, camera-direct, and works with local or S3 storage.
- Customer problem photos are visible and open in the shared lightbox.
- Checklist items track start time, completion time, actual seconds, notes, and optional skips.
- Completion currently happens after required steps and after photos are complete.
- A basic completed panel shows time analysis.

The gap is flow and closure. The page exposes many useful controls at once, but the first screen does not consistently answer "what now?" The completed state also does not collect final technician notes, supply usage, or job earnings in one operational wrap-up.

## Recommended Approach

Use a "Guided Command Flow" at the top of the existing checklist page.

Keep the current one-page checklist structure, but add a `Wash Command Card` above the supporting sections. The command card derives a small view model from existing assigns:

- checklist status
- before photo completeness
- current or next checklist item
- required-step completeness
- after photo completeness
- wrap-up save state

The rest of the page remains available below the card:

1. Customer problem photos
2. Before photo grid
3. Active step card
4. All steps list
5. After photo grid
6. Wrap-up panel

This keeps experienced techs from being trapped in a wizard while making the next action obvious for every state.

## Command Card Rules

The command card should show exactly one primary action when action is required.

Priority order:

1. No checklist loaded: show the existing "No active checklist" state.
2. Before photos incomplete: prompt "Finish before photos" and link/scroll to `#before-photo-progress`.
3. Before photos complete and the next incomplete step has not started: show `Start step`.
4. A step is started and not completed: show `Complete step`.
5. Required steps complete and after photos incomplete: prompt "Finish after photos" and link/scroll to `#after-photo-progress`.
6. After photos complete and wrap-up is not saved: show `Wrap up`.
7. Wrap-up saved: show `Back to dashboard`. Do not compute a dedicated next-job link in this slice; the dashboard remains the source of truth for the next job.

When the existing automatic completion logic marks the checklist complete before wrap-up data is saved, the command card must still show `Wrap up`. Completed checklist status alone is not enough to skip wrap-up.

Secondary actions may remain where they already live:

- optional skip
- edit step note
- retake photo
- open photo lightbox

The command card should not introduce alternate state transitions. It should call the same events and helpers that existing controls use.

## Active Wash Layout

The page should feel like an operational tool, not a long report.

Top region:

- Appointment/service summary when available.
- Overall progress: steps done, total steps, percent complete.
- Current gate or action.
- Short supporting copy explaining why that action is next.

Photo regions:

- Before photo grid remains required before steps start.
- After photo grid remains locked until required steps are complete.
- Existing tile upload behavior, S3 behavior, errors, retake controls, and lightbox wiring remain unchanged.

Step regions:

- The active step card becomes more prominent and mirrors the command card state.
- The all-steps list remains visible for context and fallback controls.
- Existing note and skip flows stay in place.

## Real Wrap-Up

Wrap-up becomes a persisted operational step.

Add `final_notes` to `MobileCarWash.Operations.AppointmentChecklist`.

Use existing systems for everything else:

- `MobileCarWash.Inventory.list_supplies/0` for selectable active supplies.
- `MobileCarWash.Inventory.log_usage/1` to create `SupplyUsage` rows and decrement stock.
- `MobileCarWash.Operations.TechEarnings.wash_earnings/2` to show estimated job pay.

Wrap-up UI:

- Shows after photos complete and the checklist is ready to close.
- Contains a final technician note field.
- Contains supply usage rows:
  - supply select
  - quantity used
  - optional note
- Allows submitting with no supplies when none were used.
- Shows time analysis using existing checklist item actual seconds.
- Shows estimated earnings for the appointment.
- Shows completion confirmation and a return-to-dashboard action after save.

Wrap-up save behavior:

- Persist `AppointmentChecklist.final_notes`.
- Log each valid supply row with `appointment_id`, `technician_id`, and `van_id` when available.
- Use inline validation errors for missing supply, invalid quantity, or supply logging failure.
- Do not silently mark wrap-up saved if supply logging fails.
- Preserve current checklist/appointment completion rules; this slice should not loosen photo or step gates.
- A checklist may already be `:completed` because the existing photo/step gates completed it; if `final_notes` is still `nil`, wrap-up remains unsaved and should still be shown.

## Data Model

Add one field:

- `AppointmentChecklist.final_notes :string`

Add one update action or extend an existing explicit action:

- `:save_wrap_up`, accepting `:final_notes`

No new supply tables are needed. `SupplyUsage` already records:

- `supply_id`
- `appointment_id`
- `technician_id`
- `van_id`
- `quantity_used`
- `notes`
- `occurred_at`

No new earnings table is needed. Earnings are calculated from technician pay settings and the completed wash.

## Authorization And Ownership

Keep existing checklist access behavior.

The wrap-up must only be usable by:

- the assigned technician for the appointment
- admins, if they can already access the checklist

Supply usage created from the tech checklist should be tied to the appointment's assigned technician, not a user-provided technician id.

## Error Handling

- If supplies cannot be loaded, render the wrap-up final note and completion state with a clear supply-loading message.
- If one supply row fails validation, keep the entered form values and show an inline error.
- If inventory logging fails after some rows were saved, show an error and re-read existing usage for the appointment so the tech does not double-log blindly.
- If there are no active supplies, show "No supplies to log" and allow final-note-only wrap-up.
- If earnings cannot be calculated because the technician record is missing, hide the earnings amount and show a neutral fallback.

## Testing

Extend `test/mobile_car_wash_web/live/checklist_live_test.exs`.

Focused coverage:

- Command card renders the before-photo gate when before photos are incomplete.
- Command card starts the next step after before photos are complete.
- Command card completes an active step.
- Command card points to after photos after required steps are complete.
- Command card opens wrap-up after after photos are complete.
- Final notes persist to `AppointmentChecklist.final_notes`.
- Supply usage rows are created with appointment and technician ids.
- Supply quantity decrements after wrap-up logging.
- Wrap-up can be submitted with no supplies.
- Invalid supply quantity shows an inline error and does not create usage.
- Earnings summary renders for a flat-rate technician.
- Existing before-photo gate, after-photo gate, notes, skips, upload errors, lightbox attributes, and completed read-only behavior keep passing.

Verification commands:

```bash
mix test test/mobile_car_wash_web/live/checklist_live_test.exs
mix test test/mobile_car_wash_web/live/tech/tech_dashboard_live_test.exs test/mobile_car_wash_web/live/tech/job_live_test.exs
mix precommit
```

## Out Of Scope

- Admin inventory reporting changes.
- New supply catalog management UI.
- Customer-visible wrap-up notes.
- Payment collection or customer receipt changes.
- Push/email notifications for wrap-up.
- Changing the photo upload transport.
- Replacing the checklist with a strict multi-page wizard.

## Acceptance Criteria

- `/tech/checklist/:id` opens with one obvious next action.
- Existing photo and checklist gates remain intact.
- Active wash work can still be done from one page.
- The tech can complete wrap-up with final notes and optional supply usage.
- Supply usage decrements inventory through the existing inventory domain.
- The tech sees a job earnings summary during wrap-up.
- Completed checklist state shows saved wrap-up data and a clear return to `/tech`.
