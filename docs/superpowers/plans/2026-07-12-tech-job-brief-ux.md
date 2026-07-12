# Tech Job Brief UX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn `/tech/appointments/:id` into a single-job command screen with one primary action, prep details, and customer problem photos.

**Architecture:** Keep the existing `MobileCarWashWeb.Tech.JobLive` route and transition events. Add a small view model for the command header, load customer problem photos with existing `Photo`/`PhotoUpload` infrastructure, and reorganize the HEEx into command, prep, and photo regions without changing resources or routes.

**Tech Stack:** Phoenix LiveView, HEEx, Ash resources, ExUnit, Phoenix.LiveViewTest.

## Global Constraints

- Source spec: `docs/superpowers/specs/2026-07-12-tech-job-brief-ux-design.md`.
- Modify `MobileCarWashWeb.Tech.JobLive` only, plus its focused test file.
- Do not add migrations, Ash actions, routes, upload controls, delete controls, lightbox behavior, or checklist behavior.
- Load problem photos with `MobileCarWash.Operations.Photo` and display URLs via `MobileCarWash.Operations.PhotoUpload.apply_url/1`.
- Preserve existing access denial behavior for forbidden/not-found jobs.
- Preserve existing `depart`, `arrive`, and `start_wash` transition behavior.
- Write each behavior test first, run it red, then implement the minimum code to turn it green.
- Use explicit `git add <paths>` only.

---

## File Structure

- Modify: `lib/mobile_car_wash_web/live/tech/job_live.ex`
  - Add aliases for `MobileCarWash.Operations.{Photo, PhotoUpload, Technician}`.
  - Extend the job assign bundle with `:problem_photos`.
  - Add `load_problem_photos/1`.
  - Add `job_command/2`, `customer_contact_label/1`, `notes_text/1`, `problem_photo_label/1`, and `photo_car_part_label/1`.
  - Restructure render markup into `#job-command-card`, `#job-prep-cards`, and `#job-problem-photos`.
- Modify: `test/mobile_car_wash_web/live/tech/job_live_test.exs`
  - Add `Photo` to the Operations aliases.
  - Add `create_problem_photo!/2`.
  - Add focused LiveView tests for problem photos, empty photos, command header states, and prep fallbacks.

---

## Task 1: Problem Photo Loading And Rendering

**Files:**
- Modify: `lib/mobile_car_wash_web/live/tech/job_live.ex`
- Modify: `test/mobile_car_wash_web/live/tech/job_live_test.exs`

**Interfaces:**
- Produces: `load_problem_photos(appointment_id :: Ecto.UUID.t()) :: [MobileCarWash.Operations.Photo.t()]`
- Produces assign: `@problem_photos :: list`
- Produces markup:
  - `#job-problem-photos`
  - `#job-problem-photo-empty`
  - `#job-problem-photo-<photo.id>`
- Consumes existing: `PhotoUpload.apply_url/1`

- [ ] **Step 1: Add failing test helpers**

In `test/mobile_car_wash_web/live/tech/job_live_test.exs`, update the alias:

```elixir
alias MobileCarWash.Operations.{Photo, Procedure, ProcedureStep, Technician}
```

Add this helper below `create_appointment/3`:

```elixir
defp create_problem_photo!(appointment, attrs \\ %{}) do
  defaults = %{
    file_path: "/photos/appointments/#{appointment.id}/problem_area_front.jpg",
    original_filename: "problem_area_front.jpg",
    content_type: "image/jpeg",
    photo_type: :problem_area,
    caption: "Bird droppings on the front bumper",
    uploaded_by: :customer,
    car_part: :front
  }

  Photo
  |> Ash.Changeset.for_create(:upload, Map.merge(defaults, attrs))
  |> Ash.Changeset.force_change_attribute(:appointment_id, appointment.id)
  |> Ash.create!(authorize?: false)
end
```

- [ ] **Step 2: Write failing problem-photo rendering tests**

Add these tests inside `describe "job brief page"`:

```elixir
test "renders customer problem photos with caption and car part", %{
  conn: conn,
  tech: tech,
  customer: customer
} do
  appointment = create_appointment(customer.id, tech.id, :confirmed)
  photo = create_problem_photo!(appointment)

  {:ok, view, html} = live_job(conn, appointment.id)

  assert has_element?(view, "#job-problem-photos")
  assert has_element?(view, "#job-problem-photo-#{photo.id}")
  assert html =~ ~s(src="#{photo.file_path}")
  assert html =~ "Bird droppings on the front bumper"
  assert html =~ "Front"
  refute has_element?(view, "#job-problem-photo-empty")
end

test "renders an empty problem-photo state when the customer uploaded none", %{
  conn: conn,
  tech: tech,
  customer: customer
} do
  appointment = create_appointment(customer.id, tech.id, :confirmed)

  {:ok, view, html} = live_job(conn, appointment.id)

  assert has_element?(view, "#job-problem-photos")
  assert has_element?(view, "#job-problem-photo-empty")
  assert html =~ "No customer problem photos"
end
```

- [ ] **Step 3: Run tests and verify red**

Run:

```bash
mix test test/mobile_car_wash_web/live/tech/job_live_test.exs
```

Expected: the new tests fail because `#job-problem-photos` and `#job-problem-photo-empty` do not exist.

- [ ] **Step 4: Implement problem-photo data loading**

In `lib/mobile_car_wash_web/live/tech/job_live.ex`, replace the Operations alias:

```elixir
alias MobileCarWash.Operations.{Photo, PhotoUpload, Technician}
```

In `load_job/2`, add `problem_photos: load_problem_photos(appointment.id)`:

```elixir
{:ok,
 %{
   appointment: appointment,
   tech_record: tech_record,
   customer: customer,
   service: service,
   address: address,
   vehicle: vehicle,
   progress: Dispatch.checklist_progress(appointment.id),
   problem_photos: load_problem_photos(appointment.id)
 }}
```

In `assign_job/2`, add:

```elixir
problem_photos: job.problem_photos
```

Add these helpers near the existing formatting helpers:

```elixir
defp load_problem_photos(appointment_id) do
  Photo
  |> Ash.Query.filter(
    appointment_id == ^appointment_id and photo_type == :problem_area and is_nil(deleted_at)
  )
  |> Ash.Query.sort(inserted_at: :asc)
  |> Ash.read!(authorize?: false)
  |> Enum.map(&PhotoUpload.apply_url/1)
end

defp problem_photo_label(%{caption: caption}) when is_binary(caption) do
  case String.trim(caption) do
    "" -> "Customer problem photo"
    value -> value
  end
end

defp problem_photo_label(_photo), do: "Customer problem photo"

defp photo_car_part_label(nil), do: "Problem area"

defp photo_car_part_label(part) do
  part
  |> to_string()
  |> String.replace("_", " ")
  |> String.split(" ")
  |> Enum.map_join(" ", &String.capitalize/1)
end
```

- [ ] **Step 5: Implement problem-photo markup**

In the `render/1` HEEx, add this section below the existing details/action grid for now:

```heex
<section
  id="job-problem-photos"
  class="border-t border-base-300 px-5 py-5 sm:px-6"
>
  <div class="flex items-center justify-between gap-3">
    <div>
      <h2 class="text-sm font-semibold uppercase tracking-[0.18em] text-base-content/50">
        Customer problem photos
      </h2>
      <p class="mt-1 text-sm text-base-content/70">
        Review these before starting the wash.
      </p>
    </div>
    <span class="badge badge-ghost">{length(@problem_photos)}</span>
  </div>

  <div
    :if={@problem_photos == []}
    id="job-problem-photo-empty"
    class="mt-4 rounded-xl border border-dashed border-base-300 bg-base-200/50 px-4 py-5 text-sm text-base-content/70"
  >
    No customer problem photos.
  </div>

  <div :if={@problem_photos != []} class="mt-4 grid grid-cols-2 gap-3 sm:grid-cols-3">
    <figure
      :for={photo <- @problem_photos}
      id={"job-problem-photo-#{photo.id}"}
      class="overflow-hidden rounded-xl border border-base-300 bg-base-100"
    >
      <img
        src={photo.file_path}
        alt={problem_photo_label(photo)}
        class="aspect-square w-full object-cover"
      />
      <figcaption class="space-y-1 px-3 py-2">
        <p class="text-xs font-semibold text-base-content">
          {photo_car_part_label(photo.car_part)}
        </p>
        <p class="line-clamp-2 text-xs text-base-content/70">
          {problem_photo_label(photo)}
        </p>
      </figcaption>
    </figure>
  </div>
</section>
```

- [ ] **Step 6: Run tests and verify green**

Run:

```bash
mix test test/mobile_car_wash_web/live/tech/job_live_test.exs
```

Expected: all `job_live_test.exs` tests pass.

- [ ] **Step 7: Commit Task 1**

```bash
git add lib/mobile_car_wash_web/live/tech/job_live.ex test/mobile_car_wash_web/live/tech/job_live_test.exs
git commit -m "Add problem photos to tech job brief"
```

---

## Task 2: Command Header View Model And Single Primary Action

**Files:**
- Modify: `lib/mobile_car_wash_web/live/tech/job_live.ex`
- Modify: `test/mobile_car_wash_web/live/tech/job_live_test.exs`

**Interfaces:**
- Produces: `job_command(status :: atom, progress :: map) :: map`
- Produced command map keys:
  - `:title`
  - `:body`
  - `:kind`
  - `:action`
- Produced action map keys for event actions:
  - `:type`, value `:event`
  - `:event`
  - `:id`
  - `:label`
- Produced action map keys for links:
  - `:type`, value `:link`
  - `:to`
  - `:id`
  - `:label`
- Produced markup:
  - `#job-command-card`
  - `#job-primary-action`
  - `#job-primary-waiting`

- [ ] **Step 1: Write failing command-header tests**

Add these tests inside `describe "job brief page"`:

```elixir
test "confirmed job renders one command header head-out action", %{
  conn: conn,
  tech: tech,
  customer: customer
} do
  appointment = create_appointment(customer.id, tech.id, :confirmed)

  {:ok, view, html} = live_job(conn, appointment.id)

  assert has_element?(view, "#job-command-card")
  assert has_element?(view, "#job-head-out[data-role='job-primary-action']", "Head out")
  assert html =~ "Leave for this service stop"
  assert length(Floki.find(html, "#job-head-out")) == 1
end

test "en-route job renders one command header arrived action", %{
  conn: conn,
  tech: tech,
  customer: customer
} do
  appointment = create_appointment(customer.id, tech.id, :en_route)

  {:ok, view, html} = live_job(conn, appointment.id)

  assert has_element?(view, "#job-arrived[data-role='job-primary-action']", "Arrived")
  assert html =~ "Mark yourself on site"
  assert length(Floki.find(html, "#job-arrived")) == 1
end

test "on-site job renders one command header start-wash action", %{
  conn: conn,
  tech: tech,
  customer: customer
} do
  appointment = create_appointment(customer.id, tech.id, :on_site)

  {:ok, view, html} = live_job(conn, appointment.id)

  assert has_element?(view, "#job-start-wash[data-role='job-primary-action']", "Start wash")
  assert html =~ "Start the wash"
  assert length(Floki.find(html, "#job-start-wash")) == 1
end
```

- [ ] **Step 2: Add failing checklist and waiting-state tests**

Add this helper below `create_procedure_for_service/1`:

```elixir
defp create_checklist_progress!(appointment) do
  procedure = create_procedure_for_service(appointment.service_type_id)

  {:ok, checklist} =
    MobileCarWash.Operations.AppointmentChecklist
    |> Ash.Changeset.for_create(:create, %{
      status: :in_progress,
      total_estimated_minutes: 10
    })
    |> Ash.Changeset.force_change_attribute(:appointment_id, appointment.id)
    |> Ash.Changeset.force_change_attribute(:procedure_id, procedure.id)
    |> Ash.create()

  appointment
  |> Ash.Changeset.for_update(:update, %{})
  |> Ash.Changeset.force_change_attribute(:status, :in_progress)
  |> Ash.Changeset.force_change_attribute(:checklist_id, checklist.id)
  |> Ash.update!(authorize?: false)

  checklist
end
```

Add these tests:

```elixir
test "in-progress job renders one command header checklist link", %{
  conn: conn,
  tech: tech,
  customer: customer
} do
  appointment = create_appointment(customer.id, tech.id, :on_site)
  checklist = create_checklist_progress!(appointment)

  {:ok, view, html} = live_job(conn, appointment.id)

  assert has_element?(
           view,
           "#job-open-checklist[data-role='job-primary-action'][href='/tech/checklist/#{checklist.id}']",
           "Continue checklist"
         )

  assert html =~ "Continue the active wash checklist"
  assert length(Floki.find(html, "#job-open-checklist")) == 1
end

test "pending job renders a non-clickable command state", %{
  conn: conn,
  tech: tech,
  customer: customer
} do
  appointment = create_appointment(customer.id, tech.id, :pending)

  {:ok, view, html} = live_job(conn, appointment.id)

  assert has_element?(view, "#job-primary-waiting")
  assert html =~ "Waiting on dispatch"
  refute has_element?(view, "[data-role='job-primary-action']")
end
```

