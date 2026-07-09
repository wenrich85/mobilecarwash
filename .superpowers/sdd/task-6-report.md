# Task 6 Report: Focus Active Wash UX

## Summary

Implemented the checklist LiveView restructure for the active wash flow so the in-wash screen now exposes stable DOM regions for focused technician work:

- `#active-wash`
- `#before-photo-progress`
- `#active-step-card`
- `#all-steps-list`
- `#after-photo-progress`
- `#wrap-up-panel` when completed

Added a new `active_step_title/1` helper backed by the existing `current_progress_item/1` behavior and kept the existing checklist event handlers and state transitions intact.

## Changed Files

- `lib/mobile_car_wash_web/live/checklist_live.ex`
- `test/mobile_car_wash_web/live/checklist_live_test.exs`

## What Changed

### `lib/mobile_car_wash_web/live/checklist_live.ex`

- Reorganized the render tree into stable, named regions for the active wash experience.
- Added a focused active-step card above the full checklist item list.
- Preserved:
  - before-photo capture/retake flow
  - step list controls and timers
  - notes editing
  - skip flow
  - after-photo flow
  - upload overlay
  - completion summary behavior
- Added helper functions:
  - `active_step_title/1`
  - `active_step_supporting_copy/2`
  - `done_label/2`

### `test/mobile_car_wash_web/live/checklist_live_test.exs`

- Replaced placeholder/compile-only tests with mounted LiveView tests.
- Added real fixture setup for technician, customer, appointment, procedure, checklist, and items.
- Added coverage for:
  - in-progress checklist renders the required stable regions
  - completed checklist renders the required stable regions plus `#wrap-up-panel`

## Tests Run

### Focused commands requested by the brief

1. `mix format lib/mobile_car_wash_web/live/checklist_live.ex test/mobile_car_wash_web/live/checklist_live_test.exs`
   - Result: passed

2. `mix test test/mobile_car_wash_web/live/checklist_live_test.exs`
   - Result: passed
   - Output summary: `2 tests, 0 failures`

### Additional verification

3. `mix precommit`
   - Result: not clean, due pre-existing unrelated suite issues already called out in the brief
   - Reproduced unrelated failure:
     - `test/mobile_car_wash_web/static_cache_headers_test.exs`
     - `cache-control headers on static assets hashed /assets/* files are served immutable for 1 year`
     - assertion failed because response status was `404` instead of `200`
   - Also emitted numerous unrelated warnings/noise from other tests and background processes
   - I stopped the run after confirming the unrelated failure signal so this task stayed scoped

## Concerns

- `mix precommit` is still not green because of unrelated existing suite failures/noise, including the known static-cache header failure.
- The render refactor is intentionally large within `ChecklistLive`, but event handlers and checklist workflow logic were left unchanged.

## Fix Notes

### Changed Files

- `lib/mobile_car_wash_web/live/checklist_live.ex`
- `test/mobile_car_wash_web/live/checklist_live_test.exs`

### Tests Run

- `mix test test/mobile_car_wash_web/live/checklist_live_test.exs` - passed (`2 tests, 0 failures`)
- `mix format lib/mobile_car_wash_web/live/checklist_live.ex test/mobile_car_wash_web/live/checklist_live_test.exs` - passed
- `mix precommit` - started, but the alias remained noisy with unrelated suite output and was not used as the success signal for this task

### Concerns

- `mix precommit` still has unrelated noise/failures outside this checklist slice.
- Completed checklists now keep `#before-photo-progress` stable while suppressing active `show_upload` controls and showing a read-only placeholder when a before photo is missing.
