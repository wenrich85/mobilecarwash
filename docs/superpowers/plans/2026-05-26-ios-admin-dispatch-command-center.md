# iOS Admin Dispatch Command Center Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring the approved web Admin Dispatch Command Center into the DrivewayDetailCo iOS admin flow with native same-day dispatch monitoring, exception triage, technician workload, and assignment/confirm controls.

**Architecture:** Add a compact Phoenix API facade that reuses the existing dispatch presenter and backend dispatch actions, then consume that contract from the iOS app with focused Swift models, API methods, a view model, and SwiftUI command-center views. Keep iOS derivation lightweight; server owns cross-record dispatch state so web and native stay consistent.

**Tech Stack:** Phoenix/Ash/ExUnit API tests in `/Volumes/mac_external/Development/Business/MobileCarWash`; SwiftUI/Observation/Swift Testing/XCTest project in `/Volumes/mac_external/sdgku/DrivewayDetailCo`.

---

## Scope Notes

- The current iOS admin app already has a read-only dashboard, appointments list, appointment detail, services list, tech tab, and account tab.
- The web dispatch redesign is already implemented in `MobileCarWashWeb.Admin.DispatchLive`, `MobileCarWashWeb.Admin.DispatchPresenter`, and `MobileCarWashWeb.Admin.DispatchComponents`.
- This plan does not duplicate LiveView behavior in Swift. It adds native iOS controls backed by a new admin dispatch API.
- Preserve existing `/api/v1/appointments` behavior for customer/admin appointment list screens.
- Preserve existing tech APIs and photo-channel work.
- Keep `AGENTS.md` untouched unless explicitly asked; it is currently an unrelated dirty file in the Phoenix repo.

## File Structure

Phoenix repo:

- Create `lib/mobile_car_wash_web/plugs/require_admin_api_auth.ex`
  - API plug that requires an authenticated bearer user with `role == :admin`.
- Create `lib/mobile_car_wash_web/controllers/api/v1/admin_dispatch_controller.ex`
  - JSON command-center endpoint and assignment/confirm mutations for iOS admin.
- Modify `lib/mobile_car_wash_web/router.ex`
  - Add `/api/v1/admin/dispatch`, `/api/v1/admin/dispatch/appointments/:id/assign`, and `/api/v1/admin/dispatch/appointments/:id/confirm`.
- Test `test/mobile_car_wash_web/controllers/api/v1/admin_dispatch_controller_test.exs`
  - Verify admin-only access, command payload shape, assign, unassign, and confirm.

iOS repo:

- Create `DrivewayDetailCo/Models/AdminDispatch.swift`
  - Codable command-center models matching the Phoenix API payload.
- Modify `DrivewayDetailCo/Core/Endpoints.swift`
  - Add admin dispatch endpoints and HTTP methods.
- Modify `DrivewayDetailCo/Core/APIClient.swift`
  - Add protocol and implementation methods for command payload, assign, unassign, confirm.
- Modify `DrivewayDetailCoTests/TestSupport/StubFactory.swift`
  - Add model builders and `MockAPIClient` methods.
- Create `DrivewayDetailCo/Features/Admin/AdminDispatchViewModel.swift`
  - Load, refresh, filter, assign, unassign, confirm, and expose derived sections.
- Create `DrivewayDetailCo/Features/Admin/AdminDispatchView.swift`
  - Native command-center screen.
- Create `DrivewayDetailCo/Features/Admin/AdminDispatchComponents.swift`
  - Reusable cards/rows for metrics, active services, assignment queue, exceptions, workload.
- Modify `DrivewayDetailCo/Features/Admin/AdminTabView.swift`
  - Add a Dispatch tab before Appointments.
- Test `DrivewayDetailCoTests/Features/AdminDispatchViewModelTests.swift`
  - Focused view-model tests only.

---

### Task 1: Phoenix Admin API Auth Plug

**Files:**
- Create: `lib/mobile_car_wash_web/plugs/require_admin_api_auth.ex`
- Test: `test/mobile_car_wash_web/controllers/api/v1/admin_dispatch_controller_test.exs`