- [ ] **Step 3: Run tests and verify red**

Run:

```bash
mix test test/mobile_car_wash_web/live/tech/job_live_test.exs
```

Expected: the new tests fail because `#job-command-card` and `#job-primary-action` do not exist, and action buttons still live only in the lower action card.

- [ ] **Step 4: Implement `job_command/2`**

Add these helpers near `next_step_label/2`:

```elixir
defp job_command(_status, %{checklist_id: checklist_id})
     when not is_nil(checklist_id) do
  %{
    title: "Wash in progress",
    body: "Continue the active wash checklist.",
    kind: :active,
    action: %{
      type: :link,
      id: "job-open-checklist",
      to: ~p"/tech/checklist/#{checklist_id}",
      label: "Continue checklist"
    }
  }
end

defp job_command(:confirmed, %{steps_total: 0}) do
  %{
    title: "Leave for this service stop",
    body: "Head out when you are ready to travel to the customer.",
    kind: :ready,
    action: %{type: :event, id: "job-head-out", event: "depart", label: "Head out"}
  }
end

defp job_command(:en_route, %{steps_total: 0}) do
  %{
    title: "You are en route",
    body: "Mark yourself on site when you arrive.",
    kind: :travel,
    action: %{type: :event, id: "job-arrived", event: "arrive", label: "Arrived"}
  }
end

defp job_command(:on_site, %{steps_total: 0}) do
  %{
    title: "You are on site",
    body: "Start the wash when you are ready.",
    kind: :onsite,
    action: %{type: :event, id: "job-start-wash", event: "start_wash", label: "Start wash"}
  }
end

defp job_command(:pending, _progress) do
  %{
    title: "Waiting on dispatch",
    body: "This appointment is not ready for field action yet.",
    kind: :waiting,
    action: nil
  }
end

defp job_command(:completed, _progress) do
  %{
    title: "Completed stop",
    body: "Review the completed service details.",
    kind: :done,
    action: nil
  }
end

defp job_command(:cancelled, _progress) do
  %{
    title: "Cancelled stop",
    body: "No field action is available for this appointment.",
    kind: :waiting,
    action: nil
  }
end

defp job_command(_status, _progress) do
  %{
    title: "Review appointment",
    body: "Review the appointment details before taking action.",
    kind: :review,
    action: nil
  }
end
```

In `assign_job/2`, add:

```elixir
command: job_command(job.appointment.status, job.progress)
```

- [ ] **Step 5: Move the primary action into command header**

Replace the current top header's "Next step" box with this command card:

```heex
<div
  id="job-command-card"
  class="rounded-xl border border-base-300 bg-base-100 px-4 py-4 text-sm shadow-sm sm:min-w-72"
>
  <p class="text-xs font-semibold uppercase tracking-[0.16em] text-base-content/45">
    Next action
  </p>
  <p class="mt-2 text-base font-semibold text-base-content">{@command.title}</p>
  <p class="mt-1 text-sm leading-6 text-base-content/70">{@command.body}</p>

  <button
    :if={@command.action && @command.action.type == :event}
    id={@command.action.id}
    data-role="job-primary-action"
    phx-click={@command.action.event}
    class="btn btn-primary mt-4 w-full"
  >
    {@command.action.label}
  </button>

  <.link
    :if={@command.action && @command.action.type == :link}
    id={@command.action.id}
    data-role="job-primary-action"
    navigate={@command.action.to}
    class="btn btn-primary mt-4 w-full"
  >
    {@command.action.label}
  </.link>

  <div
    :if={is_nil(@command.action)}
    id="job-primary-waiting"
    class="mt-4 rounded-lg border border-dashed border-base-300 bg-base-200/50 px-3 py-2 text-sm text-base-content/70"
  >
    No field action available.
  </div>
</div>
```

The tests intentionally assert `data-role="job-primary-action"` so each primary control can keep its existing stable id while also proving it is rendered in the command header.

- [ ] **Step 6: Remove duplicate lower primary controls**

In the lower action section, remove the button/link block that renders `#job-head-out`, `#job-arrived`, `#job-start-wash`, and `#job-open-checklist`. Keep the checklist progress display and the waiting/review copy. This ensures each primary action id appears exactly once.

