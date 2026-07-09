# Task 1 Report: TechApplication Resource And State Transitions

## Status

DONE_WITH_CONCERNS

## Summary

Implemented the new `MobileCarWash.Operations.TechApplication` Ash resource, registered it in the `Operations` domain, added the `tech_applications` migration, and covered the lifecycle with focused resource tests.

## Files Changed

- Created `lib/mobile_car_wash/operations/tech_application.ex`
- Modified `lib/mobile_car_wash/operations/operations.ex`
- Modified `lib/mobile_car_wash/operations/technician.ex`
- Created `priv/repo/migrations/20260708191137_create_tech_applications.exs`
- Created `test/mobile_car_wash/operations/tech_application_test.exs`

## TDD Notes

1. Added `test/mobile_car_wash/operations/tech_application_test.exs` exactly from the task brief.
2. Ran `mix test test/mobile_car_wash/operations/tech_application_test.exs` and confirmed RED with `MobileCarWash.Operations.TechApplication` undefined.
3. Implemented the migration and resource.
4. Re-ran the focused test until GREEN.

## Verification

### Passing

- `mix test test/mobile_car_wash/operations/tech_application_test.exs`
  - Result: `3 tests, 0 failures`

### Concern / Incomplete Repo-Wide Gate

- `mix precommit`
  - Result: encountered unrelated existing failures/noise outside Task 1
  - Latest run summary: `1358 tests, 1 failure`
  - Latest unrelated failure: `test/mobile_car_wash_web/static_cache_headers_test.exs:9`
  - Also produced substantial pre-existing warning/log noise and sandbox connection churn during the broader suite

## Notable Implementation Detail

- `lib/mobile_car_wash/operations/technician.ex` needed a small compatibility tweak so the acceptance flow can pass through `van_id` during technician creation/update, which is required by the Task 1 brief's `:accept` contract.

## Concerns

1. `mix precommit` still surfaces an unrelated existing failure in `test/mobile_car_wash_web/static_cache_headers_test.exs:9`.
2. The repo-wide run emitted heavy pre-existing Ash notification warnings and DB sandbox disconnect noise that were not introduced by this task.

## Fix After Review

- Closed the public ownership hole by removing public `customer_id` acceptance and making the `customer` relationship required at the Ash resource layer.
- Added explicit lifecycle guards so `:save_draft`, `:submit`, `:mark_reviewed`, `:accept`, and `:not_accept` only run from their allowed statuses.
- Tightened `:mark_reviewed` to accept only `:review_notes`.
- Expanded focused tests to cover ownership enforcement, guarded transitions, `:save_draft`, `:mark_reviewed`, and `:for_customer`.

### Requested Test Command

- Command: `mix test test/mobile_car_wash/operations/tech_application_test.exs`
- Output summary: `8 tests, 0 failures`

### Additional Verification

- Command: `mix precommit`
- Output summary: `1358 tests, 1 failure` with unrelated failure at `test/mobile_car_wash_web/static_cache_headers_test.exs:9`

## Second Fix After Review

- Removed the generated broad `:update` action from `MobileCarWash.Operations.TechApplication` so the explicit workflow actions remain authoritative.
- Added regression coverage proving `Ash.Changeset.for_update(application, :update, %{status: :accepted})` is unavailable and that public update attempts cannot change `customer_id`.

### Requested Test Command

- Command: `mix test test/mobile_car_wash/operations/tech_application_test.exs`
- Output summary: `10 tests, 0 failures`

### Additional Verification

- Command: `mix precommit`
- Output summary: surfaced the same unrelated failure at `test/mobile_car_wash_web/static_cache_headers_test.exs:9` before I stopped the noisy run
