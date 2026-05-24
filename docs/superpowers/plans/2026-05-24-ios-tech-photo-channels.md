# iOS Technician Photo Channels Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire technician photo channels end-to-end so techs can upload Before, During, and After photos and review Customer problem-area photos from the iOS job flow.

**Architecture:** Phoenix remains the source of truth for photo rows and signed URLs. iOS gets a photo hub view model that loads server photos, groups them by channel, uses the existing multipart upload endpoint, and keeps the offline queue for failed uploads. The UI is connected from tech job detail and checklist while reusing existing photo components where possible.

**Tech Stack:** Phoenix 1.8, Ash resources, ExUnit controller tests, SwiftUI, Swift Testing, existing `APIClient`, existing `PersistentQueue<PendingPhoto>`.

---

## File Map

Backend:

- Modify `lib/mobile_car_wash_web/controllers/api/v1/appointment_photos_controller.ex`
  - Add `index/2`.
  - Allow `photo_type=step_completion`.
  - Accept optional `checklist_item_id`.
  - Keep `before` and `after` car-part validation strict.
- Modify `lib/mobile_car_wash_web/router.ex`
  - Add `GET /api/v1/appointments/:id/photos`.
- Modify `lib/mobile_car_wash/operations/photo.ex`
  - Allow `checklist_item_id` in the `:upload` create action if needed by Ash create params.
- Test `test/mobile_car_wash_web/controllers/api/v1/appointment_photos_controller_test.exs`
  - Cover list endpoint and step-completion upload.

iOS:

- Modify `DrivewayDetailCo/Models/PhotoSummary.swift`
  - Add `PhotoType.stepCompletion`.
  - Add `PhotoChannel`.
  - Make `PhotoUploadRequest.checklistItemId` optional.
- Modify `DrivewayDetailCo/Core/PersistentQueue.swift`
  - Store optional `carPart` and optional `checklistItemId` in `PendingPhoto`.
- Modify `DrivewayDetailCo/Core/Endpoints.swift`
  - Keep `appointmentPhotos` as `GET` by default and add `uploadAppointmentPhoto`.
- Modify `DrivewayDetailCo/Core/APIClient.swift`
  - Add `photos(appointmentId:)`.
  - Upload using the new upload endpoint case and include optional fields.
- Modify `DrivewayDetailCo/Features/Tech/PhotoCaptureViewModel.swift`
  - Load photos.
  - Group by channel and required slot.
  - Compute missing required slots.
  - Upload before/after/during photos.
- Modify `DrivewayDetailCo/Features/Tech/PhotoCaptureView.swift`
  - Replace simple before/after picker with channel tabs.
  - Render grid for Before/After, feed/action for During, read-only Customer.
- Modify `DrivewayDetailCo/Features/Tech/TechAppointmentDetailView.swift`
  - Add navigation route and visible Photos card for on-site/in-progress/completed jobs.
- Modify `DrivewayDetailCo/Features/Tech/ChecklistView.swift`
  - Add a Photos button/pill that opens the same hub.
- Modify `DrivewayDetailCoTests/TestSupport/StubFactory.swift`
  - Add `appointmentPhotosToReturn` and protocol stubs.
- Modify `DrivewayDetailCoTests/Features/Tech/PhotoCaptureViewModelTests.swift`
  - Add focused grouping and missing-slot tests.

---

## Task 1: Backend Photo List and Step Completion Upload

**Files:**
- Modify: `lib/mobile_car_wash_web/controllers/api/v1/appointment_photos_controller.ex`
- Modify: `lib/mobile_car_wash_web/router.ex`
- Test: `test/mobile_car_wash_web/controllers/api/v1/appointment_photos_controller_test.exs`

- [ ] **Step 1: Add controller tests**

Create `test/mobile_car_wash_web/controllers/api/v1/appointment_photos_controller_test.exs` if it does not exist. Include tests with this shape:

```elixir
defmodule MobileCarWashWeb.Api.V1.AppointmentPhotosControllerTest do
  use MobileCarWashWeb.ApiCase

  alias MobileCarWash.Operations.{Photo, PhotoUpload}

  describe "GET /api/v1/appointments/:id/photos" do
    test "returns active photos for the assigned technician", %{conn: conn} do
      {authed, tech} = register_and_sign_in_tech(conn)
      appointment = create_customer_appointment(tech.id, :in_progress)
      {:ok, active} = create_photo(appointment.id, :before, :front)
      {:ok, deleted} = create_photo(appointment.id, :after, :front)
      deleted |> Ash.Changeset.for_update(:soft_delete, %{}) |> Ash.update!(authorize?: false)

      conn = get(authed, ~p"/api/v1/appointments/#{appointment.id}/photos")
      body = json_response(conn, 200)

      assert [%{"id" => id, "photo_type" => "before", "car_part" => "front"}] = body["data"]
      assert id == active.id
    end
  end

  describe "POST /api/v1/appointments/:id/photos" do
    test "accepts step completion photos without a car part", %{conn: conn} do
      {authed, tech} = register_and_sign_in_tech(conn)
      appointment = create_customer_appointment(tech.id, :in_progress)
      upload = %Plug.Upload{path: write_jpeg!(), filename: "step.jpg", content_type: "image/jpeg"}

      conn =
        post(authed, ~p"/api/v1/appointments/#{appointment.id}/photos", %{
          "photo_type" => "step_completion",
          "idempotency_key" => Ecto.UUID.generate(),
          "file" => upload
        })

      body = json_response(conn, 201)
      assert body["data"]["photo_type"] == "step_completion"
      assert body["data"]["car_part"] == nil
    end
  end
end
```

- [ ] **Step 2: Run backend photo tests and verify they fail**

Run:

```bash
mix test test/mobile_car_wash_web/controllers/api/v1/appointment_photos_controller_test.exs
```

Expected: fail because `GET /appointments/:id/photos` is not routed and `step_completion` is rejected.

- [ ] **Step 3: Add route**

In `lib/mobile_car_wash_web/router.ex`, in the native technician checklist/photo flow block:

```elixir
get "/appointments/:id/photos", AppointmentPhotosController, :index
post "/appointments/:id/photos", AppointmentPhotosController, :create
delete "/appointments/:id/photos/:photo_id", AppointmentPhotosController, :delete
```

- [ ] **Step 4: Implement `index/2` and upload validation**

In `AppointmentPhotosController`:

```elixir
@photo_types ~w(before after step_completion)
@required_car_part_photo_types ~w(before after)

def index(conn, %{"id" => appointment_id}) do
  with {:ok, appointment} <- fetch_appointment(conn, appointment_id) do
    photos =
      Photo
      |> Ash.Query.filter(appointment_id == ^appointment.id and is_nil(deleted_at))
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.read!(authorize?: false)
      |> Enum.map(&photo_json/1)

    json(conn, %{data: photos})
  else
    {:error, :not_found} ->
      conn |> put_status(:not_found) |> json(%{error: "not_found"})
  end
end

def create(conn, %{"id" => appointment_id, "file" => %Plug.Upload{} = upload} = params) do
  with {:ok, appointment} <- fetch_appointment(conn, appointment_id),
       {:ok, photo_type} <- atom_param(params["photo_type"], @photo_types),
       {:ok, car_part} <- car_part_param(params["car_part"], params["photo_type"]),
       {:ok, idempotency_key} <- required_string(params["idempotency_key"]),
       :ok <- validate_size(upload.path),
       {:ok, photo} <-
         PhotoUpload.save_file(appointment.id, upload.path, upload.filename, photo_type,
           uploaded_by: :technician,
           car_part: car_part,
           idempotency_key: idempotency_key,
           checklist_item_id: params["checklist_item_id"]
         ) do
    photo_payload = photo_json(photo)
    AppointmentTracker.broadcast_photo(appointment.id, photo.photo_type, photo.car_part, photo_payload)
    conn |> put_status(:created) |> json(%{data: photo_payload})
  else
    {:error, :not_found} -> conn |> put_status(:not_found) |> json(%{error: "not_found"})
    {:error, :too_large} -> conn |> put_status(:request_entity_too_large) |> json(%{error: "file_too_large"})
    {:error, reason} -> conn |> put_status(:unprocessable_entity) |> json(%{error: to_string(reason)})
  end
end

defp car_part_param(value, photo_type) when photo_type in @required_car_part_photo_types do
  atom_param(value, Enum.map(Photo.key_car_parts(), &to_string/1))
end

defp car_part_param(nil, "step_completion"), do: {:ok, nil}
defp car_part_param(value, "step_completion"), do: atom_param(value, Enum.map(Photo.key_car_parts(), &to_string/1))
defp car_part_param(_value, _photo_type), do: {:error, :invalid_param}
```

Update `photo_json/1` to include:

```elixir
caption: photo.caption,
uploaded_by: to_string(photo.uploaded_by),
checklist_item_id: photo.checklist_item_id
```

- [ ] **Step 5: Run backend focused tests**

Run:

```bash
mix format lib/mobile_car_wash_web/controllers/api/v1/appointment_photos_controller.ex lib/mobile_car_wash_web/router.ex test/mobile_car_wash_web/controllers/api/v1/appointment_photos_controller_test.exs
mix test test/mobile_car_wash_web/controllers/api/v1/appointment_photos_controller_test.exs
```

