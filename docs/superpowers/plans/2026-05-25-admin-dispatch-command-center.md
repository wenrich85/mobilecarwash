# Admin Dispatch Command Center Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign `/admin/dispatch` into a live operations command center focused on active service monitoring, exceptions, and fast technician assignment.

**Architecture:** Keep the existing `MobileCarWashWeb.Admin.DispatchLive` route and data loading. Add a small presenter module for derived dispatch state so the LiveView stays readable, then replace the current page layout with focused function components in `DispatchComponents`.

**Tech Stack:** Phoenix LiveView, HEEx function components, Tailwind CSS v4/daisyUI tokens, Ash resources, existing `DispatchMap` hook, ExUnit/Phoenix LiveView tests.

---

## File Structure

- Create `lib/mobile_car_wash_web/live/admin/dispatch_presenter.ex`
  - Pure helpers for metrics, active service summaries, assignment queue, technician workload, and exception derivation.
- Modify `lib/mobile_car_wash_web/live/admin/dispatch_live.ex`
  - Assign derived presenter data in `load_appointments/1`.
  - Replace the current header/filter/map/active/kanban render order with the command center layout.
  - Preserve existing subscriptions, refresh behavior, map hook, filters, assignment, confirm, and technician-management events.
- Modify `lib/mobile_car_wash_web/live/admin/components/dispatch_components.ex`
  - Add command center components.
  - Keep existing `appointment_card/1`, `active_wash_card/1`, and `kanban_column/1` available while the new layout adopts the new components.
- Create `test/mobile_car_wash_web/live/admin/dispatch_presenter_test.exs`
  - Focused pure tests for derived state.
- Modify `test/mobile_car_wash_web/live/admin/dispatch_live_kanban_test.exs`
  - Add lightweight checks that the redesigned screen exposes stable command-center DOM sections.
- Create `test/mobile_car_wash_web/live/admin/dispatch_live_command_center_test.exs`
  - Authenticated LiveView smoke test for command-center regions.
- Run existing dispatch tests and `mix precommit`.

---

### Task 1: Presenter Module Skeleton And Metrics

**Files:**
- Create: `lib/mobile_car_wash_web/live/admin/dispatch_presenter.ex`
- Create: `test/mobile_car_wash_web/live/admin/dispatch_presenter_test.exs`

- [ ] **Step 1: Add focused presenter tests**

Create `test/mobile_car_wash_web/live/admin/dispatch_presenter_test.exs`:

```elixir
defmodule MobileCarWashWeb.Admin.DispatchPresenterTest do
  use ExUnit.Case, async: true

  alias MobileCarWashWeb.Admin.DispatchPresenter

  defp appointment(attrs) do
    Map.merge(
      %{
        id: "appt-1",
        status: :pending,
        technician_id: nil,
        customer_id: "cust-1",
        service_type_id: "svc-1",
        scheduled_at: ~U[2026-05-25 15:00:00Z]
      },
      attrs
    )
  end

  test "metrics summarize live dispatch state" do
    appointments = [
      appointment(%{id: "pending", status: :pending}),
      appointment(%{id: "confirmed", status: :confirmed, technician_id: "tech-1"}),
      appointment(%{id: "active", status: :in_progress, technician_id: "tech-2"}),
      appointment(%{id: "done", status: :completed, technician_id: "tech-3"})
    ]

    technicians = [
      %{id: "tech-1", active: true, status: :available},
      %{id: "tech-2", active: true, status: :on_break},
      %{id: "tech-3", active: false, status: :off_duty}
    ]

    assert DispatchPresenter.metrics(appointments, technicians, []) == %{
             total: 4,
             in_progress: 1,
             ready_to_assign: 1,
             completed: 1,
             on_duty: 1,
             exceptions: 0
           }
  end

  test "assignment_queue returns pending and confirmed jobs sorted by schedule" do
    later = appointment(%{id: "later", status: :pending, scheduled_at: ~U[2026-05-25 17:00:00Z]})
    sooner = appointment(%{id: "sooner", status: :confirmed, scheduled_at: ~U[2026-05-25 14:00:00Z]})
    complete = appointment(%{id: "complete", status: :completed, scheduled_at: ~U[2026-05-25 13:00:00Z]})

    assert [%{id: "sooner"}, %{id: "later"}] =
             DispatchPresenter.assignment_queue([later, sooner, complete])
  end
end
```

