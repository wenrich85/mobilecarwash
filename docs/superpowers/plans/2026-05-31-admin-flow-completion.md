# Admin Flow Completion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish the approved Admin Command Center implementation across Phoenix web and DrivewayDetailCo iOS by completing full verification, simulator smoke coverage, real backend mutation checks, remaining polish, and merge readiness.

**Architecture:** Treat the current implementation as the baseline: Phoenix owns admin dispatch/customer data and mutations, while iOS consumes those APIs with native SwiftUI command surfaces. This plan avoids new backend endpoints unless a verified smoke failure proves an existing endpoint cannot support the intended flow. The final output is a tested, pushed iOS branch and a clean Phoenix `main` except for the explicitly preserved unrelated `AGENTS.md`.

**Tech Stack:** Phoenix 1.8, Elixir, ExUnit, Ash, SwiftUI, Observation, Swift Testing, Xcode/iOS Simulator, Git.

---

## Current Baseline

Phoenix repo:

- Path: `/Volumes/mac_external/Development/Business/MobileCarWash`
- Branch: `main`
- Known preserved dirty file: `AGENTS.md`
- Latest relevant commit: `527896f fix: normalize admin dispatch timestamp`
- Last known `mix precommit`: passed after `527896f`

iOS repo:

- Path: `/Volumes/mac_external/sdgku/DrivewayDetailCo/.worktrees/ios-admin-dispatch-command-center`
- Branch: `codex/ios-admin-dispatch-command-center`
- Latest relevant commit: `180b596 fix: clarify dispatch date action`
- Last focused tests passed:
  - `DrivewayDetailCoTests/ModelDecodingTests`
  - `DrivewayDetailCoTests/AdminCustomersViewModelTests`
  - `DrivewayDetailCoTests/AdminDispatchViewModelTests`

Simulator:

- Device: `iPhone 17 Pro`
- UDID: `0D565491-438B-4641-99C4-56C7C0CB781A`
- Bundle id: `com.wendellrichards.DrivewayDetailCo`
- Use `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`

---

## File Structure

Phoenix files to verify only unless failures require fixes:

- `lib/mobile_car_wash_web/controllers/api/v1/admin_dispatch_controller.ex`
  - Owns iOS admin dispatch JSON payload, assign, unassign, confirm.
- `test/mobile_car_wash_web/controllers/api/v1/admin_dispatch_controller_test.exs`
  - Focused API coverage for auth, payload, mutations, timestamp format.
- `lib/mobile_car_wash_web/live/admin/dispatch_live.ex`
  - Web admin dispatch LiveView.
- `lib/mobile_car_wash_web/live/admin/dispatch_presenter.ex`
  - Shared derived dispatch state for web.
- `test/mobile_car_wash_web/live/admin/dispatch_presenter_test.exs`
  - Presenter derived-state coverage.

iOS files to verify and possibly patch:

- `DrivewayDetailCo/Features/Admin/AdminTabView.swift`
  - Admin tab routing.
- `DrivewayDetailCo/Features/Admin/AdminDashboardView.swift`
  - Command Center landing.
- `DrivewayDetailCo/Features/Admin/AdminDispatchView.swift`
  - Native dispatch command board.
- `DrivewayDetailCo/Features/Admin/AdminDispatchViewModel.swift`
  - Dispatch API loading and mutation state.
- `DrivewayDetailCo/Features/Admin/AdminDispatchComponents.swift`
  - Dispatch cards, metrics, exceptions, workload controls.
- `DrivewayDetailCo/Features/Admin/AdminCustomersView.swift`
  - Customer list/detail/admin controls.
- `DrivewayDetailCo/Core/APIClient.swift`
  - Shared API client and decoder.
- `DrivewayDetailCo/Core/Endpoints.swift`
  - API path/method/query mapping.
- `DrivewayDetailCo/Models/AdminDispatch.swift`
  - Dispatch payload models.
- `DrivewayDetailCo/Models/AdminCustomer.swift`
  - Customer payload models.
- `DrivewayDetailCoTests/Features/AdminDispatchViewModelTests.swift`
  - Dispatch view-model coverage.
- `DrivewayDetailCoTests/Features/AdminCustomersViewModelTests.swift`
  - Customer view-model coverage.