- [ ] **Step 7: Run tests and verify green**

Run:

```bash
mix test test/mobile_car_wash_web/live/tech/job_live_test.exs
```

Expected: all `job_live_test.exs` tests pass.

- [ ] **Step 8: Commit Task 2**

```bash
git add lib/mobile_car_wash_web/live/tech/job_live.ex test/mobile_car_wash_web/live/tech/job_live_test.exs
git commit -m "Promote job brief primary action"
```

---

## Task 3: Prep Cards, Empty Notes, And Final Layout Polish

**Files:**
- Modify: `lib/mobile_car_wash_web/live/tech/job_live.ex`
- Modify: `test/mobile_car_wash_web/live/tech/job_live_test.exs`

**Interfaces:**
- Produces: `customer_contact_label(customer :: map) :: String.t()`
- Produces: `notes_text(appointment :: map) :: String.t()`
- Produced markup:
  - `#job-prep-cards`
  - `#job-service-card`
  - `#job-vehicle-card`
  - `#job-address-card`
  - `#job-customer-card`
  - `#job-notes-card`

- [ ] **Step 1: Write failing prep-card tests**

Add this helper below `create_appointment/3`:

```elixir
defp with_notes(appointment, notes) do
  appointment
  |> Ash.Changeset.for_update(:update, %{})
  |> Ash.Changeset.force_change_attribute(:notes, notes)
  |> Ash.update!(authorize?: false)
end
```

Add these tests:

```elixir
test "renders prep cards for service vehicle address customer and notes", %{
  conn: conn,
  tech: tech,
  customer: customer
} do
  appointment =
    customer.id
    |> create_appointment(tech.id, :confirmed)
    |> with_notes("Customer asked us to focus on the front bumper.")

  {:ok, view, html} = live_job(conn, appointment.id)

  assert has_element?(view, "#job-prep-cards")
  assert has_element?(view, "#job-service-card")
  assert has_element?(view, "#job-vehicle-card")
  assert has_element?(view, "#job-address-card")
  assert has_element?(view, "#job-customer-card")
  assert has_element?(view, "#job-notes-card")
  assert html =~ "Job Wash"
  assert html =~ "Toyota"
  assert html =~ "100 Job Ave"
  assert html =~ customer.phone
  assert html =~ "Customer asked us to focus on the front bumper."
end

test "renders a calm notes fallback when the appointment has no notes", %{
  conn: conn,
  tech: tech,
  customer: customer
} do
  appointment = create_appointment(customer.id, tech.id, :confirmed)

  {:ok, view, html} = live_job(conn, appointment.id)

  assert has_element?(view, "#job-notes-card")
  assert html =~ "No appointment notes"
end
```

- [ ] **Step 2: Run tests and verify red**

Run:

```bash
mix test test/mobile_car_wash_web/live/tech/job_live_test.exs
```

Expected: the new tests fail because `#job-prep-cards` and the named prep cards do not exist.

- [ ] **Step 3: Implement contact and notes helpers**

Add these helpers near `vehicle_label/1`:

```elixir
defp customer_contact_label(%{phone: phone}) when is_binary(phone) do
  case String.trim(phone) do
    "" -> "No phone on file"
    value -> value
  end
end

defp customer_contact_label(_customer), do: "No phone on file"

defp notes_text(%{notes: notes}) when is_binary(notes) do
  case String.trim(notes) do
    "" -> "No appointment notes"
    value -> value
  end
end

defp notes_text(_appointment), do: "No appointment notes"
```

- [ ] **Step 4: Replace service-stop/action grid with prep cards**

Replace the existing `lg:grid-cols-[1.15fr_0.85fr]` section with this structure:

```heex
<section id="job-prep-cards" class="grid gap-3 px-5 py-5 sm:px-6 lg:grid-cols-2">
  <article id="job-service-card" class="rounded-xl border border-base-300 bg-base-100 p-4 shadow-sm">
    <p class="text-xs font-semibold uppercase tracking-[0.16em] text-base-content/45">
      Service
    </p>
    <p class="mt-2 text-sm font-semibold text-base-content">{@service.name}</p>
    <p class="mt-1 text-sm text-base-content/70">
      {Calendar.strftime(@appointment.scheduled_at, "%b %d · %I:%M %p")}
    </p>
  </article>

  <article id="job-vehicle-card" class="rounded-xl border border-base-300 bg-base-100 p-4 shadow-sm">
    <p class="text-xs font-semibold uppercase tracking-[0.16em] text-base-content/45">
      Vehicle
    </p>
    <p class="mt-2 text-sm font-semibold text-base-content">{vehicle_label(@vehicle)}</p>
  </article>

  <article id="job-address-card" class="rounded-xl border border-base-300 bg-base-100 p-4 shadow-sm">
    <p class="text-xs font-semibold uppercase tracking-[0.16em] text-base-content/45">
      Address
    </p>
    <a
      href={maps_url(@address)}
      target="_blank"
      rel="noopener"
      class="mt-2 inline-flex items-start gap-2 text-sm font-semibold text-primary transition hover:text-primary/80"
    >
      <.icon name="hero-map-pin" class="mt-0.5 h-4 w-4 shrink-0" />
      <span>{@address.street}, {@address.city}, {@address.state} {@address.zip}</span>
    </a>
  </article>

  <article id="job-customer-card" class="rounded-xl border border-base-300 bg-base-100 p-4 shadow-sm">
    <p class="text-xs font-semibold uppercase tracking-[0.16em] text-base-content/45">
      Customer
    </p>
    <p class="mt-2 text-sm font-semibold text-base-content">{@customer.name}</p>
    <p class="mt-1 text-sm text-base-content/70">{customer_contact_label(@customer)}</p>
  </article>

  <article
    id="job-notes-card"
    class="rounded-xl border border-base-300 bg-base-100 p-4 shadow-sm lg:col-span-2"
  >
    <p class="text-xs font-semibold uppercase tracking-[0.16em] text-base-content/45">
      Appointment notes
    </p>
    <p class="mt-2 text-sm leading-6 text-base-content/80">{notes_text(@appointment)}</p>
  </article>
</section>
```

- [ ] **Step 5: Keep checklist progress as support only**

If checklist progress was removed with the old action card, add this compact support block below the command card when `@progress.steps_total > 0`:

```heex
<div :if={@progress.steps_total > 0} class="mt-4 space-y-2">
  <div class="flex items-center justify-between text-sm text-base-content/70">
    <span>Checklist progress</span>
    <span>{@progress.steps_done}/{@progress.steps_total}</span>
  </div>
  <progress
    class="progress progress-primary h-2 w-full"
    value={@progress.steps_done}
    max={@progress.steps_total}
  />
</div>
```

- [ ] **Step 6: Run focused tests**

Run:

```bash
mix test test/mobile_car_wash_web/live/tech/job_live_test.exs
```

Expected: all `job_live_test.exs` tests pass.

- [ ] **Step 7: Run adjacent tests**

Run:

```bash
mix test test/mobile_car_wash_web/live/tech/tech_dashboard_live_test.exs test/mobile_car_wash_web/live/checklist_live_test.exs
```

Expected: all adjacent tech dashboard and checklist tests pass.

- [ ] **Step 8: Run formatter check**

Run:

```bash
mix format --check-formatted lib/mobile_car_wash_web/live/tech/job_live.ex test/mobile_car_wash_web/live/tech/job_live_test.exs
```

Expected: exit code `0`.

- [ ] **Step 9: Commit Task 3**

```bash
git add lib/mobile_car_wash_web/live/tech/job_live.ex test/mobile_car_wash_web/live/tech/job_live_test.exs
git commit -m "Polish tech job brief prep layout"
```

---

## Final Verification

- [ ] Run focused tests:

```bash
mix test test/mobile_car_wash_web/live/tech/job_live_test.exs
```

- [ ] Run adjacent tests:

```bash
mix test test/mobile_car_wash_web/live/tech/tech_dashboard_live_test.exs test/mobile_car_wash_web/live/checklist_live_test.exs
```

- [ ] Run full precommit:

```bash
mix precommit
```

- [ ] Confirm clean branch state:

```bash
git status --short --branch
```

---

## Self-Review Notes

- Spec coverage: Task 1 covers problem photos and empty photo state. Task 2 covers the single primary next action and waiting states. Task 3 covers prep details, contact, notes, layout, and adjacent verification.
- Red-flag scan: no deferred code, vague test names, or unspecified validation steps remain.
- Type consistency: all new helpers are private `Tech.JobLive` helpers and are consumed only by `render/1` or `load_job/2`.