- [ ] **Step 2: Run the presenter tests and verify they fail**

Run:

```bash
mix test test/mobile_car_wash_web/live/admin/dispatch_presenter_test.exs
```

Expected: compile failure because `MobileCarWashWeb.Admin.DispatchPresenter` does not exist.

- [ ] **Step 3: Add the presenter module**

Create `lib/mobile_car_wash_web/live/admin/dispatch_presenter.ex`:

```elixir
defmodule MobileCarWashWeb.Admin.DispatchPresenter do
  @moduledoc """
  Pure presentation helpers for the admin dispatch command center.

  Keep DB access in DispatchLive. This module only derives display state
  from appointments, technicians, progress maps, photos, and flags that
  the LiveView has already loaded.
  """

  @active_statuses [:en_route, :on_site, :in_progress]
  @assignment_statuses [:pending, :confirmed]

  def metrics(appointments, technicians, exceptions) do
    %{
      total: length(appointments),
      in_progress: Enum.count(appointments, &(&1.status in @active_statuses)),
      ready_to_assign: Enum.count(appointments, &ready_to_assign?/1),
      completed: Enum.count(appointments, &(&1.status == :completed)),
      on_duty: Enum.count(technicians, &on_duty?/1),
      exceptions: length(exceptions)
    }
  end

  def assignment_queue(appointments) do
    appointments
    |> Enum.filter(&(&1.status in @assignment_statuses))
    |> Enum.sort_by(& &1.scheduled_at, DateTime)
  end

  def active_appointments(appointments) do
    appointments
    |> Enum.filter(&(&1.status in @active_statuses))
    |> Enum.sort_by(& &1.scheduled_at, DateTime)
  end

  defp ready_to_assign?(appointment) do
    appointment.status in @assignment_statuses and is_nil(appointment.technician_id)
  end

  defp on_duty?(%{active: true, status: status}), do: status in [:available, :on_break]
  defp on_duty?(_), do: false
end
```

- [ ] **Step 4: Run presenter tests and verify they pass**

Run:

```bash
mix test test/mobile_car_wash_web/live/admin/dispatch_presenter_test.exs
```

Expected: `2 tests, 0 failures`.

- [ ] **Step 5: Commit Task 1**

```bash
git add lib/mobile_car_wash_web/live/admin/dispatch_presenter.ex test/mobile_car_wash_web/live/admin/dispatch_presenter_test.exs
git commit -m "feat: add dispatch command presenter"
```

---

### Task 2: Exceptions And Workload Derivation

**Files:**
- Modify: `lib/mobile_car_wash_web/live/admin/dispatch_presenter.ex`
- Modify: `test/mobile_car_wash_web/live/admin/dispatch_presenter_test.exs`

- [ ] **Step 1: Add tests for exception and workload summaries**

Append inside the existing `describe`-free test module:

```elixir
test "exceptions include unassigned pending jobs and flagged customers" do
  unassigned = appointment(%{id: "unassigned", status: :pending, technician_id: nil})
  flagged = appointment(%{id: "flagged", status: :confirmed, technician_id: "tech-1", customer_id: "cust-flag"})

  exceptions =
    DispatchPresenter.exceptions([unassigned, flagged],
      flagged_customer_ids: MapSet.new(["cust-flag"]),
      tech_requests: %{},
      progress_by_appointment: %{},
      photo_counts_by_appointment: %{}
    )

  assert Enum.any?(exceptions, &(&1.appointment_id == "unassigned" and &1.kind == :unassigned))
  assert Enum.any?(exceptions, &(&1.appointment_id == "flagged" and &1.kind == :booking_flag))
end

test "technician_workload marks current activity and assignment counts" do
  techs = [
    %{id: "tech-1", name: "Ava", active: true, status: :available, zone: :north},
    %{id: "tech-2", name: "Noah", active: true, status: :on_break, zone: nil}
  ]

  appointments = [
    appointment(%{id: "a1", status: :confirmed, technician_id: "tech-1"}),
    appointment(%{id: "a2", status: :in_progress, technician_id: "tech-1"}),
    appointment(%{id: "a3", status: :confirmed, technician_id: "tech-2"})
  ]

  workloads = DispatchPresenter.technician_workload(techs, appointments, %{"tech-1" => %{status: :in_progress}})

  assert [%{id: "tech-1", assigned_count: 2, active?: true}, %{id: "tech-2", assigned_count: 1}] = workloads
end
```