- [ ] **Step 1: Write the failing auth tests**

Create `test/mobile_car_wash_web/controllers/api/v1/admin_dispatch_controller_test.exs` with the initial access tests:

```elixir
defmodule MobileCarWashWeb.Api.V1.AdminDispatchControllerTest do
  use MobileCarWashWeb.ApiCase

  alias MobileCarWash.Accounts.Customer

  defp register_api_user(conn, role) do
    {conn, user, _token} =
      register_and_sign_in(conn,
        email: "admin-dispatch-#{role}-#{System.unique_integer([:positive])}@example.com"
      )

    {:ok, user} =
      user
      |> Ash.Changeset.for_update(:update, %{role: role})
      |> Ash.update(authorize?: false)

    {conn, user}
  end

  describe "GET /api/v1/admin/dispatch" do
    test "rejects anonymous requests", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/admin/dispatch")
      assert json_response(conn, 401)["error"] == "unauthorized"
    end

    test "rejects non-admin users", %{conn: conn} do
      {conn, _user} = register_api_user(conn, :customer)
      conn = get(conn, ~p"/api/v1/admin/dispatch")
      assert json_response(conn, 403)["error"] == "forbidden"
    end
  end
end
```

- [ ] **Step 2: Run the failing test**

Run:

```bash
cd /Volumes/mac_external/Development/Business/MobileCarWash
mix test test/mobile_car_wash_web/controllers/api/v1/admin_dispatch_controller_test.exs
```

Expected: failure because the route/controller does not exist yet.

- [ ] **Step 3: Add the auth plug**

Create `lib/mobile_car_wash_web/plugs/require_admin_api_auth.ex`:

```elixir
defmodule MobileCarWashWeb.Plugs.RequireAdminApiAuth do
  @moduledoc """
  Requires a bearer-authenticated API user with the admin role.
  """
  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  def init(opts), do: opts

  def call(conn, _opts) do
    case conn.assigns[:current_user] || conn.assigns[:current_customer] do
      nil ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "unauthorized"})
        |> halt()

      %{role: :admin} ->
        conn

      _ ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "forbidden"})
        |> halt()
    end
  end
end
```

- [ ] **Step 4: Add a placeholder route/controller for auth only**

Modify `lib/mobile_car_wash_web/router.ex` inside `scope "/api/v1"`:

```elixir
get "/admin/dispatch", AdminDispatchController, :show
```

Create `lib/mobile_car_wash_web/controllers/api/v1/admin_dispatch_controller.ex`:

```elixir
defmodule MobileCarWashWeb.Api.V1.AdminDispatchController do
  use MobileCarWashWeb, :controller

  plug MobileCarWashWeb.Plugs.RequireAdminApiAuth

  def show(conn, _params) do
    json(conn, %{data: %{metrics: %{total: 0}}})
  end
end
```

- [ ] **Step 5: Run test and commit**

Run:

```bash
mix format lib/mobile_car_wash_web/plugs/require_admin_api_auth.ex lib/mobile_car_wash_web/controllers/api/v1/admin_dispatch_controller.ex lib/mobile_car_wash_web/router.ex test/mobile_car_wash_web/controllers/api/v1/admin_dispatch_controller_test.exs
mix test test/mobile_car_wash_web/controllers/api/v1/admin_dispatch_controller_test.exs
git add lib/mobile_car_wash_web/plugs/require_admin_api_auth.ex lib/mobile_car_wash_web/controllers/api/v1/admin_dispatch_controller.ex lib/mobile_car_wash_web/router.ex test/mobile_car_wash_web/controllers/api/v1/admin_dispatch_controller_test.exs
git commit -m "feat: add admin dispatch api auth"
```

Expected: auth tests pass.

---

### Task 2: Phoenix Command-Center Payload

**Files:**
- Modify: `lib/mobile_car_wash_web/controllers/api/v1/admin_dispatch_controller.ex`
- Test: `test/mobile_car_wash_web/controllers/api/v1/admin_dispatch_controller_test.exs`