Expected: all tests in that file pass.

---

## Task 2: iOS API and Models

**Files:**
- Modify: `/Volumes/mac_external/sdgku/DrivewayDetailCo/DrivewayDetailCo/Models/PhotoSummary.swift`
- Modify: `/Volumes/mac_external/sdgku/DrivewayDetailCo/DrivewayDetailCo/Core/PersistentQueue.swift`
- Modify: `/Volumes/mac_external/sdgku/DrivewayDetailCo/DrivewayDetailCo/Core/Endpoints.swift`
- Modify: `/Volumes/mac_external/sdgku/DrivewayDetailCo/DrivewayDetailCo/Core/APIClient.swift`
- Modify: `/Volumes/mac_external/sdgku/DrivewayDetailCo/DrivewayDetailCoTests/TestSupport/StubFactory.swift`

- [ ] **Step 1: Update model types**

In `PhotoSummary.swift`, update `PhotoType`, add `PhotoChannel`, and extend request/photo models:

```swift
enum PhotoType: String, Codable, CaseIterable, Equatable, Sendable {
    case before
    case after
    case problemArea = "problem_area"
    case stepCompletion = "step_completion"
}

enum PhotoChannel: String, CaseIterable, Equatable, Sendable {
    case before
    case during
    case after
    case customer

    var title: String {
        switch self {
        case .before: return "Before"
        case .during: return "During"
        case .after: return "After"
        case .customer: return "Customer"
        }
    }

    var photoType: PhotoType {
        switch self {
        case .before: return .before
        case .during: return .stepCompletion
        case .after: return .after
        case .customer: return .problemArea
        }
    }
}

struct AppointmentPhoto: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let appointmentId: String
    let photoType: PhotoType
    let carPart: CarPart?
    let url: URL
    let uploadedAt: Date
    let urlExpiresAt: Date?
    let caption: String?
    let uploadedBy: String?
    let checklistItemId: String?
}

struct PhotoUploadRequest: Equatable, Sendable {
    let photoType: PhotoType
    let carPart: CarPart?
    let checklistItemId: String?
    let idempotencyKey: String
    let fileURL: URL
    let contentType: String
}
```

- [ ] **Step 2: Update pending photo queue**

In `PersistentQueue.swift`, make `carPart` optional and add `checklistItemId`:

```swift
struct PendingPhoto: Codable, Equatable, Sendable {
    let appointmentId: String
    let filePath: String
    let photoType: PhotoType
    let carPart: CarPart?
    let checklistItemId: String?
    let idempotencyKey: String
    let createdAt: Date
}
```

- [ ] **Step 3: Add API protocol and endpoint cases**

In `APIClientProtocol` add:

```swift
func appointmentPhotos(appointmentId: String) async throws -> [AppointmentPhoto]
```

In `Endpoint`, split listing from upload:

```swift
case appointmentPhotos(appointmentId: String)
case uploadAppointmentPhoto(appointmentId: String)
```

Both paths return `/appointments/\(appointmentId)/photos`; method is `GET` for `.appointmentPhotos` and `POST` for `.uploadAppointmentPhoto`.

- [ ] **Step 4: Update multipart upload**

In `APIClient`:

```swift
func appointmentPhotos(appointmentId: String) async throws -> [AppointmentPhoto] {
    let request = Endpoint.appointmentPhotos(appointmentId: appointmentId)
        .urlRequest(baseURL: baseURL, token: tokenProvider())
    return try await performRequest(request, responseType: DataWrapper<[AppointmentPhoto]>.self).data
}

func uploadAppointmentPhoto(appointmentId: String, request upload: PhotoUploadRequest) async throws -> AppointmentPhoto {
    let boundary = "Boundary-\(UUID().uuidString)"
    var request = Endpoint.uploadAppointmentPhoto(appointmentId: appointmentId)
        .urlRequest(baseURL: baseURL, token: tokenProvider())
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    request.httpBody = try makeMultipartBody(upload: upload, boundary: boundary)
    return try await performRequest(request, responseType: DataWrapper<AppointmentPhoto>.self).data
}
```

In `makeMultipartBody`, only append optional fields when present:

```swift
data.appendMultipartField(name: "photo_type", value: upload.photoType.rawValue, boundary: boundary)
if let carPart = upload.carPart {
    data.appendMultipartField(name: "car_part", value: carPart.rawValue, boundary: boundary)
}
if let checklistItemId = upload.checklistItemId {
    data.appendMultipartField(name: "checklist_item_id", value: checklistItemId, boundary: boundary)
}
data.appendMultipartField(name: "idempotency_key", value: upload.idempotencyKey, boundary: boundary)
```