- `DrivewayDetailCoTests/Core/ModelDecodingTests.swift`
  - Real backend JSON decoding coverage.

---

### Task 1: Establish Clean Verification Baseline

**Files:**
- Inspect only: Phoenix and iOS git status

- [ ] **Step 1: Verify Phoenix dirty state**

Run:

```bash
cd /Volumes/mac_external/Development/Business/MobileCarWash
git status --short
```

Expected:

```text
 M AGENTS.md
```

If any other file is dirty, stop and inspect it with:

```bash
git diff --stat
git diff -- <path>
```

Do not stage, revert, or edit unrelated files.

- [ ] **Step 2: Verify iOS branch state**

Run:

```bash
cd /Volumes/mac_external/sdgku/DrivewayDetailCo/.worktrees/ios-admin-dispatch-command-center
git status --short
git branch --show-current
git log --oneline -5
```

Expected:

```text
codex/ios-admin-dispatch-command-center
180b596 fix: clarify dispatch date action
804bf6c fix: surface admin customer rows
6b2e7bd fix: decode customer wash timestamps
43a53bd fix: decode admin appointment payloads
4b9a1c5 feat: make ios admin dashboard a command center
```

- [ ] **Step 3: Commit nothing**

This task is a baseline task only. There should be no commit.

---

### Task 2: Run Full Phoenix Verification

**Files:**
- Verify: `test/mobile_car_wash_web/controllers/api/v1/admin_dispatch_controller_test.exs`
- Verify: `test/mobile_car_wash_web/live/admin/dispatch_presenter_test.exs`
- Verify all Phoenix code with `mix precommit`

- [ ] **Step 1: Run focused dispatch tests**

Run:

```bash
cd /Volumes/mac_external/Development/Business/MobileCarWash
mix test \
  test/mobile_car_wash_web/controllers/api/v1/admin_dispatch_controller_test.exs \
  test/mobile_car_wash_web/live/admin/dispatch_presenter_test.exs
```

Expected:

```text
0 failures
```

- [ ] **Step 2: Run Phoenix precommit**

Run:

```bash
cd /Volumes/mac_external/Development/Business/MobileCarWash
mix precommit
```

Expected:

```text
0 failures
```

- [ ] **Step 3: If Phoenix verification fails, fix only the failing behavior**

Use this loop:

```bash
mix test <failing-test-file>
mix format <changed-files>
mix test <failing-test-file>
mix precommit
```

Commit only if a Phoenix code change is required:

```bash
git add <changed-files>
git commit -m "fix: stabilize admin flow verification"
git push origin main
```

Do not include `AGENTS.md` in the commit.

---

### Task 3: Run Full iOS Verification

**Files:**
- Verify all iOS tests through Xcode

- [ ] **Step 1: Run focused admin and decoding tests first**

Run:

```bash
cd /Volumes/mac_external/sdgku/DrivewayDetailCo/.worktrees/ios-admin-dispatch-command-center
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project DrivewayDetailCo.xcodeproj \
  -scheme DrivewayDetailCo \
  -destination 'id=0D565491-438B-4641-99C4-56C7C0CB781A' \
  -derivedDataPath /tmp/DrivewayDetailCoSmokeBuild \
  -only-testing:DrivewayDetailCoTests/ModelDecodingTests \
  -only-testing:DrivewayDetailCoTests/AdminDispatchViewModelTests \
  -only-testing:DrivewayDetailCoTests/AdminCustomersViewModelTests
```

Expected:

```text
** TEST SUCCEEDED **
```

- [ ] **Step 2: Run the full iOS test suite**

Run:

```bash
cd /Volumes/mac_external/sdgku/DrivewayDetailCo/.worktrees/ios-admin-dispatch-command-center
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project DrivewayDetailCo.xcodeproj \
  -scheme DrivewayDetailCo \
  -destination 'id=0D565491-438B-4641-99C4-56C7C0CB781A' \
  -derivedDataPath /tmp/DrivewayDetailCoFullBuild
```

Expected:

```text
** TEST SUCCEEDED **
```

- [ ] **Step 3: Fix any full-suite regressions with focused commits**

For each failing area, run the smallest failing test target after the fix. Commit each independent fix:

```bash
git add <changed-files>
git commit -m "fix: stabilize ios admin flow"
git push origin codex/ios-admin-dispatch-command-center
```