- [ ] **Step 1: Add payload shape test**

Append a test that creates one admin, one technician, one customer appointment, then asserts the command payload has the same high-level regions as the web command center:

```elixir
test "returns command-center state for admins", %{conn: conn} do
  {conn, _admin} = register_api_user(conn, :admin)
  %{appointment: appointment, technician: technician} = create_dispatch_fixture(:pending)

  conn = get(conn, ~p"/api/v1/admin/dispatch")
  body = json_response(conn, 200)["data"]

  assert body["metrics"]["total"] >= 1
  assert Enum.any?(body["assignment_queue"], &(&1["id"] == appointment.id))
  assert Enum.any?(body["technician_workload"], &(&1["id"] == technician.id))
  assert is_list(body["exceptions"])
  assert is_list(body["active_services"])
end
```

Add local fixture helpers for customer, service, vehicle, address, technician, and appointment following the patterns in existing API controller tests.

- [ ] **Step 2: Run failing test**

Run:

```bash
mix test test/mobile_car_wash_web/controllers/api/v1/admin_dispatch_controller_test.exs
```

Expected: failure because the placeholder payload is incomplete.

- [ ] **Step 3: Implement payload loading**

Update `AdminDispatchController.show/2` to:

- Load active technicians.
- Load dispatch appointments for an optional `date` query param, defaulting to today in UTC.
- Load service/customer/address/vehicle maps as needed for labels.
- Reuse `MobileCarWashWeb.Admin.DispatchPresenter.metrics/3`, `assignment_queue/1`, `active_appointments/1`, `exceptions/2`, and `technician_workload/3`.
- Serialize only JSON-safe strings and primitives.

Use this response shape:

```elixir
%{
  data: %{
    generated_at: DateTime.utc_now(),
    date: Date.to_iso8601(date),
    metrics: %{total: 1, in_progress: 0, ready_to_assign: 1, completed: 0, on_duty: 1, exceptions: 1},
    active_services: [],
    assignment_queue: [appointment_json(appointment, maps)],
    exceptions: [exception_json(exception, maps)],
    technician_workload: [workload_json(workload)]
  }
}
```

- [ ] **Step 4: Run focused tests and commit**

Run:

```bash
mix format lib/mobile_car_wash_web/controllers/api/v1/admin_dispatch_controller.ex test/mobile_car_wash_web/controllers/api/v1/admin_dispatch_controller_test.exs
mix test test/mobile_car_wash_web/controllers/api/v1/admin_dispatch_controller_test.exs
git add lib/mobile_car_wash_web/controllers/api/v1/admin_dispatch_controller.ex test/mobile_car_wash_web/controllers/api/v1/admin_dispatch_controller_test.exs
git commit -m "feat: expose admin dispatch command payload"
```

---

### Task 3: Phoenix Assign And Confirm Mutations

**Files:**
- Modify: `lib/mobile_car_wash_web/router.ex`
- Modify: `lib/mobile_car_wash_web/controllers/api/v1/admin_dispatch_controller.ex`
- Test: `test/mobile_car_wash_web/controllers/api/v1/admin_dispatch_controller_test.exs`

- [ ] **Step 1: Add mutation tests**

Add tests:

```elixir
test "assigns a technician", %{conn: conn} do
  {conn, _admin} = register_api_user(conn, :admin)
  %{appointment: appointment, technician: technician} = create_dispatch_fixture(:pending)

  conn =
    post(conn, ~p"/api/v1/admin/dispatch/appointments/#{appointment.id}/assign", %{
      "technician_id" => technician.id
    })

  body = json_response(conn, 200)["data"]
  assert body["id"] == appointment.id
  assert body["technician_id"] == technician.id
end

test "unassigns a technician", %{conn: conn} do
  {conn, _admin} = register_api_user(conn, :admin)
  %{appointment: appointment} = create_dispatch_fixture(:confirmed_with_tech)

  conn =
    post(conn, ~p"/api/v1/admin/dispatch/appointments/#{appointment.id}/assign", %{
      "technician_id" => nil
    })

  assert json_response(conn, 200)["data"]["technician_id"] == nil
end

test "confirms an assigned pending appointment", %{conn: conn} do
  {conn, _admin} = register_api_user(conn, :admin)
  %{appointment: appointment} = create_dispatch_fixture(:pending_with_tech)

  conn = post(conn, ~p"/api/v1/admin/dispatch/appointments/#{appointment.id}/confirm")
  assert json_response(conn, 200)["data"]["status"] == "confirmed"
end
```