- [ ] **Step 2: Run the presenter tests and verify new failures**

Run:

```bash
mix test test/mobile_car_wash_web/live/admin/dispatch_presenter_test.exs
```

Expected: failures for missing `exceptions/2` and `technician_workload/3`.

- [ ] **Step 3: Implement exception and workload helpers**

Add these functions to `DispatchPresenter`:

```elixir
def exceptions(appointments, opts) do
  flagged_customer_ids = Keyword.fetch!(opts, :flagged_customer_ids)
  tech_requests = Keyword.fetch!(opts, :tech_requests)
  progress_by_appointment = Keyword.fetch!(opts, :progress_by_appointment)
  photo_counts_by_appointment = Keyword.fetch!(opts, :photo_counts_by_appointment)

  appointments
  |> Enum.flat_map(fn appointment ->
    []
    |> maybe_add_unassigned(appointment)
    |> maybe_add_unconfirmed(appointment)
    |> maybe_add_booking_flag(appointment, flagged_customer_ids)
    |> maybe_add_tech_request(appointment, tech_requests)
    |> maybe_add_stalled_checklist(appointment, progress_by_appointment)
    |> maybe_add_missing_required_photos(appointment, photo_counts_by_appointment)
  end)
  |> Enum.sort_by(&{severity_order(&1.severity), &1.scheduled_at}, DateTime)
end

def technician_workload(technicians, appointments, current_appointment_by_tech) do
  Enum.map(technicians, fn tech ->
    assigned = Enum.filter(appointments, &(&1.technician_id == tech.id and &1.status != :completed))
    current = Map.get(current_appointment_by_tech, tech.id)

    %{
      id: tech.id,
      name: tech.name,
      status: tech.status,
      zone: Map.get(tech, :zone),
      assigned_count: length(assigned),
      active?: not is_nil(current),
      current: current,
      pressure: workload_pressure(length(assigned), current)
    }
  end)
end

def progress_by_appointment(active) do
  Map.new(active, fn {appointment, progress} -> {appointment.id, progress} end)
end

defp maybe_add_unassigned(exceptions, %{status: status, technician_id: nil} = appointment)
     when status in [:pending, :confirmed] do
  [exception(appointment, :unassigned, :high, "Needs technician", "Assign a technician") | exceptions]
end

defp maybe_add_unassigned(exceptions, _appointment), do: exceptions

defp maybe_add_unconfirmed(exceptions, %{status: :pending, technician_id: tech_id} = appointment)
     when not is_nil(tech_id) do
  [exception(appointment, :unconfirmed, :medium, "Assigned but not confirmed", "Confirm appointment") | exceptions]
end

defp maybe_add_unconfirmed(exceptions, _appointment), do: exceptions

defp maybe_add_booking_flag(exceptions, appointment, flagged_customer_ids) do
  if MapSet.member?(flagged_customer_ids, appointment.customer_id) do
    [exception(appointment, :booking_flag, :high, "Customer booking flag", "Review customer record") | exceptions]
  else
    exceptions
  end
end

defp maybe_add_tech_request(exceptions, appointment, tech_requests) do
  if Map.has_key?(tech_requests, appointment.id) do
    [exception(appointment, :tech_request, :medium, "Technician requested this job", "Review request") | exceptions]
  else
    exceptions
  end
end

defp maybe_add_stalled_checklist(exceptions, %{status: :in_progress} = appointment, progress_by_appointment) do
  progress = Map.get(progress_by_appointment, appointment.id)

  if progress && progress.steps_total > 0 && progress.steps_done == 0 do
    [exception(appointment, :stalled_checklist, :medium, "Checklist has not advanced", "Check service progress") | exceptions]
  else
    exceptions
  end
end

defp maybe_add_stalled_checklist(exceptions, _appointment, _progress_by_appointment), do: exceptions

defp maybe_add_missing_required_photos(exceptions, %{status: :in_progress} = appointment, photo_counts_by_appointment) do
  counts = Map.get(photo_counts_by_appointment, appointment.id, %{before: 0, after: 0})

  if Map.get(counts, :before, 0) == 0 do
    [exception(appointment, :missing_before_photos, :medium, "Before photos missing", "Ask tech to upload proof") | exceptions]
  else
    exceptions
  end
end

defp maybe_add_missing_required_photos(exceptions, _appointment, _photo_counts_by_appointment), do: exceptions

defp exception(appointment, kind, severity, reason, action) do
  %{
    appointment_id: appointment.id,
    customer_id: appointment.customer_id,
    scheduled_at: appointment.scheduled_at,
    kind: kind,
    severity: severity,
    reason: reason,
    action: action
  }
end

defp workload_pressure(count, current) when count >= 4 or not is_nil(current), do: :high
defp workload_pressure(count, _current) when count >= 2, do: :medium
defp workload_pressure(_count, _current), do: :normal

defp severity_order(:high), do: 0
defp severity_order(:medium), do: 1
defp severity_order(:low), do: 2
```