Do not batch unrelated test fixes into one commit.

---

### Task 4: Simulator Smoke Test The Admin Navigation

**Files:**
- Verify: `DrivewayDetailCo/Features/Admin/AdminTabView.swift`
- Verify: `DrivewayDetailCo/Features/Admin/AdminDashboardView.swift`
- Verify: `DrivewayDetailCo/Features/Admin/AdminDispatchView.swift`
- Verify: `DrivewayDetailCo/Features/Admin/AdminCustomersView.swift`

- [ ] **Step 1: Build and install the current iOS app**

Run:

```bash
cd /Volumes/mac_external/sdgku/DrivewayDetailCo/.worktrees/ios-admin-dispatch-command-center
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
  -project DrivewayDetailCo.xcodeproj \
  -scheme DrivewayDetailCo \
  -configuration Debug \
  -destination 'id=0D565491-438B-4641-99C4-56C7C0CB781A' \
  -derivedDataPath /tmp/DrivewayDetailCoSmokeBuild

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl boot 0D565491-438B-4641-99C4-56C7C0CB781A || true
open -a Simulator --args -CurrentDeviceUDID 0D565491-438B-4641-99C4-56C7C0CB781A
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl bootstatus 0D565491-438B-4641-99C4-56C7C0CB781A -b
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl install 0D565491-438B-4641-99C4-56C7C0CB781A /tmp/DrivewayDetailCoSmokeBuild/Build/Products/Debug-iphonesimulator/DrivewayDetailCo.app
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl launch --terminate-running-process 0D565491-438B-4641-99C4-56C7C0CB781A com.wendellrichards.DrivewayDetailCo
```

Expected:

```text
com.wendellrichards.DrivewayDetailCo: <pid>
```

- [ ] **Step 2: Smoke Command tab**

Manual checks:

- Command tab title reads `Command Center`.
- No red error text appears.
- `Open Dispatch` navigates to Dispatch.
- `Customers` navigates to Customers.
- Metrics cards render without overlap.

Capture screenshot:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl io 0D565491-438B-4641-99C4-56C7C0CB781A screenshot /tmp/admin-command-smoke.png
```

- [ ] **Step 3: Smoke Dispatch tab**

Manual checks:

- Dispatch tab title reads `Dispatch`.
- Calendar menu label is icon-only in the toolbar, and inside the menu the action reads `Show <selected date>`, not `Load Date`.
- Refresh button does not create an error.
- Metrics, exceptions, active services, assignment queue, and technicians sections render.
- Empty states are readable when there is no data.

Capture screenshot:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl io 0D565491-438B-4641-99C4-56C7C0CB781A screenshot /tmp/admin-dispatch-smoke.png
```

- [ ] **Step 4: Smoke Appointments tab**

Manual checks:

- Appointments tab loads without `unexpected response`.
- Appointment rows show customer/service/date details.
- Opening a row shows appointment detail.
- Assignment/confirm controls in detail still work or show disabled state correctly.

Capture screenshot:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl io 0D565491-438B-4641-99C4-56C7C0CB781A screenshot /tmp/admin-appointments-smoke.png
```

- [ ] **Step 5: Smoke Customers tab**

Manual checks:

- Customers tab shows real rows immediately below collapsed `Filters`.
- Search field is visible.
- Selecting a row opens customer detail.
- Bulk tag controls appear only after a customer is selected.

Capture screenshot:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl io 0D565491-438B-4641-99C4-56C7C0CB781A screenshot /tmp/admin-customers-smoke.png
```

- [ ] **Step 6: Smoke More tab**

Manual checks:

- More tab opens.
- Existing admin management surfaces are reachable.
- No placeholder-only screens remain for implemented admin flow areas.

