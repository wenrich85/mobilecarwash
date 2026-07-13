# Task 4: Supply Usage And Earnings In Wrap-Up

## Status

Completed.

## Implementation

- Loaded active inventory supplies into `ChecklistLive` and assigned an empty list for missing checklists.
- Replaced the temporary hidden supply input with three fixed supply rows, including the required stable selectors.
- Parsed submitted rows server-side, rejects incomplete or non-positive quantities inline, and derives `technician_id` exclusively from the appointment.
- Logged each valid row through `MobileCarWash.Inventory.log_usage/1`, refreshed inventory and appointment usage after save, and rendered logged supply names and quantities.
- Added the estimated earnings summary using `MobileCarWash.Operations.TechEarnings.wash_earnings/2`, including its existing flat-rate `$25.00` fallback.
- Corrected the existing `SupplyUsage` action callback by registering it as an Ash `change(after_action(...))`; this ensures the documented inventory decrement runs when `Inventory.log_usage/1` creates usage.
- Preserved the existing photo gates, automatic completion, S3 upload, and lightbox code paths.

## Tests

Passed:

```bash
mix test test/mobile_car_wash_web/live/checklist_live_test.exs --only describe:"wrap-up final notes"
# 5 tests, 0 failures

mix test test/mobile_car_wash_web/live/checklist_live_test.exs
# 23 tests, 0 failures
```

## Notes

The supplied fixture helper and calls used different attribute shapes (map merge with keyword-list calls). The helper normalizes attributes with `Map.new/1` so the acceptance tests exercise the wrap-up behavior rather than failing during fixture creation.

## Review Fix: Atomic Wrap-Up Persistence

The wrap-up save path now uses `MobileCarWash.Repo.transaction/1`. It saves final notes and logs every supply row inside one transaction and calls `Repo.rollback/1` when any write returns an error. The supply usage callback now returns missing-supply errors instead of raising, allowing the LiveView to display `#wrap-up-error` and the outer transaction to roll back notes, usage records, and stock decrements.

The focused regression renders a real supply row, deletes the second selected supply after render, and submits a valid first usage followed by the stale row. It verifies that final notes remain `nil`, no appointment usage is retained, the first supply remains at its original quantity, and the inline error renders.

### Review Fix Tests

```bash
mix test test/mobile_car_wash_web/live/checklist_live_test.exs --only describe:"wrap-up final notes"
# 6 tests, 0 failures

mix test test/mobile_car_wash_web/live/checklist_live_test.exs
# 24 tests, 0 failures
```

## Review Fix: Ash Transaction Notifications

The wrap-up save path now uses `Ash.transact/3` instead of a raw `Repo.transaction/1`, preserving the same all-or-nothing rollback behavior while allowing Ash to collect and send notifications without missed-notification warnings. The supply fixture helper also restores the requested default `attrs \\ %{}` interface.

### Notification Fix Tests

```bash
mix test test/mobile_car_wash_web/live/checklist_live_test.exs --only describe:"wrap-up final notes"
# 6 tests, 0 failures, no Ash missed-notification warnings
```