- [ ] **Step 4: Run presenter tests**

Run:

```bash
mix test test/mobile_car_wash_web/live/admin/dispatch_presenter_test.exs
```

Expected: all presenter tests pass.

- [ ] **Step 5: Commit Task 2**

```bash
git add lib/mobile_car_wash_web/live/admin/dispatch_presenter.ex test/mobile_car_wash_web/live/admin/dispatch_presenter_test.exs
git commit -m "feat: derive dispatch exceptions and workload"
```

---

### Task 3: Load Derived Dispatch State In LiveView

**Files:**
- Modify: `lib/mobile_car_wash_web/live/admin/dispatch_live.ex`

- [ ] **Step 1: Alias presenter and photo resource**

At the top of `dispatch_live.ex`, change aliases to include:

```elixir
alias MobileCarWashWeb.Admin.DispatchPresenter
alias MobileCarWash.Operations.{Technician, Photo}
```

Remove the separate `alias MobileCarWash.Operations.Technician`.

- [ ] **Step 2: Add photo count loading helper**

Add this private function near `load_service_map/0`:

```elixir
defp load_photo_counts_by_appointment([]), do: %{}

defp load_photo_counts_by_appointment(appointment_ids) do
  Photo
  |> Ash.Query.filter(appointment_id in ^appointment_ids and is_nil(deleted_at))
  |> Ash.read!(authorize?: false)
  |> Enum.group_by(& &1.appointment_id)
  |> Map.new(fn {appointment_id, photos} ->
    counts =
      photos
      |> Enum.group_by(& &1.photo_type)
      |> Map.new(fn {type, typed_photos} -> {type, length(typed_photos)} end)

    {appointment_id,
     %{
       before: Map.get(counts, :before, 0),
       after: Map.get(counts, :after, 0),
       problem_area: Map.get(counts, :problem_area, 0),
       step_completion: Map.get(counts, :step_completion, 0),
       total: length(photos)
     }}
  end)
end
```

- [ ] **Step 3: Assign derived state inside `load_appointments/1`**

After `active` is computed and before the final `assign(socket, ...)`, add:

```elixir
progress_by_appointment = DispatchPresenter.progress_by_appointment(active)
photo_counts_by_appointment = load_photo_counts_by_appointment(Enum.map(all, & &1.id))

exceptions =
  DispatchPresenter.exceptions(filtered,
    flagged_customer_ids: flagged_customer_ids,
    tech_requests: socket.assigns.tech_requests,
    progress_by_appointment: progress_by_appointment,
    photo_counts_by_appointment: photo_counts_by_appointment
  )

metrics = DispatchPresenter.metrics(filtered, technicians = socket.assigns.technicians, exceptions)
assignment_queue = DispatchPresenter.assignment_queue(filtered)
active_service_appointments = DispatchPresenter.active_appointments(all)

technician_workload =
  DispatchPresenter.technician_workload(
    technicians,
    all,
    socket.assigns.current_appointment_by_tech
  )
```

In the existing final `assign(socket, ...)`, add:

```elixir
dispatch_metrics: metrics,
dispatch_exceptions: exceptions,
assignment_queue: assignment_queue,
active_service_appointments: active_service_appointments,
technician_workload: technician_workload,
photo_counts_by_appointment: photo_counts_by_appointment,
progress_by_appointment: progress_by_appointment,
```

- [ ] **Step 4: Make status-update reloads refresh derived state**

In `reload_one_appointment/2`, replace the final `assign(socket, all_appointments: all, active: active)` with:

```elixir
socket
|> assign(all_appointments: all, active: active)
|> load_appointments()
```

This keeps derived command-center state fresh after a targeted appointment update. Keep this direct reload for the first implementation slice so the command-center assigns cannot drift.