Capture screenshot:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl io 0D565491-438B-4641-99C4-56C7C0CB781A screenshot /tmp/admin-more-smoke.png
```

---

### Task 5: Verify Real Backend Dispatch Mutations

**Files:**
- Verify: `lib/mobile_car_wash_web/controllers/api/v1/admin_dispatch_controller.ex`
- Verify: `DrivewayDetailCo/Features/Admin/AdminDispatchViewModel.swift`
- Verify: `DrivewayDetailCo/Core/APIClient.swift`

- [ ] **Step 1: Ensure Phoenix dev server is running**

Run:

```bash
cd /Volumes/mac_external/Development/Business/MobileCarWash
lsof -i :4000 -sTCP:LISTEN
```

Expected: a process listening on `*:4000` or `127.0.0.1:4000`.

If no server is running:

```bash
mix phx.server
```

- [ ] **Step 2: Get an admin token**

Run:

```bash
cd /Volumes/mac_external/Development/Business/MobileCarWash
TOKEN=$(curl -s -X POST http://127.0.0.1:4000/api/v1/auth/sign_in \
  -H 'content-type: application/json' \
  -d '{"email":"smoke-admin@example.com","password":"Password123!"}' | jq -r '.token')
echo ${#TOKEN}
```

Expected: a non-zero token length.

- [ ] **Step 3: Verify dispatch payload has actionable rows or document empty fixture state**

Run:

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  "http://127.0.0.1:4000/api/v1/admin/dispatch" | \
  jq '{date:.data.date, metrics:.data.metrics, queue_ids:(.data.assignment_queue | map(.id)), active_ids:(.data.active_services | map(.id)), tech_ids:(.data.technician_workload | map(.id))}'
```

Expected: JSON with `metrics`, `queue_ids`, `active_ids`, and `tech_ids`.

If there are no assignment or active rows, seed or create one using existing app flows before continuing. Do not add a new backend endpoint for this.

- [ ] **Step 4: Verify assign/unassign from API**

Use an appointment ID from `assignment_queue` and a technician ID from `technician_workload`:

```bash
APPOINTMENT_ID=<appointment-id>
TECHNICIAN_ID=<technician-id>

curl -s -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H 'content-type: application/json' \
  -d "{\"technician_id\":\"$TECHNICIAN_ID\"}" \
  "http://127.0.0.1:4000/api/v1/admin/dispatch/appointments/$APPOINTMENT_ID/assign" | \
  jq '.data | {id, technician_id, technician_name, status}'

curl -s -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H 'content-type: application/json' \
  -d '{"technician_id":null}' \
  "http://127.0.0.1:4000/api/v1/admin/dispatch/appointments/$APPOINTMENT_ID/assign" | \
  jq '.data | {id, technician_id, technician_name, status}'
```

Expected:

- First response has `technician_id == TECHNICIAN_ID`.
- Second response has `technician_id == null`.

- [ ] **Step 5: Verify confirm from API**

Assign the technician again, then confirm:

```bash
curl -s -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H 'content-type: application/json' \
  -d "{\"technician_id\":\"$TECHNICIAN_ID\"}" \
  "http://127.0.0.1:4000/api/v1/admin/dispatch/appointments/$APPOINTMENT_ID/assign" >/dev/null

curl -s -X POST \
  -H "Authorization: Bearer $TOKEN" \
  "http://127.0.0.1:4000/api/v1/admin/dispatch/appointments/$APPOINTMENT_ID/confirm" | \
  jq '.data | {id, technician_id, status}'
```

Expected:

```json
{
  "id": "<appointment-id>",
  "technician_id": "<technician-id>",
  "status": "confirmed"
}
```

- [ ] **Step 6: Verify same mutations in the simulator**

Manual checks:

- Open Dispatch tab.
- Assign the same kind of queued appointment to a technician.
- Confirm it.
- Pull to refresh.
- Verify the row status and technician assignment remain consistent after refresh.

If the API succeeds but simulator fails, inspect and patch iOS only.

---

### Task 6: Verify Customer Detail And Admin Controls

**Files:**
- Verify: `DrivewayDetailCo/Features/Admin/AdminCustomersView.swift`
- Verify: `DrivewayDetailCoTests/Features/AdminCustomersViewModelTests.swift`
- Verify: Phoenix customer admin API controllers if failures point backend-side

- [ ] **Step 1: Verify customer list endpoint**

Run:

```bash
cd /Volumes/mac_external/Development/Business/MobileCarWash
TOKEN=$(curl -s -X POST http://127.0.0.1:4000/api/v1/auth/sign_in \
  -H 'content-type: application/json' \
  -d '{"email":"smoke-admin@example.com","password":"Password123!"}' | jq -r '.token')

curl -s -H "Authorization: Bearer $TOKEN" \
  "http://127.0.0.1:4000/api/v1/admin/customers" | \
  jq '{count:(.data | length), first:(.data[0] | {id, name, email, last_wash_at, tags})}'
```

Expected: `count` is greater than `0`.

- [ ] **Step 2: Verify customer detail endpoint**

Use the first customer ID:

```bash
CUSTOMER_ID=$(curl -s -H "Authorization: Bearer $TOKEN" \
  "http://127.0.0.1:4000/api/v1/admin/customers" | jq -r '.data[0].id')

curl -s -H "Authorization: Bearer $TOKEN" \
  "http://127.0.0.1:4000/api/v1/admin/customers/$CUSTOMER_ID" | \
  jq '.data | {id, name, email, note_count, tags, personas, available_tags, available_channels}'
```

Expected: JSON decodes with detail fields present.

- [ ] **Step 3: Verify customer detail in simulator**

Manual checks:

- Open Customers tab.
- Open the first customer row.
- Confirm Profile, Attribution, Account Controls, Notes, Tags, Personas, and Recent Appointments sections render.
- Confirm no red `Customer unavailable` state appears.

- [ ] **Step 4: Verify customer admin mutations from simulator**

Manual checks:

- Add a note with body `Smoke test note`.
- Toggle pin on the note.
- Apply a tag with reason `Smoke test tag`.
- Reassign channel if available.
- Resend verification for an unverified customer.
- Do not disable a real customer unless using the smoke admin/customer fixture.

- [ ] **Step 5: If a customer action fails, add the smallest test first**

Add to `DrivewayDetailCoTests/Features/AdminCustomersViewModelTests.swift` using this pattern:

```swift
@Test("reports customer mutation errors without clearing current detail")
func reportsCustomerMutationErrorsWithoutClearingDetail() async {
    let api = MockAPIClient()
    api.adminCustomerDetailToReturn = StubFactory.adminCustomerDetail()
    let viewModel = AdminCustomerDetailViewModel(customerId: "cust-1", api: api)

    await viewModel.load()
    api.errorToThrow = URLError(.badServerResponse)
    await viewModel.resendVerification()

    #expect(viewModel.customer?.id == "cust-1")
    #expect(viewModel.errorMessage != nil)
}
```

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project DrivewayDetailCo.xcodeproj \
  -scheme DrivewayDetailCo \
  -destination 'id=0D565491-438B-4641-99C4-56C7C0CB781A' \
  -derivedDataPath /tmp/DrivewayDetailCoSmokeBuild \
  -only-testing:DrivewayDetailCoTests/AdminCustomersViewModelTests
```

Commit the fix:

```bash
git add DrivewayDetailCo/Features/Admin/AdminCustomersView.swift DrivewayDetailCoTests/Features/AdminCustomersViewModelTests.swift
git commit -m "fix: stabilize admin customer detail actions"
git push origin codex/ios-admin-dispatch-command-center
```

---

### Task 7: Polish Remaining Admin UI Rough Edges

**Files:**
- Modify only if smoke testing finds issues:
  - `DrivewayDetailCo/Features/Admin/AdminDashboardView.swift`
  - `DrivewayDetailCo/Features/Admin/AdminDispatchView.swift`
  - `DrivewayDetailCo/Features/Admin/AdminDispatchComponents.swift`
  - `DrivewayDetailCo/Features/Admin/AdminCustomersView.swift`

- [ ] **Step 1: Collect concrete polish issues**

Create a short list with this exact format in the task notes:

```text
Screen:
Issue:
Expected:
Screenshot:
```

Do not change UI from preference alone; only fix issues observed in simulator smoke testing.

- [ ] **Step 2: Patch one issue at a time**

For copy-only changes, patch the exact label. Example pattern:

```swift
Button("Show \(viewModel.selectedDateLabel)") {
    Task { await viewModel.load() }
}
```

For layout issues, prefer local SwiftUI modifiers on the component with the issue:

```swift
.lineLimit(2)
.minimumScaleFactor(0.8)
.fixedSize(horizontal: false, vertical: true)
```

- [ ] **Step 3: Run focused tests**

For Dispatch changes:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project DrivewayDetailCo.xcodeproj \
  -scheme DrivewayDetailCo \
  -destination 'id=0D565491-438B-4641-99C4-56C7C0CB781A' \
  -derivedDataPath /tmp/DrivewayDetailCoSmokeBuild \
  -only-testing:DrivewayDetailCoTests/AdminDispatchViewModelTests
```

For Customers changes:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project DrivewayDetailCo.xcodeproj \
  -scheme DrivewayDetailCo \
  -destination 'id=0D565491-438B-4641-99C4-56C7C0CB781A' \
  -derivedDataPath /tmp/DrivewayDetailCoSmokeBuild \
  -only-testing:DrivewayDetailCoTests/AdminCustomersViewModelTests
```

- [ ] **Step 4: Commit polish fixes**

Run:

```bash
git add <changed-ios-files>
git commit -m "fix: polish ios admin flow"
git push origin codex/ios-admin-dispatch-command-center
```

---

### Task 8: Decide Native Dispatch Map Scope

**Files:**
- No code changes in this task unless the user explicitly approves MapKit implementation.

- [ ] **Step 1: Record current scope decision**

Current decision:

```text
Native iOS MapKit dispatch map is out of scope for the current completion pass.
The web app retains the existing DispatchMap hook. The iOS command center focuses on same-day triage, queue management, exceptions, technician workload, assignment, and confirmation.
```

- [ ] **Step 2: If the user requires a native map, create a separate plan**

Create a new plan instead of adding MapKit into this finish plan:

```bash
cd /Volumes/mac_external/Development/Business/MobileCarWash
touch docs/superpowers/plans/2026-05-31-ios-admin-dispatch-mapkit.md
```

The MapKit plan must include:

- `Map`/`MapKit` region state.
- Appointment coordinate requirements.
- Backend coordinate payload verification.
- Empty coordinate fallback.
- Simulator visual verification.

- [ ] **Step 3: Commit nothing**

This task is a decision checkpoint only.

---

### Task 9: Final Branch Verification And Merge Readiness

**Files:**
- Verify all changed files
- No code changes unless final verification fails

- [ ] **Step 1: Run final Phoenix status**

Run:

```bash
cd /Volumes/mac_external/Development/Business/MobileCarWash
git status --short
```

Expected:

```text
 M AGENTS.md
```

- [ ] **Step 2: Run final iOS status**

Run:

```bash
cd /Volumes/mac_external/sdgku/DrivewayDetailCo/.worktrees/ios-admin-dispatch-command-center
git status --short
git log --oneline origin/main..HEAD
```

Expected:

- `git status --short` is empty.
- `git log origin/main..HEAD` shows the admin command center commits.

- [ ] **Step 3: Push latest branch**

Run:

```bash
cd /Volumes/mac_external/sdgku/DrivewayDetailCo/.worktrees/ios-admin-dispatch-command-center
git push origin codex/ios-admin-dispatch-command-center
```

Expected:

```text
Everything up-to-date
```

or a successful branch update.

- [ ] **Step 4: Prepare merge summary**

Use this summary:

```text
Admin Command Center completion:
- Phoenix admin dispatch API verified, including auth, payload, assign/unassign, confirm, and timestamp format.
- iOS admin dashboard now opens as Command Center.
- iOS Dispatch tab supports metrics, exceptions, active services, assignment queue, technician workload, refresh, date loading, assign, and confirm.
- iOS Customers tab fetches real customers, opens detail, and preserves customer admin controls.
- Full Phoenix and iOS verification completed.
- Native iOS MapKit dispatch map intentionally deferred unless separately approved.
```

- [ ] **Step 5: Merge only after user approval**

Do not merge automatically. Ask the user whether to:

```text
1. Merge the iOS branch to main and push
2. Open a PR / leave branch for review
3. Continue with optional MapKit dispatch map plan
```

---

## Self-Review

- Spec coverage: This plan completes the already implemented command metrics, active services, assignment queue, exceptions, technician workload, assign/unassign, confirm, native iOS UI, customers flow, and final verification.
- Intentional omission: Native iOS MapKit dispatch map remains out of scope unless separately approved. The web dispatch map hook remains intact.
- Placeholder scan: No `TBD`, `TODO`, or vague “add tests” steps remain.
- Type consistency: Paths and command names match the current Phoenix and iOS branches.