- [ ] **Step 5: Update test stubs and compile**

In `MockAPIClient`, add:

```swift
var appointmentPhotosToReturn: [AppointmentPhoto] = []

func appointmentPhotos(appointmentId: String) async throws -> [AppointmentPhoto] {
    if let error = errorToThrow { throw error }
    return appointmentPhotosToReturn
}
```

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build -project DrivewayDetailCo.xcodeproj -scheme DrivewayDetailCo -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Expected: build succeeds or only existing warnings remain.

---

## Task 3: iOS Photo Hub View Model

**Files:**
- Modify: `/Volumes/mac_external/sdgku/DrivewayDetailCo/DrivewayDetailCo/Features/Tech/PhotoCaptureViewModel.swift`
- Test: `/Volumes/mac_external/sdgku/DrivewayDetailCo/DrivewayDetailCoTests/Features/Tech/PhotoCaptureViewModelTests.swift`

- [ ] **Step 1: Add focused tests**

Add tests for grouping and missing slots:

```swift
@Test("Loads photos and groups required slots")
func loadsPhotosAndGroupsRequiredSlots() async throws {
    let api = MockAPIClient()
    api.appointmentPhotosToReturn = [
        StubFactory.appointmentPhoto(photoType: .before, carPart: .front),
        StubFactory.appointmentPhoto(photoType: .after, carPart: .rear),
        StubFactory.appointmentPhoto(photoType: .problemArea, carPart: .front)
    ]
    let queue = PersistentQueue<PendingPhoto>(key: "photos-\(UUID().uuidString)", defaults: .standard)
    let viewModel = PhotoCaptureViewModel(appointmentId: "appt-1", api: api, queue: queue)

    await viewModel.load()

    #expect(viewModel.photo(for: .front, channel: .before) != nil)
    #expect(viewModel.photo(for: .rear, channel: .after) != nil)
    #expect(viewModel.photos(for: .customer).count == 1)
    #expect(viewModel.missingParts(for: .before).contains(.rear))
}
```

- [ ] **Step 2: Implement view-model state**

In `PhotoCaptureViewModel`, add:

```swift
var selectedChannel: PhotoChannel = .before
private(set) var allPhotos: [AppointmentPhoto] = []

func load() async {
    do {
        allPhotos = try await api.appointmentPhotos(appointmentId: appointmentId)
        rebuildPhotoIndex()
    } catch {
        errorMessage = error.localizedDescription
    }
}

func photos(for channel: PhotoChannel) -> [AppointmentPhoto] {
    allPhotos.filter { $0.photoType == channel.photoType }
}

func photo(for part: CarPart, channel: PhotoChannel? = nil) -> AppointmentPhoto? {
    photos[key((channel ?? selectedChannel).photoType, part)]
}

func missingParts(for channel: PhotoChannel) -> [CarPart] {
    guard channel == .before || channel == .after else { return [] }
    return CarPart.allCases.filter { photo(for: $0, channel: channel) == nil }
}

private func rebuildPhotoIndex() {
    photos = Dictionary(uniqueKeysWithValues: allPhotos.compactMap { photo in
        guard let carPart = photo.carPart else { return nil }
        return (key(photo.photoType, carPart), photo)
    })
}
```

- [ ] **Step 3: Update upload methods**

Change upload to accept channel and optional part:

```swift
func upload(fileURL: URL, channel: PhotoChannel? = nil, carPart: CarPart? = nil, checklistItemId: String? = nil, contentType: String = "image/jpeg") async {
    let channel = channel ?? selectedChannel
    let request = PhotoUploadRequest(
        photoType: channel.photoType,
        carPart: carPart,
        checklistItemId: checklistItemId,
        idempotencyKey: UUID().uuidString,
        fileURL: fileURL,
        contentType: contentType
    )
    ...
}
```

For before/after, callers pass a `carPart`. For during, callers pass `nil` or an optional car part.

