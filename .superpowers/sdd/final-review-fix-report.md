# Final Review Fix Report: Active Wash Wrap-Up

## Status

Implemented final-review blockers and verified the requested focused suites.

## Fixes

- Enforced checklist ownership in `ChecklistLive`: admins can access, the assigned technician can access, and other technicians are redirected before the checklist renders. Step, note, skip, and wrap-up writes re-check ownership so stale sessions cannot mutate reassigned work.
- Enforced wrap-up lifecycle on the server. `save_wrap_up` reloads authoritative checklist items and after photos and rejects saves until required steps and after photos are complete.
- Restricted `AppointmentChecklist`'s default `:update` action so `final_notes` is accepted only by `:save_wrap_up`.
- Made wrap-up repeat-safe: saved wrap-ups render read-only and later crafted `save_wrap_up` events are rejected before any usage is logged.
- Preserved submitted final notes, selected supply, quantity, and supply note following validation or logging errors.
- Added result-returning inventory reads and a stable supply-loading message. Inventory read failures no longer use bang reads in the wrap-up mount/refresh path; internal reasons are logged with appointment context.
- Calculated the earnings summary once during mount from the assigned technician and rendered the assign rather than querying from the timer-rendered template.
- Resolved the assigned technician server-side for supply usage and recorded that technician's `van_id` when set. Browser-supplied technician/van ids are never consumed.
- Replaced technician-facing raw `inspect(reason)` output with a stable retry message and structured server logging.
- Restored the completed-without-final-notes command-card precedence for legacy completed checklists that may not have full photo records; those still route to wrap-up rather than back to before-photo capture.

## TDD Evidence

- Initial regression run: `mix test test/mobile_car_wash/operations/appointment_checklist_wrap_up_test.exs test/mobile_car_wash_web/live/checklist_live_test.exs` failed as expected for broad default updates, unrestricted access, premature/repeat wrap-up, missing van attribution, and lost form values.
- Added a stale-assignment step-mutation regression and confirmed it failed before the shared mutation authorization guard was added.
- Final focused run: `37 tests, 0 failures`.

## Ash Snapshot Workflow

Command run:

```bash
mix ash_postgres.generate_migrations --name refresh_appointment_checklist_final_notes_snapshot
```

It generated the required snapshot:

- `priv/resource_snapshots/repo/appointment_checklists/20260713030901.json`

The generated migration repeated the already-committed `final_notes` DDL and also contained unrelated `tech_applications`, `tech_invites`, and `service_types` drift. The duplicate migration and those unrelated generated snapshots were removed. No new migration is retained because `priv/repo/migrations/20260713020708_add_final_notes_to_appointment_checklists.exs` already adds the column.

## Verification

```bash
mix test test/mobile_car_wash/operations/appointment_checklist_wrap_up_test.exs test/mobile_car_wash_web/live/checklist_live_test.exs
# 38 tests, 0 failures

mix test test/mobile_car_wash_web/live/tech/tech_dashboard_live_test.exs test/mobile_car_wash_web/live/tech/job_live_test.exs
# exit 0

mix format --check-formatted lib/mobile_car_wash/operations/appointment_checklist.ex lib/mobile_car_wash_web/live/checklist_live.ex test/mobile_car_wash/operations/appointment_checklist_wrap_up_test.exs test/mobile_car_wash_web/live/checklist_live_test.exs
# exit 0
```

Also passed:

```bash
mix format --check-formatted lib/mobile_car_wash/inventory.ex
git diff --check
```

## Residual Warnings

- The dashboard/job suite logs pre-existing Ash missed-notification warnings from `WashOrchestrator` while creating checklist records.
- The focused wrap-up suite logs the expected structured warning for its intentional stale-supply logging failure regression.
- The Ash codegen command warned about an unrelated non-convertible default and exposed existing unrelated snapshot drift; none of that generated DDL was retained.

## Worktree Note

The pre-existing dirty `.superpowers/sdd/task-1-report.md` was not modified by this review pass and is intentionally excluded from the commit.