- [ ] **Step 5: Run existing dispatch tests**

Run:

```bash
mix test test/mobile_car_wash_web/live/admin/dispatch_live_kanban_test.exs test/mobile_car_wash_web/live/admin/dispatch_live_tech_strip_test.exs test/mobile_car_wash_web/live/admin/dispatch_live_tag_flag_test.exs
```

Expected: existing tests pass.

- [ ] **Step 6: Commit Task 3**

```bash
git add lib/mobile_car_wash_web/live/admin/dispatch_live.ex
git commit -m "feat: load dispatch command state"
```

---

### Task 4: Command Center Components

**Files:**
- Modify: `lib/mobile_car_wash_web/live/admin/components/dispatch_components.ex`

- [ ] **Step 1: Add component availability tests**

In `test/mobile_car_wash_web/live/admin/dispatch_live_kanban_test.exs`, add tests next to the existing component availability tests:

```elixir
test "command center components are available" do
  functions = MobileCarWashWeb.Admin.DispatchComponents.__info__(:functions)

  assert {:command_bar, 1} in functions
  assert {:metric_cards, 1} in functions
  assert {:exception_panel, 1} in functions
  assert {:assignment_queue, 1} in functions
  assert {:technician_workload_rail, 1} in functions
end
```

- [ ] **Step 2: Run test and verify it fails**

Run:

```bash
mix test test/mobile_car_wash_web/live/admin/dispatch_live_kanban_test.exs
```

Expected: failure because the new component functions do not exist.

- [ ] **Step 3: Add command center components**

Add these public components above `appointment_card/1` in `dispatch_components.ex`:

```elixir
import MobileCarWashWeb.CoreComponents, only: [icon: 1]

attr :metrics, :map, required: true
attr :filter_date, :any, default: nil

def command_bar(assigns) do
  assigns = assign(assigns, :display_date, display_date(assigns.filter_date))

  ~H"""
  <section id="dispatch-command-bar" class="rounded-2xl border border-base-300 bg-base-100 shadow-sm">
    <div class="flex flex-col gap-4 p-5 lg:flex-row lg:items-center lg:justify-between">
      <div>
        <p class="text-xs font-bold uppercase tracking-[0.18em] text-primary">Today / Live Ops</p>
        <h1 class="text-3xl font-black tracking-tight text-base-content md:text-4xl">Dispatch Center</h1>
        <p class="text-sm text-base-content/70">Live service monitoring and assignment control for {@display_date}</p>
      </div>
      <div class="flex flex-wrap gap-2">
        <span class="badge badge-info gap-1 px-3 py-3">
          <.icon name="hero-signal-micro" class="size-4" /> Live
        </span>
        <span class="badge badge-success px-3 py-3">{@metrics.on_duty} on duty</span>
        <span class={["badge px-3 py-3", if(@metrics.exceptions > 0, do: "badge-warning", else: "badge-ghost")]}>
          {@metrics.exceptions} need action
        </span>
        <MobileCarWashWeb.Layouts.theme_toggle />
      </div>
    </div>
  </section>
  """
end

attr :metrics, :map, required: true

def metric_cards(assigns) do
  ~H"""
  <section id="dispatch-metrics" class="grid grid-cols-2 gap-3 lg:grid-cols-4">
    <.metric_card label="In progress" value={@metrics.in_progress} tone="bg-sky-500 text-white" />
    <.metric_card label="Ready to assign" value={@metrics.ready_to_assign} tone="bg-blue-50 text-blue-700 dark:bg-blue-950 dark:text-blue-200" />
    <.metric_card label="Completed" value={@metrics.completed} tone="bg-emerald-50 text-emerald-700 dark:bg-emerald-950 dark:text-emerald-200" />
    <.metric_card label="Exceptions" value={@metrics.exceptions} tone="bg-orange-50 text-orange-700 dark:bg-orange-950 dark:text-orange-200" />
  </section>
  """
end

attr :label, :string, required: true
attr :value, :integer, required: true
attr :tone, :string, required: true

defp metric_card(assigns) do
  ~H"""
  <div class={["rounded-2xl border border-base-300 p-4 shadow-sm transition hover:-translate-y-0.5", @tone]}>
    <p class="text-xs font-bold uppercase tracking-[0.12em] opacity-75">{@label}</p>
    <p class="mt-2 text-4xl font-black">{@value}</p>
  </div>
  """
end
```