- [ ] **Step 4: Run iOS view-model tests**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project DrivewayDetailCo.xcodeproj -scheme DrivewayDetailCo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:DrivewayDetailCoTests/PhotoCaptureViewModelTests
```

Expected: all `PhotoCaptureViewModelTests` pass.

---

## Task 4: iOS Photo Hub UI and Navigation

**Files:**
- Modify: `/Volumes/mac_external/sdgku/DrivewayDetailCo/DrivewayDetailCo/Features/Tech/PhotoCaptureView.swift`
- Modify: `/Volumes/mac_external/sdgku/DrivewayDetailCo/DrivewayDetailCo/Features/Tech/PhotoAreaCard.swift`
- Modify: `/Volumes/mac_external/sdgku/DrivewayDetailCo/DrivewayDetailCo/Features/Tech/TechAppointmentDetailView.swift`
- Modify: `/Volumes/mac_external/sdgku/DrivewayDetailCo/DrivewayDetailCo/Features/Tech/ChecklistView.swift`

- [ ] **Step 1: Update `PhotoCaptureView` initializer**

Support optional checklist context:

```swift
init(
    appointmentId: String,
    activeChecklistItemId: String? = nil,
    api: APIClientProtocol,
    queue: PersistentQueue<PendingPhoto>
) {
    self._viewModel = State(
        initialValue: PhotoCaptureViewModel(
            appointmentId: appointmentId,
            activeChecklistItemId: activeChecklistItemId,
            api: api,
            queue: queue
        )
    )
}
```

- [ ] **Step 2: Replace segmented picker with channel tabs**

Use a segmented picker over `PhotoChannel.allCases`:

```swift
Picker("Photo channel", selection: $viewModel.selectedChannel) {
    ForEach(PhotoChannel.allCases, id: \.self) { channel in
        Text(channel.title).tag(channel)
    }
}
.pickerStyle(.segmented)
```

Render:

- Grid for `.before` and `.after`.
- Capture button and list for `.during`.
- Read-only list for `.customer`.

- [ ] **Step 3: Add photo routes from job detail**

In `TechAppointmentDetailView`, add:

```swift
@State private var photoRoute: TechPhotoRoute?

private struct TechPhotoRoute: Identifiable, Hashable {
    let id: String
}
```

Add a `Photos` card when status is `.onSite`, `.inProgress`, or `.completed`, and navigate:

```swift
.navigationDestination(item: $photoRoute) { route in
    PhotoCaptureView(
        appointmentId: route.id,
        api: viewModel.apiClient,
        queue: viewModel.photoQueueClient
    )
}
```

- [ ] **Step 4: Add photo route from checklist**

Pass the photo queue into `ChecklistView`, add a `Photos` button near the pill, and navigate to:

```swift
PhotoCaptureView(
    appointmentId: checklist.appointmentId,
    activeChecklistItemId: viewModel.activeItem?.id,
    api: viewModel.apiClient,
    queue: viewModel.photoQueueClient
)
```

- [ ] **Step 5: Build and visually check**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build -project DrivewayDetailCo.xcodeproj -scheme DrivewayDetailCo -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Install and open the tech simulator. Confirm the job detail has a Photos card and the hub has all four channels.

---

## Task 5: Verification

**Files:** No new files unless fixing failures.

- [ ] **Step 1: Backend focused tests**

Run:

```bash
mix test test/mobile_car_wash_web/controllers/api/v1/appointment_photos_controller_test.exs test/mobile_car_wash_web/controllers/api/v1/checklists_controller_test.exs test/mobile_car_wash_web/controllers/api/v1/tech_controller_test.exs
```

Expected: `0 failures`.

- [ ] **Step 2: iOS focused tests**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project DrivewayDetailCo.xcodeproj -scheme DrivewayDetailCo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:DrivewayDetailCoTests/PhotoCaptureViewModelTests -only-testing:DrivewayDetailCoTests/TechAppointmentDetailViewModelTests -only-testing:DrivewayDetailCoTests/AppointmentDetailViewModelTests
```

Expected: `TEST SUCCEEDED`.

- [ ] **Step 3: Phoenix precommit**

Run:

```bash
mix precommit
```

Expected: full suite passes. Existing Ash missed-notification warnings are acceptable if the final result is `0 failures`.

- [ ] **Step 4: Simulator smoke test**

Install the iOS app on the tech simulator and verify:

- Schedule shows the in-progress appointment.
- Job detail opens.
- Photos card opens the photo hub.
- Before, During, After, and Customer channels render.
- A required Before or After upload can be attempted, and a network failure queues it rather than crashing.

---

## Self-Review

Spec coverage:

- Backend photo list endpoint: Task 1.
- `step_completion` upload support: Task 1.
- iOS model/API updates: Task 2.
- Photo hub grouping and missing slots: Task 3.
- Tech detail and checklist entry points: Task 4.
- Focused tests and simulator verification: Task 5.

Placeholder scan: no deferred backend support remains; During channel is usable in this plan.

Type consistency: `PhotoChannel`, `PhotoType.stepCompletion`, `PhotoUploadRequest.checklistItemId`, and `AppointmentPhoto.checklistItemId` are named consistently across tasks.