- [ ] **Step 2: Run failing tests**

Run:

```bash
mix test test/mobile_car_wash_web/controllers/api/v1/admin_dispatch_controller_test.exs
```

- [ ] **Step 3: Implement routes and actions**

Add routes:

```elixir
post "/admin/dispatch/appointments/:id/assign", AdminDispatchController, :assign
post "/admin/dispatch/appointments/:id/confirm", AdminDispatchController, :confirm
```

Implement actions by reusing `MobileCarWash.Scheduling.Dispatch.assign_technician/2`, `unassign_technician/1`, and appointment `:confirm` update. Return the reloaded serialized appointment.

- [ ] **Step 4: Run tests and commit**

Run:

```bash
mix format lib/mobile_car_wash_web/controllers/api/v1/admin_dispatch_controller.ex lib/mobile_car_wash_web/router.ex test/mobile_car_wash_web/controllers/api/v1/admin_dispatch_controller_test.exs
mix test test/mobile_car_wash_web/controllers/api/v1/admin_dispatch_controller_test.exs
git add lib/mobile_car_wash_web/controllers/api/v1/admin_dispatch_controller.ex lib/mobile_car_wash_web/router.ex test/mobile_car_wash_web/controllers/api/v1/admin_dispatch_controller_test.exs
git commit -m "feat: add admin dispatch assignment api"
```

---

### Task 4: iOS Models And API Contract

**Files:**
- Create: `/Volumes/mac_external/sdgku/DrivewayDetailCo/DrivewayDetailCo/Models/AdminDispatch.swift`
- Modify: `/Volumes/mac_external/sdgku/DrivewayDetailCo/DrivewayDetailCo/Core/Endpoints.swift`
- Modify: `/Volumes/mac_external/sdgku/DrivewayDetailCo/DrivewayDetailCo/Core/APIClient.swift`
- Modify: `/Volumes/mac_external/sdgku/DrivewayDetailCo/DrivewayDetailCoTests/TestSupport/StubFactory.swift`

- [ ] **Step 1: Add models**

Create `DrivewayDetailCo/Models/AdminDispatch.swift`:

```swift
import Foundation

struct AdminDispatchCommandCenter: Codable, Equatable, Sendable {
    let generatedAt: Date
    let date: String
    let metrics: AdminDispatchMetrics
    let activeServices: [AdminDispatchAppointment]
    let assignmentQueue: [AdminDispatchAppointment]
    let exceptions: [AdminDispatchException]
    let technicianWorkload: [AdminTechnicianWorkload]
}

struct AdminDispatchMetrics: Codable, Equatable, Sendable {
    let total: Int
    let inProgress: Int
    let readyToAssign: Int
    let completed: Int
    let onDuty: Int
    let exceptions: Int
}

struct AdminDispatchAppointment: Codable, Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let status: AppointmentStatus
    let scheduledAt: Date
    let durationMinutes: Int
    let priceCents: Int
    let customerId: String?
    let customerName: String?
    let serviceName: String?
    let technicianId: String?
    let technicianName: String?
    let addressLine: String?
    let vehicleName: String?
    let progress: AppointmentLiveProgress?
    let beforePhotoCount: Int?
    let afterPhotoCount: Int?
}

struct AdminDispatchException: Codable, Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let appointmentId: String
    let customerId: String?
    let severity: Severity
    let kind: String
    let reason: String
    let action: String
    let scheduledAt: Date

    enum Severity: String, Codable, Sendable {
        case high
        case medium
        case low
    }
}

struct AdminTechnicianWorkload: Codable, Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let name: String
    let status: DutyStatus
    let zone: String?
    let assignedCount: Int
    let active: Bool
    let pressure: Pressure
    let currentAppointmentId: String?

    enum Pressure: String, Codable, Sendable {
        case normal
        case medium
        case high
    }
}
```