Then add skeleton versions for the remaining required functions. They can call existing `appointment_card/1` where useful:

```elixir
attr :exceptions, :list, required: true
attr :customer_map, :map, required: true
attr :service_map, :map, required: true
attr :appointments_by_id, :map, required: true

def exception_panel(assigns) do
  ~H"""
  <section id="dispatch-exceptions" class="rounded-2xl border border-base-300 bg-base-100 p-4 shadow-sm">
    <div class="mb-3 flex items-center justify-between">
      <h2 class="text-lg font-black">Needs Action</h2>
      <span class="badge badge-warning">{length(@exceptions)}</span>
    </div>
    <div :if={@exceptions == []} class="rounded-xl bg-base-200 p-4 text-sm text-base-content/70">
      No dispatch exceptions right now.
    </div>
    <div class="space-y-3">
      <div :for={item <- @exceptions} id={"dispatch-exception-#{item.appointment_id}-#{item.kind}"} class="rounded-xl border border-warning/30 bg-warning/10 p-3">
        <% appt = Map.get(@appointments_by_id, item.appointment_id) %>
        <p class="text-sm font-bold">{item.reason}</p>
        <p class="text-xs text-base-content/70">
          {appt && Map.get(@service_map, appt.service_type_id, "Service")} · {Map.get(@customer_map, item.customer_id, "Customer")}
        </p>
        <p class="mt-2 text-xs font-semibold text-warning">{item.action}</p>
      </div>
    </div>
  </section>
  """
end

attr :appointments, :list, required: true
attr :customer_map, :map, required: true
attr :service_map, :map, required: true
attr :technicians, :list, required: true
attr :address_map, :map, required: true
attr :vehicle_map, :map, required: true
attr :tech_requests, :map, required: true
attr :flagged_customer_ids, :any, required: true

def assignment_queue(assigns) do
  ~H"""
  <section id="dispatch-assignment-queue" class="rounded-2xl border border-base-300 bg-base-100 p-4 shadow-sm">
    <div class="mb-4 flex items-center justify-between">
      <h2 class="text-xl font-black">Assignment Queue</h2>
      <span class="badge badge-info">{length(@appointments)}</span>
    </div>
    <div :if={@appointments == []} class="rounded-xl bg-base-200 p-4 text-sm text-base-content/70">No jobs waiting for assignment.</div>
    <div class="grid gap-3">
      <.appointment_card
        :for={appt <- @appointments}
        appointment={appt}
        customer_name={Map.get(@customer_map, appt.customer_id, "Customer")}
        service_name={Map.get(@service_map, appt.service_type_id, "Service")}
        technicians={@technicians}
        address_zone={get_address_zone(appt, @address_map)}
        vehicle={Map.get(@vehicle_map, appt.vehicle_id)}
        requested_by={Map.get(@tech_requests, appt.id)}
        booking_flagged?={MapSet.member?(@flagged_customer_ids, appt.customer_id)}
      />
    </div>
  </section>
  """
end

attr :workloads, :list, required: true

def technician_workload_rail(assigns) do
  ~H"""
  <section id="dispatch-technician-workload" class="rounded-2xl border border-base-300 bg-base-100 p-4 shadow-sm">
    <h2 class="mb-4 text-lg font-black">Technician Workload</h2>
    <div class="space-y-3">
      <div :for={tech <- @workloads} id={"dispatch-tech-workload-#{tech.id}"} class="rounded-xl border border-base-300 bg-base-200/60 p-3">
        <div class="flex items-center justify-between gap-3">
          <div>
            <p class="font-bold">{tech.name}</p>
            <p class="text-xs text-base-content/70">{format_status(tech.status)} · {tech.assigned_count} assigned</p>
          </div>
          <span class={["badge badge-sm", workload_badge(tech.pressure)]}>{tech.pressure}</span>
        </div>
      </div>
    </div>
  </section>
  """
end
```

Add helpers near the bottom:

```elixir
defp display_date(nil), do: "all scheduled jobs"
defp display_date(%Date{} = date), do: Calendar.strftime(date, "%b %d, %Y")

defp workload_badge(:high), do: "badge-warning"
defp workload_badge(:medium), do: "badge-info"
defp workload_badge(_), do: "badge-ghost"
```

- [ ] **Step 4: Run component availability tests**

Run:

```bash
mix test test/mobile_car_wash_web/live/admin/dispatch_live_kanban_test.exs
```

Expected: all tests in that file pass.

- [ ] **Step 5: Commit Task 4**

```bash
git add lib/mobile_car_wash_web/live/admin/components/dispatch_components.ex test/mobile_car_wash_web/live/admin/dispatch_live_kanban_test.exs
git commit -m "feat: add dispatch command components"
```

---

### Task 5: Replace Dispatch Layout With Command Center

**Files:**
- Modify: `lib/mobile_car_wash_web/live/admin/dispatch_live.ex`
- Create: `test/mobile_car_wash_web/live/admin/dispatch_live_command_center_test.exs`

- [ ] **Step 1: Add LiveView DOM presence test**

Create `test/mobile_car_wash_web/live/admin/dispatch_live_command_center_test.exs`:

```elixir
defmodule MobileCarWashWeb.Admin.DispatchLiveCommandCenterTest do
  use MobileCarWashWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  require Ash.Query

  alias MobileCarWash.Accounts.Customer

  defp create_admin do
    {:ok, admin} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "admin-command-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Command Admin",
        phone: "+15125550301"
      })
      |> Ash.create()

    admin
    |> Ash.Changeset.for_update(:update, %{role: :admin})
    |> Ash.update!(authorize?: false)
  end

  defp sign_in(conn, user) do
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> post("/auth/customer/password/sign_in", %{
      "customer" => %{
        "email" => to_string(user.email),
        "password" => "Password123!"
      }
    })
    |> recycle()
  end

  test "admin dispatch renders command center regions", %{conn: conn} do
    conn = conn |> sign_in(create_admin())

    {:ok, view, _html} = live(conn, ~p"/admin/dispatch")

    assert has_element?(view, "#dispatch-command-bar")
    assert has_element?(view, "#dispatch-metrics")
    assert has_element?(view, "#dispatch-exceptions")
    assert has_element?(view, "#dispatch-assignment-queue")
    assert has_element?(view, "#dispatch-technician-workload")
    assert has_element?(view, "#dispatch-map")
  end
end
```

- [ ] **Step 2: Run the LiveView test and verify it fails before layout replacement**

Run:

```bash
mix test test/mobile_car_wash_web/live/admin/dispatch_live_command_center_test.exs
```

Expected: failure because the command center region IDs are not all present.

- [ ] **Step 3: Replace the render body layout**

In `DispatchLive.render/1`, replace the content inside the outer wrapper with this order:

```heex
<div class="min-h-screen bg-base-200 px-4 py-6">
  <div class="mx-auto flex max-w-7xl flex-col gap-5">
    <.command_bar metrics={@dispatch_metrics} filter_date={@filter_date} />

    <.metric_cards metrics={@dispatch_metrics} />

    <form id="dispatch-filters" phx-change="filter" class="rounded-2xl border border-base-300 bg-base-100 p-4 shadow-sm">
      <%!-- Move the existing date, technician, zone, requested, and clear controls here without changing their names or events. --%>
    </form>

    <div class="grid gap-5 xl:grid-cols-[minmax(0,1fr)_22rem]">
      <div class="flex flex-col gap-5">
        <section id="dispatch-active-services" class="rounded-2xl border border-base-300 bg-base-100 p-4 shadow-sm">
          <div class="mb-4 flex items-center justify-between">
            <h2 class="text-xl font-black">Live Service Board</h2>
            <span class="badge badge-success">{length(@active)}</span>
          </div>
          <div :if={@active == []} class="rounded-xl bg-base-200 p-4 text-sm text-base-content/70">
            No active services right now.
          </div>
          <div class="grid grid-cols-1 gap-4 lg:grid-cols-2">
            <.active_wash_card
              :for={{appt, progress} <- @active}
              appointment={appt}
              customer_name={Map.get(@customer_map, appt.customer_id, "Customer")}
              service_name={Map.get(@service_map, appt.service_type_id, "Service")}
              tech_name={tech_name(appt.technician_id, @technicians)}
              progress={progress}
            />
          </div>
        </section>

        <.assignment_queue
          appointments={@assignment_queue}
          customer_map={@customer_map}
          service_map={@service_map}
          technicians={@technicians}
          address_map={@address_map}
          vehicle_map={@vehicle_map}
          tech_requests={@tech_requests}
          flagged_customer_ids={@flagged_customer_ids}
        />
      </div>

      <aside class="flex flex-col gap-5">
        <.exception_panel
          exceptions={@dispatch_exceptions}
          customer_map={@customer_map}
          service_map={@service_map}
          appointments_by_id={Map.new(@all_appointments, &{&1.id, &1})}
        />

        <.technician_workload_rail workloads={@technician_workload} />

        <section id="dispatch-map-panel" class="rounded-2xl border border-base-300 bg-base-100 p-4 shadow-sm">
          <h2 class="mb-3 text-lg font-black">Map Context</h2>
          <div id="dispatch-map" phx-hook="DispatchMap" phx-update="ignore" class="h-80 w-full rounded-xl border border-base-300 z-0" />
        </section>
      </aside>
    </div>

    <section id="dispatch-status-board" class="pb-8">
      <%!-- Move the existing four Kanban columns here as the secondary planning board. --%>
    </section>

    <%!-- Move the existing Manage Technicians block here below the status board. --%>
  </div>
</div>
```

Move the existing filter controls, Kanban columns, and Manage Technicians markup into the indicated sections. Preserve all existing `phx-*` event names.

- [ ] **Step 4: Run dispatch LiveView tests**

Run:

```bash
mix test test/mobile_car_wash_web/live/admin/dispatch_live_command_center_test.exs test/mobile_car_wash_web/live/admin/dispatch_live_kanban_test.exs test/mobile_car_wash_web/live/admin/dispatch_live_tech_strip_test.exs test/mobile_car_wash_web/live/admin/dispatch_live_tag_flag_test.exs
```

Expected: all pass. If tech-strip tests fail because the old "Techs on shift" heading moved into workload rail, update assertions to the new stable `#dispatch-technician-workload` region and visible technician names/statuses.

- [ ] **Step 5: Commit Task 5**

```bash
git add lib/mobile_car_wash_web/live/admin/dispatch_live.ex test/mobile_car_wash_web/live/admin/dispatch_live_command_center_test.exs test/mobile_car_wash_web/live/admin/dispatch_live_kanban_test.exs test/mobile_car_wash_web/live/admin/dispatch_live_tech_strip_test.exs
git commit -m "feat: redesign admin dispatch command center"
```

---

### Task 6: Polish, Verify Dark Mode, And Precommit

**Files:**
- Modify only files required by compile/test failures.

- [ ] **Step 1: Run formatter**

Run:

```bash
mix format
```

Expected: formatting completes without error.

- [ ] **Step 2: Run focused tests**

Run:

```bash
mix test test/mobile_car_wash_web/live/admin/dispatch_presenter_test.exs test/mobile_car_wash_web/live/admin/dispatch_live_command_center_test.exs test/mobile_car_wash_web/live/admin/dispatch_live_kanban_test.exs test/mobile_car_wash_web/live/admin/dispatch_live_tech_strip_test.exs test/mobile_car_wash_web/live/admin/dispatch_live_tag_flag_test.exs
```

Expected: all pass.

- [ ] **Step 3: Run precommit**

Run:

```bash
mix precommit
```

Expected: all checks pass. Existing Ash missed-notification warnings may appear; failures must be fixed.

- [ ] **Step 4: Visual check locally**

Run the Phoenix server:

```bash
mix phx.server
```

Open `/admin/dispatch` as an admin and verify:

- Command bar renders.
- Theme toggle changes light/dark mode.
- Metric cards are visible.
- Exceptions panel handles empty and populated states.
- Assignment queue can assign/reassign a technician.
- Confirm appointment still works.
- Map still renders and receives pins.
- Manage Technicians still opens and saves existing fields.

- [ ] **Step 5: Commit final polish**

```bash
git status --short
git add lib/mobile_car_wash_web/live/admin/dispatch_presenter.ex lib/mobile_car_wash_web/live/admin/dispatch_live.ex lib/mobile_car_wash_web/live/admin/components/dispatch_components.ex test/mobile_car_wash_web/live/admin/dispatch_presenter_test.exs test/mobile_car_wash_web/live/admin/dispatch_live_command_center_test.exs test/mobile_car_wash_web/live/admin/dispatch_live_kanban_test.exs test/mobile_car_wash_web/live/admin/dispatch_live_tech_strip_test.exs
git commit -m "test: verify dispatch command center"
```

Skip this commit if Task 6 produced no file changes after Task 5.