- [ ] **Step 2: Add endpoint cases and API methods**

In `Endpoint`, add:

```swift
case adminDispatch(date: String?)
case adminDispatchAssign(appointmentId: String)
case adminDispatchConfirm(appointmentId: String)
```

Map paths:

```swift
case .adminDispatch: return "/admin/dispatch"
case .adminDispatchAssign(let appointmentId): return "/admin/dispatch/appointments/\(appointmentId)/assign"
case .adminDispatchConfirm(let appointmentId): return "/admin/dispatch/appointments/\(appointmentId)/confirm"
```

Map methods:

```swift
case .adminDispatchAssign, .adminDispatchConfirm:
    return "POST"
```

Map query:

```swift
case .adminDispatch(let date):
    return date.map { [URLQueryItem(name: "date", value: $0)] }
```

In `APIClientProtocol`, add:

```swift
func adminDispatch(date: String?) async throws -> AdminDispatchCommandCenter
func assignAdminDispatchAppointment(id: String, technicianId: String?) async throws -> AdminDispatchAppointment
func confirmAdminDispatchAppointment(id: String) async throws -> AdminDispatchAppointment
```

In `APIClient`, implement:

```swift
func adminDispatch(date: String? = nil) async throws -> AdminDispatchCommandCenter {
    let request = Endpoint.adminDispatch(date: date).urlRequest(baseURL: baseURL, token: tokenProvider())
    return try await performRequest(request, responseType: DataWrapper<AdminDispatchCommandCenter>.self).data
}

func assignAdminDispatchAppointment(id: String, technicianId: String?) async throws -> AdminDispatchAppointment {
    let body = try JSONEncoder.api.encode(["technician_id": technicianId])
    let request = Endpoint.adminDispatchAssign(appointmentId: id).urlRequest(baseURL: baseURL, token: tokenProvider(), body: body)
    return try await performRequest(request, responseType: DataWrapper<AdminDispatchAppointment>.self).data
}

func confirmAdminDispatchAppointment(id: String) async throws -> AdminDispatchAppointment {
    let request = Endpoint.adminDispatchConfirm(appointmentId: id).urlRequest(baseURL: baseURL, token: tokenProvider())
    return try await performRequest(request, responseType: DataWrapper<AdminDispatchAppointment>.self).data
}
```

- [ ] **Step 3: Update mock client**

Add storage and methods in `MockAPIClient`:

```swift
var adminDispatchToReturn: AdminDispatchCommandCenter?
var assignedAdminDispatchAppointmentToReturn: AdminDispatchAppointment?
var confirmedAdminDispatchAppointmentToReturn: AdminDispatchAppointment?
var lastAssignedAppointmentId: String?
var lastAssignedTechnicianId: String?

func adminDispatch(date: String?) async throws -> AdminDispatchCommandCenter {
    if let error = errorToThrow { throw error }
    return adminDispatchToReturn!
}

func assignAdminDispatchAppointment(id: String, technicianId: String?) async throws -> AdminDispatchAppointment {
    if let error = errorToThrow { throw error }
    lastAssignedAppointmentId = id
    lastAssignedTechnicianId = technicianId
    return assignedAdminDispatchAppointmentToReturn!
}

func confirmAdminDispatchAppointment(id: String) async throws -> AdminDispatchAppointment {
    if let error = errorToThrow { throw error }
    return confirmedAdminDispatchAppointmentToReturn!
}
```

- [ ] **Step 4: Build/test and commit**

Run:

```bash
cd /Volumes/mac_external/sdgku/DrivewayDetailCo
xcodebuild test -project DrivewayDetailCo.xcodeproj -scheme DrivewayDetailCo -destination 'platform=iOS Simulator,name=iPhone 16'
git add DrivewayDetailCo/Models/AdminDispatch.swift DrivewayDetailCo/Core/Endpoints.swift DrivewayDetailCo/Core/APIClient.swift DrivewayDetailCoTests/TestSupport/StubFactory.swift
git commit -m "feat: add ios admin dispatch api contract"
```

If local Xcode is unavailable, record the exact `xcodebuild` failure and run Swift syntax checks available in the environment.

---

### Task 5: iOS Dispatch View Model

**Files:**
- Create: `/Volumes/mac_external/sdgku/DrivewayDetailCo/DrivewayDetailCo/Features/Admin/AdminDispatchViewModel.swift`
- Test: `/Volumes/mac_external/sdgku/DrivewayDetailCo/DrivewayDetailCoTests/Features/AdminDispatchViewModelTests.swift`

- [ ] **Step 1: Write view-model tests**

Create focused tests:

```swift
import Foundation
import Testing
@testable import DrivewayDetailCo

@Suite("AdminDispatchViewModel", .serialized)
struct AdminDispatchViewModelTests {
    @Test("loads command center state")
    func loadsCommandCenterState() async {
        let api = MockAPIClient()
        api.adminDispatchToReturn = StubFactory.adminDispatchCommandCenter()
        let vm = AdminDispatchViewModel(api: api)

        await vm.load()

        #expect(vm.commandCenter?.metrics.total == 2)
        #expect(vm.assignmentQueue.count == 1)
        #expect(vm.isLoading == false)
    }

    @Test("assign updates matching appointment")
    func assignUpdatesMatchingAppointment() async {
        let api = MockAPIClient()
        api.adminDispatchToReturn = StubFactory.adminDispatchCommandCenter()
        api.assignedAdminDispatchAppointmentToReturn = StubFactory.adminDispatchAppointment(id: "appt-1", technicianId: "tech-2", technicianName: "Ava")
        let vm = AdminDispatchViewModel(api: api)

        await vm.load()
        await vm.assign(appointmentId: "appt-1", technicianId: "tech-2")

        #expect(api.lastAssignedAppointmentId == "appt-1")
        #expect(vm.assignmentQueue.first?.technicianId == "tech-2")
    }

    @Test("confirm updates matching appointment status")
    func confirmUpdatesMatchingAppointmentStatus() async {
        let api = MockAPIClient()
        api.adminDispatchToReturn = StubFactory.adminDispatchCommandCenter()
        api.confirmedAdminDispatchAppointmentToReturn = StubFactory.adminDispatchAppointment(id: "appt-1", status: .confirmed)
        let vm = AdminDispatchViewModel(api: api)

        await vm.load()
        await vm.confirm(appointmentId: "appt-1")

        #expect(vm.assignmentQueue.first?.status == .confirmed)
    }
}
```

- [ ] **Step 2: Implement view model**

Create `AdminDispatchViewModel.swift`:

```swift
import Foundation

@Observable
final class AdminDispatchViewModel {
    private(set) var commandCenter: AdminDispatchCommandCenter?
    private(set) var isLoading = false
    private(set) var isMutating = false
    private(set) var errorMessage: String?

    var selectedDate: Date = Date()

    private let api: APIClientProtocol

    init(api: APIClientProtocol) {
        self.api = api
    }

    var metrics: AdminDispatchMetrics? { commandCenter?.metrics }
    var activeServices: [AdminDispatchAppointment] { commandCenter?.activeServices ?? [] }
    var assignmentQueue: [AdminDispatchAppointment] { commandCenter?.assignmentQueue ?? [] }
    var exceptions: [AdminDispatchException] { commandCenter?.exceptions ?? [] }
    var technicianWorkload: [AdminTechnicianWorkload] { commandCenter?.technicianWorkload ?? [] }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            commandCenter = try await api.adminDispatch(date: isoDate(selectedDate))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func assign(appointmentId: String, technicianId: String?) async {
        await mutateAppointment {
            try await api.assignAdminDispatchAppointment(id: appointmentId, technicianId: technicianId)
        }
    }

    func confirm(appointmentId: String) async {
        await mutateAppointment {
            try await api.confirmAdminDispatchAppointment(id: appointmentId)
        }
    }

    private func mutateAppointment(_ operation: () async throws -> AdminDispatchAppointment) async {
        isMutating = true
        errorMessage = nil
        defer { isMutating = false }

        do {
            let updated = try await operation()
            replace(updated)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func replace(_ updated: AdminDispatchAppointment) {
        guard let current = commandCenter else { return }
        commandCenter = AdminDispatchCommandCenter(
            generatedAt: current.generatedAt,
            date: current.date,
            metrics: current.metrics,
            activeServices: current.activeServices.map { $0.id == updated.id ? updated : $0 },
            assignmentQueue: current.assignmentQueue.map { $0.id == updated.id ? updated : $0 },
            exceptions: current.exceptions,
            technicianWorkload: current.technicianWorkload
        )
    }

    private func isoDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
```

- [ ] **Step 3: Run tests and commit**

Run:

```bash
cd /Volumes/mac_external/sdgku/DrivewayDetailCo
xcodebuild test -project DrivewayDetailCo.xcodeproj -scheme DrivewayDetailCo -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:DrivewayDetailCoTests/AdminDispatchViewModelTests
git add DrivewayDetailCo/Features/Admin/AdminDispatchViewModel.swift DrivewayDetailCoTests/Features/AdminDispatchViewModelTests.swift DrivewayDetailCoTests/TestSupport/StubFactory.swift
git commit -m "feat: add ios admin dispatch view model"
```

---

### Task 6: iOS Native Dispatch UI

**Files:**
- Create: `/Volumes/mac_external/sdgku/DrivewayDetailCo/DrivewayDetailCo/Features/Admin/AdminDispatchComponents.swift`
- Create: `/Volumes/mac_external/sdgku/DrivewayDetailCo/DrivewayDetailCo/Features/Admin/AdminDispatchView.swift`
- Modify: `/Volumes/mac_external/sdgku/DrivewayDetailCo/DrivewayDetailCo/Features/Admin/AdminTabView.swift`

- [ ] **Step 1: Add components**

Create `AdminDispatchComponents.swift` with:

- `AdminDispatchMetricGrid`
- `AdminDispatchAppointmentCard`
- `AdminDispatchExceptionRow`
- `AdminTechnicianWorkloadRow`

Use native SwiftUI, `Label`, SF Symbols, semantic colors, `.regularMaterial`, and compact 8-12pt radius cards consistent with the existing iOS app.

- [ ] **Step 2: Add command-center screen**

Create `AdminDispatchView.swift`:

```swift
import SwiftUI

struct AdminDispatchView: View {
    @State private var viewModel: AdminDispatchViewModel

    init(api: APIClientProtocol) {
        self._viewModel = State(initialValue: AdminDispatchViewModel(api: api))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if viewModel.isLoading && viewModel.commandCenter == nil {
                    ProgressView("Loading dispatch...")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else if let error = viewModel.errorMessage, viewModel.commandCenter == nil {
                    ContentUnavailableView("Dispatch unavailable", systemImage: "exclamationmark.triangle", description: Text(error))
                } else {
                    if let metrics = viewModel.metrics {
                        AdminDispatchMetricGrid(metrics: metrics)
                    }

                    section("Exceptions") {
                        if viewModel.exceptions.isEmpty {
                            Text("No exceptions right now.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(viewModel.exceptions) { exception in
                                AdminDispatchExceptionRow(exception: exception)
                            }
                        }
                    }

                    section("Active Services") {
                        ForEach(viewModel.activeServices) { appointment in
                            AdminDispatchAppointmentCard(appointment: appointment, technicians: viewModel.technicianWorkload, onAssign: { techId in
                                Task { await viewModel.assign(appointmentId: appointment.id, technicianId: techId) }
                            }, onConfirm: {
                                Task { await viewModel.confirm(appointmentId: appointment.id) }
                            })
                        }
                    }

                    section("Assignment Queue") {
                        ForEach(viewModel.assignmentQueue) { appointment in
                            AdminDispatchAppointmentCard(appointment: appointment, technicians: viewModel.technicianWorkload, onAssign: { techId in
                                Task { await viewModel.assign(appointmentId: appointment.id, technicianId: techId) }
                            }, onConfirm: {
                                Task { await viewModel.confirm(appointmentId: appointment.id) }
                            })
                        }
                    }

                    section("Technicians") {
                        ForEach(viewModel.technicianWorkload) { workload in
                            AdminTechnicianWorkloadRow(workload: workload)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Dispatch")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await viewModel.load() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Refresh dispatch")
            }
        }
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content()
        }
    }
}
```

- [ ] **Step 3: Add tab**

Modify `AdminTabView.swift` to insert Dispatch after Dashboard:

```swift
NavigationStack {
    AdminDispatchView(api: env.api)
}
.tabItem {
    Label("Dispatch", systemImage: "dot.radiowaves.left.and.right")
}
.accessibilityIdentifier("admin_tab_dispatch")
```

- [ ] **Step 4: Build and commit**

Run:

```bash
cd /Volumes/mac_external/sdgku/DrivewayDetailCo
xcodebuild test -project DrivewayDetailCo.xcodeproj -scheme DrivewayDetailCo -destination 'platform=iOS Simulator,name=iPhone 16'
git add DrivewayDetailCo/Features/Admin/AdminDispatchComponents.swift DrivewayDetailCo/Features/Admin/AdminDispatchView.swift DrivewayDetailCo/Features/Admin/AdminTabView.swift
git commit -m "feat: add ios admin dispatch command center"
```

---

### Task 7: Verification And Precommit

**Files:**
- No new files unless fixing defects found by verification.

- [ ] **Step 1: Run Phoenix focused tests**

```bash
cd /Volumes/mac_external/Development/Business/MobileCarWash
mix test test/mobile_car_wash_web/controllers/api/v1/admin_dispatch_controller_test.exs test/mobile_car_wash_web/live/admin/dispatch_presenter_test.exs
```

- [ ] **Step 2: Run Phoenix precommit**

```bash
cd /Volumes/mac_external/Development/Business/MobileCarWash
mix precommit
```

- [ ] **Step 3: Run iOS focused/full tests**

```bash
cd /Volumes/mac_external/sdgku/DrivewayDetailCo
xcodebuild test -project DrivewayDetailCo.xcodeproj -scheme DrivewayDetailCo -destination 'platform=iOS Simulator,name=iPhone 16'
```

If `xcodebuild` fails because the active developer directory is Command Line Tools, record:

```text
xcode-select: error: tool 'xcodebuild' requires Xcode, but active developer directory '/Library/Developer/CommandLineTools' is a command line tools instance
```

Then ask the user to switch Xcode with:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

- [ ] **Step 4: Final status**

Run:

```bash
cd /Volumes/mac_external/Development/Business/MobileCarWash && git status --short
cd /Volumes/mac_external/sdgku/DrivewayDetailCo && git status --short
```

Confirm only intentional changes remain. Do not stage, commit, revert, or edit unrelated dirty files.

---

## Self-Review

- Spec coverage: The plan covers command metrics, active services, assignment queue, exceptions, technician workload, assign/unassign, confirm, native iOS UI, and focused tests.
- Intentional omission: Native map context is not included in this first iOS slice because the existing map hook is LiveView/browser-specific and the mobile admin value is same-day triage. A later iOS map task can use MapKit once the command API is stable.
- Placeholder scan: No `TBD`, `TODO`, or vague “add tests” steps remain.
- Type consistency: Swift model and API names are consistent across endpoint, client, mock, view model, and UI steps.
