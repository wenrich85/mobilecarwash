# Tech Dashboard Next Action Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a "Next Action First" `/tech` dashboard with one clear Workday Command Card for linked technicians.

**Architecture:** Keep the work in `MobileCarWashWeb.TechDashboardLive`, using small private helpers to derive a command-card view model from the already-loaded technician record, today's appointments, and checklist progress. Reuse existing appointment transitions, checklist navigation, duty-status events, and supply-log modal instead of adding new resources or actions.

**Tech Stack:** Phoenix LiveView, Ash resources, ExUnit/Phoenix LiveViewTest, existing Tailwind/DaisyUI styling.

## Global Constraints

- Do not add database tables, migrations, appointment statuses, route optimization, notification systems, checklist rewrites, or earnings rewrites.
- Main implementation file: `lib/mobile_car_wash_web/live/tech/tech_dashboard_live.ex`.
- Main test file: `test/mobile_car_wash_web/live/tech/tech_dashboard_live_test.exs`.
- The command card must show exactly one primary next action when actionable work exists.
- Admins without a linked technician record must keep the current admin-view warning and must not get a personal command card.
- Missing service, customer, address, vehicle, or checklist progress data must degrade to existing fallback labels rather than crashing.
- Use TDD for each task: add failing tests first, verify they fail, implement minimal code, verify green, then commit.

---

## File Structure

- Modify `lib/mobile_car_wash_web/live/tech/tech_dashboard_live.ex`
  - Add a `:command_card` assign in `mount/3` and `reload_appointments/1`.
  - Add private helpers:
    - `build_command_card/3`
    - `command_candidate/2`
    - `command_priority/1`
    - `command_kind/2`
    - `command_title/1`
    - `command_body/1`
    - `command_badge/1`
    - `command_primary_action/1`
    - `command_card_appointment_id/1`
    - `appointment_row_state/3`
  - Add a private HEEx function component `workday_command_card/1`.
  - Pass row state into `appointment_row/1`.
  - Reorder render sections so the map follows the command card and Today queue.

- Modify `test/mobile_car_wash_web/live/tech/tech_dashboard_live_test.exs`
  - Add a new `describe "workday command card"` block.
  - Reuse existing helper functions: `create_tech_customer/0`, `create_tech_record/1`, `sign_in/2`, `create_appointment/4`.
  - Add one helper for creating checklist progress in tests:
    - `create_checklist_progress!(appointment, steps_total, steps_done, status \\ :in_progress)`

No new production module is planned for this slice.

---

### Task 1: Command Card Contract And Base States

**Files:**
- Modify: `test/mobile_car_wash_web/live/tech/tech_dashboard_live_test.exs`
- Modify: `lib/mobile_car_wash_web/live/tech/tech_dashboard_live.ex`

**Interfaces:**
- Consumes existing helpers:
  - `create_tech_customer() :: MobileCarWash.Accounts.Customer.t()`
  - `create_tech_record(customer) :: MobileCarWash.Operations.Technician.t()`
  - `sign_in(conn, customer) :: Plug.Conn.t()`
  - `create_appointment(customer_id, technician_id, status, opts \\ []) :: MobileCarWash.Scheduling.Appointment.t()`
- Produces:
  - `build_command_card(tech_record_or_nil, todays_appointments, progress_map) :: map() | nil`
  - `command_card` assign available to `render/1`
  - `#tech-workday-command` root element for linked technicians
  - `#command-start-shift` button when off-duty tech has actionable work
  - `#command-view-job` link when available tech has a confirmed next job

- [ ] **Step 1: Add failing tests for the base command-card states**

Append this describe block after the existing `"duty-status control"` describe block in `test/mobile_car_wash_web/live/tech/tech_dashboard_live_test.exs`:

```elixir
  describe "workday command card" do
    setup %{conn: conn} do
      user = create_tech_customer()
      tech = create_tech_record(user)
      conn = sign_in(conn, user)

      {:ok, customer} =
        Customer
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "command-cust-#{System.unique_integer([:positive])}@test.com",
          password: "Password123!",
          password_confirmation: "Password123!",
          name: "Command Customer",
          phone: "+15125550401"
        })
        |> Ash.create()

      {:ok, conn: conn, user: user, tech: tech, customer: customer}
    end

    test "off-duty tech with work today sees start shift as the primary command",
         %{conn: conn, tech: tech, customer: customer} do
      _appt = create_appointment(customer.id, tech.id, :confirmed)

      {:ok, view, _html} = live(conn, ~p"/tech")

      assert has_element?(view, "#tech-workday-command")
      assert has_element?(view, "#command-start-shift", "Start shift")
      assert render(view) =~ "Start your shift to begin today's work."
    end

    test "available tech with a confirmed job sees the next job command",
         %{conn: conn, tech: tech, customer: customer} do
      tech
      |> Ash.Changeset.for_update(:set_status, %{status: :available})
      |> Ash.update!()

      appt = create_appointment(customer.id, tech.id, :confirmed)

      {:ok, view, _html} = live(conn, ~p"/tech")

      assert has_element?(view, "#tech-workday-command")
      assert has_element?(view, "#command-view-job[href='/tech/appointments/#{appt.id}']", "View job")
      assert render(view) =~ "Command Customer"
      assert render(view) =~ "Basic Wash"
    end

    test "linked tech with no work today sees a calm empty state", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/tech")

      assert has_element?(view, "#tech-workday-command")
      assert render(view) =~ "No jobs today"
      assert render(view) =~ "You are clear for now."
    end

    test "admin without linked technician record keeps admin mode without a personal command card",
         %{conn: conn} do
      {:ok, admin} =
        Customer
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "command-admin-#{System.unique_integer([:positive])}@test.com",
          password: "Password123!",
          password_confirmation: "Password123!",
          name: "Command Admin",
          phone: "+15125550499"
        })
        |> Ash.create()

      {:ok, admin} =
        admin
        |> Ash.Changeset.for_update(:update, %{role: :admin})
        |> Ash.update(authorize?: false)

      admin_conn = sign_in(conn, admin)

      {:ok, view, _html} = live(admin_conn, ~p"/tech")

      refute has_element?(view, "#tech-workday-command")
      assert render(view) =~ "Viewing as admin"
    end
  end
```

- [ ] **Step 2: Run the focused tests and verify they fail**

Run:

```bash
mix test test/mobile_car_wash_web/live/tech/tech_dashboard_live_test.exs
```

Expected: FAIL because `#tech-workday-command`, `#command-start-shift`, and `#command-view-job` do not exist yet.

- [ ] **Step 3: Add the `command_card` assign**

In `mount/3`, replace the existing `progress_map = build_progress_map(all_appts)` line with:

```elixir
    progress_map = build_progress_map(all_appts)
    command_card = build_command_card(tech_record, todays, progress_map)
```

In the socket assigns inside `mount/3`, add:

```elixir
        command_card: command_card,
```

In `reload_appointments/1`, after rebuilding `progress_map`, also rebuild:

```elixir
command_card = build_command_card(socket.assigns.tech_record, todays, progress_map)
```

and assign:

```elixir
command_card: command_card,
```

If `reload_appointments/1` uses different local variable names, keep its current names and add the same `build_command_card/3` call after `todays` and `progress_map` are both available.

- [ ] **Step 4: Add the base command-card render call**

In `render/1`, place this after the welcome header and before the existing duty-status control:

```heex
      <.workday_command_card
        :if={@command_card}
        command_card={@command_card}
        service_map={@service_map}
        customer_map={@customer_map}
        address_map={@address_map}
        vehicle_map={@vehicle_map}
      />
```

- [ ] **Step 5: Add command-card helpers and component**

Add these private functions near the other private helpers in `lib/mobile_car_wash_web/live/tech/tech_dashboard_live.ex`:

```elixir
  defp build_command_card(nil, _todays_appointments, _progress_map), do: nil

  defp build_command_card(tech_record, todays_appointments, progress_map) do
    actionable =
      todays_appointments
      |> Enum.reject(&(&1.status in [:cancelled, :pending]))
      |> Enum.sort_by(fn appointment ->
        {command_priority(appointment), DateTime.to_unix(appointment.scheduled_at)}
      end)

    candidate = Enum.find(actionable, &(command_priority(&1) < 99))
    kind = command_kind(tech_record, candidate)

    %{
      kind: kind,
      appointment: candidate,
      title: command_title(kind),
      body: command_body(kind),
      badge: command_badge(kind),
      action: command_primary_action(kind, candidate, progress_map)
    }
  end

  defp command_priority(%{status: :in_progress}), do: 0
  defp command_priority(%{status: :on_site}), do: 1
  defp command_priority(%{status: :en_route}), do: 2
  defp command_priority(%{status: :confirmed}), do: 3
  defp command_priority(%{status: :completed}), do: 8
  defp command_priority(_appointment), do: 99

  defp command_kind(%{status: :off_duty}, %{status: status})
       when status in [:confirmed, :en_route, :on_site, :in_progress],
    do: :start_shift

  defp command_kind(_tech_record, nil), do: :no_work
  defp command_kind(_tech_record, %{status: :confirmed}), do: :view_job
  defp command_kind(_tech_record, %{status: :en_route}), do: :mark_arrived
  defp command_kind(_tech_record, %{status: :on_site}), do: :start_wash
  defp command_kind(_tech_record, %{status: :in_progress}), do: :continue_checklist
  defp command_kind(_tech_record, %{status: :completed}), do: :log_supplies
  defp command_kind(_tech_record, _appointment), do: :review_schedule

  defp command_title(:start_shift), do: "Start your workday"
  defp command_title(:view_job), do: "Next job"
  defp command_title(:mark_arrived), do: "You are en route"
  defp command_title(:start_wash), do: "You are on site"
  defp command_title(:continue_checklist), do: "Wash in progress"
  defp command_title(:log_supplies), do: "Wrap up completed job"
  defp command_title(:no_work), do: "No jobs today"
  defp command_title(:review_schedule), do: "Review schedule"

  defp command_body(:start_shift), do: "Start your shift to begin today's work."
  defp command_body(:view_job), do: "Review the job brief before heading out."
  defp command_body(:mark_arrived), do: "Mark yourself on site when you arrive."
  defp command_body(:start_wash), do: "Start the wash when you are ready."
  defp command_body(:continue_checklist), do: "Continue the active wash checklist."
  defp command_body(:log_supplies), do: "Log supplies for the completed stop."
  defp command_body(:no_work), do: "You are clear for now."
  defp command_body(:review_schedule), do: "Review the appointment details."

  defp command_badge(:start_shift), do: "Shift"
  defp command_badge(:view_job), do: "Next"
  defp command_badge(:mark_arrived), do: "En route"
  defp command_badge(:start_wash), do: "On site"
  defp command_badge(:continue_checklist), do: "Active"
  defp command_badge(:log_supplies), do: "Wrap-up"
  defp command_badge(:no_work), do: "Clear"
  defp command_badge(:review_schedule), do: "Schedule"

  defp command_primary_action(:start_shift, _appointment, _progress_map),
    do: %{type: :event, id: "command-start-shift", event: "set_status", value_status: "available", label: "Start shift"}

  defp command_primary_action(:view_job, %{id: appointment_id}, _progress_map),
    do: %{type: :link, id: "command-view-job", to: ~p"/tech/appointments/#{appointment_id}", label: "View job"}

  defp command_primary_action(:mark_arrived, %{id: appointment_id}, _progress_map),
    do: %{type: :event, id: "command-mark-arrived", event: "arrive", value_id: appointment_id, label: "Mark arrived"}

  defp command_primary_action(:start_wash, %{id: appointment_id}, _progress_map),
    do: %{type: :event, id: "command-start-wash", event: "start_wash", value_id: appointment_id, label: "Start wash"}

  defp command_primary_action(:continue_checklist, %{id: appointment_id}, progress_map) do
    progress = Map.get(progress_map, appointment_id, default_progress())

    if progress.checklist_id do
      %{type: :link, id: "command-continue-checklist", to: ~p"/tech/checklist/#{progress.checklist_id}", label: "Continue checklist"}
    else
      %{type: :link, id: "command-view-job", to: ~p"/tech/appointments/#{appointment_id}", label: "View job"}
    end
  end

  defp command_primary_action(:log_supplies, %{id: appointment_id}, _progress_map),
    do: %{type: :event, id: "command-log-supplies", event: "open_supply_log", value_id: appointment_id, label: "Log supplies"}

  defp command_primary_action(_kind, _appointment, _progress_map), do: nil

  defp default_progress do
    %{checklist_id: nil, steps_done: 0, steps_total: 0, current_step: nil, eta_minutes: nil, checklist_status: nil}
  end
```

Add this component below `appointment_row/1` or near it:

```elixir
  attr :command_card, :map, required: true
  attr :service_map, :map, required: true
  attr :customer_map, :map, required: true
  attr :address_map, :map, required: true
  attr :vehicle_map, :map, required: true

  defp workday_command_card(assigns) do
    ~H"""
    <section id="tech-workday-command" class="card bg-base-100 shadow mb-6 border border-primary/20">
      <div class="card-body p-4">
        <div class="flex items-start justify-between gap-3">
          <div>
            <span class="badge badge-primary badge-sm">{@command_card.badge}</span>
            <h2 class="mt-2 text-xl font-bold">{@command_card.title}</h2>
            <p class="mt-1 text-sm text-base-content/70">{@command_card.body}</p>
          </div>
        </div>

        <div :if={@command_card.appointment} class="mt-4 rounded-xl bg-base-200/60 p-3">
          <% appt = @command_card.appointment %>
          <p class="text-sm font-semibold">
            {Map.get(@customer_map, appt.customer_id, "Customer")}
          </p>
          <p class="text-sm text-base-content/80">
            {(Map.get(@service_map, appt.service_type_id) && Map.get(@service_map, appt.service_type_id).name) || "Service"}
            · {Calendar.strftime(appt.scheduled_at, "%b %d · %I:%M %p")}
          </p>
          <p :if={Map.get(@vehicle_map, appt.vehicle_id)} class="text-xs text-base-content/70">
            {vehicle_label(Map.get(@vehicle_map, appt.vehicle_id))}
          </p>
          <p :if={Map.get(@address_map, appt.address_id)} class="text-xs text-base-content/70">
            {Map.get(@address_map, appt.address_id).street}, {Map.get(@address_map, appt.address_id).city}
          </p>
        </div>

        <div :if={@command_card.action} class="mt-4">
          <button
            :if={@command_card.action.type == :event}
            id={@command_card.action.id}
            class="btn btn-primary btn-block"
            phx-click={@command_card.action.event}
            phx-value-status={Map.get(@command_card.action, :value_status)}
            phx-value-id={Map.get(@command_card.action, :value_id)}
          >
            {@command_card.action.label}
          </button>

          <.link
            :if={@command_card.action.type == :link}
            id={@command_card.action.id}
            navigate={@command_card.action.to}
            class="btn btn-primary btn-block"
          >
            {@command_card.action.label}
          </.link>
        </div>

        <div :if={!@command_card.action} class="mt-4 flex gap-2">
          <.link navigate={~p"/tech/profile"} class="btn btn-outline btn-sm">Profile</.link>
          <a href="#tech-earnings" class="btn btn-ghost btn-sm">Earnings</a>
        </div>
      </div>
    </section>
    """
  end
```

- [ ] **Step 6: Run focused tests and verify Task 1 passes**

Run:

```bash
mix test test/mobile_car_wash_web/live/tech/tech_dashboard_live_test.exs
```

Expected: PASS for the new base command-card tests and existing dashboard tests. If old tests fail because duplicate text appears, update selectors to target specific ids rather than broad text.

- [ ] **Step 7: Commit Task 1**

Run:

```bash
git add lib/mobile_car_wash_web/live/tech/tech_dashboard_live.ex test/mobile_car_wash_web/live/tech/tech_dashboard_live_test.exs
git commit -m "Add tech dashboard command card"
```

---

### Task 2: Complete Command Actions, Row Labels, And Layout Order

**Files:**
- Modify: `test/mobile_car_wash_web/live/tech/tech_dashboard_live_test.exs`
- Modify: `lib/mobile_car_wash_web/live/tech/tech_dashboard_live.ex`

**Interfaces:**
- Consumes from Task 1:
  - `command_card` assign.
  - `workday_command_card/1`.
  - `default_progress/0`.
  - Existing appointment event handlers: `"arrive"`, `"start_wash"`, `"open_supply_log"`.
- Produces:
  - `#command-mark-arrived` for `:en_route`.
  - `#command-start-wash` for `:on_site`.
  - `#command-continue-checklist` for `:in_progress` with checklist.
  - `#command-log-supplies` for completed appointment when no active/next jobs exist.
  - `data-command-row-state="active"` or `"next"` on the command-card appointment row.
  - `#tech-earnings` anchor on the earnings section.

- [ ] **Step 1: Add a test helper for checklist progress**

In `test/mobile_car_wash_web/live/tech/tech_dashboard_live_test.exs`, add this helper after `create_appointment/4`:

```elixir
  defp create_checklist_progress!(appointment, steps_total, steps_done, status \\ :in_progress) do
    alias MobileCarWash.Operations.{AppointmentChecklist, ChecklistItem, Procedure, ProcedureStep}

    {:ok, procedure} =
      Procedure
      |> Ash.Changeset.for_create(:create, %{
        name: "Command Wash SOP #{System.unique_integer([:positive])}",
        slug: "command-wash-#{System.unique_integer([:positive])}"
      })
      |> Ash.Changeset.force_change_attribute(:service_type_id, appointment.service_type_id)
      |> Ash.create()

    {:ok, checklist} =
      AppointmentChecklist
      |> Ash.Changeset.for_create(:create, %{status: status})
      |> Ash.Changeset.force_change_attribute(:appointment_id, appointment.id)
      |> Ash.Changeset.force_change_attribute(:procedure_id, procedure.id)
      |> Ash.create()

    for n <- 1..steps_total do
      {:ok, step} =
        ProcedureStep
        |> Ash.Changeset.for_create(:create, %{
          step_number: n,
          title: "Command Step #{n}",
          estimated_minutes: 5
        })
        |> Ash.Changeset.force_change_attribute(:procedure_id, procedure.id)
        |> Ash.create()

      ChecklistItem
      |> Ash.Changeset.for_create(:create, %{
        step_number: n,
        title: "Command Step #{n}",
        estimated_minutes: 5,
        completed: n <= steps_done
      })
      |> Ash.Changeset.force_change_attribute(:checklist_id, checklist.id)
      |> Ash.Changeset.force_change_attribute(:procedure_step_id, step.id)
      |> Ash.create!()
    end

    checklist
  end
```

- [ ] **Step 2: Add failing tests for transition/checklist/supply command states**

Append these tests to the `"workday command card"` describe block:

```elixir
    test "en-route job shows mark arrived as the primary command",
         %{conn: conn, tech: tech, customer: customer} do
      appt = create_appointment(customer.id, tech.id, :en_route)

      {:ok, view, _html} = live(conn, ~p"/tech")

      assert has_element?(view, "#command-mark-arrived", "Mark arrived")

      view
      |> element("#command-mark-arrived")
      |> render_click()

      {:ok, reloaded} = Ash.get(Appointment, appt.id, authorize?: false)
      assert reloaded.status == :on_site
    end

    test "on-site job shows start wash as the primary command",
         %{conn: conn, tech: tech, customer: customer} do
      _appt = create_appointment(customer.id, tech.id, :on_site)

      {:ok, view, _html} = live(conn, ~p"/tech")

      assert has_element?(view, "#command-start-wash", "Start wash")
    end

    test "in-progress job with checklist shows continue checklist as the primary command",
         %{conn: conn, tech: tech, customer: customer} do
      appt = create_appointment(customer.id, tech.id, :in_progress)
      checklist = create_checklist_progress!(appt, 3, 1)

      {:ok, view, _html} = live(conn, ~p"/tech")

      assert has_element?(
               view,
               "#command-continue-checklist[href='/tech/checklist/#{checklist.id}']",
               "Continue checklist"
             )
    end

    test "completed job can surface supply logging when no active work remains",
         %{conn: conn, tech: tech, customer: customer} do
      _appt = create_appointment(customer.id, tech.id, :completed)

      {:ok, view, _html} = live(conn, ~p"/tech")

      assert has_element?(view, "#command-log-supplies", "Log supplies")
    end

    test "today row marks the command-card appointment as next",
         %{conn: conn, tech: tech, customer: customer} do
      appt = create_appointment(customer.id, tech.id, :confirmed)

      {:ok, view, _html} = live(conn, ~p"/tech")

      assert has_element?(view, "[data-appointment-id='#{appt.id}'][data-command-row-state='next']")
      assert render(view) =~ "Next"
    end
```

- [ ] **Step 3: Run focused tests and verify they fail**

Run:

```bash
mix test test/mobile_car_wash_web/live/tech/tech_dashboard_live_test.exs
```

Expected: FAIL for at least the row-state selector and any command action that Task 1 did not fully wire.

- [ ] **Step 4: Add command-row state helpers**

In `lib/mobile_car_wash_web/live/tech/tech_dashboard_live.ex`, add:

```elixir
  defp command_card_appointment_id(%{appointment: %{id: id}}), do: id
  defp command_card_appointment_id(_command_card), do: nil

  defp appointment_row_state(appointment, command_card, progress) do
    if appointment.id == command_card_appointment_id(command_card) do
      cond do
        appointment.status in [:in_progress, :on_site, :en_route] -> :active
        progress.checklist_id -> :active
        appointment.status == :confirmed -> :next
        true -> :next
      end
    end
  end

  defp row_state_label(:active), do: "Active"
  defp row_state_label(:next), do: "Next"
  defp row_state_label(_), do: nil
```

- [ ] **Step 5: Pass row state into today appointment rows**

In the Today section's `<.appointment_row ... />`, replace the inline progress expression with a named value inside the loop by changing the component call to this pattern:

```heex
          <.appointment_row
            :for={appt <- @todays_appointments}
            appointment={appt}
            service={Map.get(@service_map, appt.service_type_id)}
            customer_name={Map.get(@customer_map, appt.customer_id, "Customer")}
            address={Map.get(@address_map, appt.address_id)}
            vehicle={Map.get(@vehicle_map, appt.vehicle_id)}
            progress={Map.get(@progress_map, appt.id, default_progress())}
            row_state={
              appointment_row_state(
                appt,
                @command_card,
                Map.get(@progress_map, appt.id, default_progress())
              )
            }
          />
```

For Tomorrow and Upcoming calls, add:

```heex
            row_state={nil}
```

- [ ] **Step 6: Update `appointment_row/1` to expose row state**

In the root div of `appointment_row/1`, change:

```heex
    <div class="card bg-base-100 shadow-sm">
```

to:

```heex
    <div
      class={[
        "card bg-base-100 shadow-sm",
        @row_state == :active && "border border-warning",
        @row_state == :next && "border border-primary/30"
      ]}
      data-appointment-id={@appointment.id}
      data-command-row-state={@row_state}
    >
```

Inside the row header next to the existing status badge, add:

```heex
            <span :if={row_state_label(@row_state)} class="badge badge-primary badge-sm">
              {row_state_label(@row_state)}
            </span>
```

- [ ] **Step 7: Ensure command actions are wired to existing events**

Confirm `workday_command_card/1` has these action render branches from Task 1:

```heex
          <button
            :if={@command_card.action.type == :event}
            id={@command_card.action.id}
            class="btn btn-primary btn-block"
            phx-click={@command_card.action.event}
            phx-value-status={Map.get(@command_card.action, :value_status)}
            phx-value-id={Map.get(@command_card.action, :value_id)}
          >
            {@command_card.action.label}
          </button>
```

The existing event handlers already handle:

```elixir
def handle_event("set_status", %{"status" => status_str}, socket)
def handle_event("arrive", %{"id" => id}, socket)
def handle_event("start_wash", %{"id" => appointment_id}, socket)
def handle_event("open_supply_log", %{"id" => appointment_id}, socket)
```

Do not add new event names for these actions.

- [ ] **Step 8: Move the map below Today and add an earnings anchor**

In `render/1`, move the entire Map block so it appears after the Today section and before Tomorrow.

Change the Earnings wrapper:

```heex
      <div :if={@tech_record} class="mb-8">
```

to:

```heex
      <div :if={@tech_record} id="tech-earnings" class="mb-8">
```

- [ ] **Step 9: Run focused tests and verify Task 2 passes**

Run:

```bash
mix test test/mobile_car_wash_web/live/tech/tech_dashboard_live_test.exs
```

Expected: PASS, with all command-card state tests green and existing dashboard tests still green.

- [ ] **Step 10: Commit Task 2**

Run:

```bash
git add lib/mobile_car_wash_web/live/tech/tech_dashboard_live.ex test/mobile_car_wash_web/live/tech/tech_dashboard_live_test.exs
git commit -m "Complete tech dashboard next actions"
```

---

### Task 3: Regression Pass, Formatting, And Full Verification

**Files:**
- Modify only if verification reveals issues:
  - `lib/mobile_car_wash_web/live/tech/tech_dashboard_live.ex`
  - `test/mobile_car_wash_web/live/tech/tech_dashboard_live_test.exs`

**Interfaces:**
- Consumes all Task 1 and Task 2 behavior.
- Produces a verified branch ready for review/merge.

- [ ] **Step 1: Run formatter check**

Run:

```bash
mix format --check-formatted lib/mobile_car_wash_web/live/tech/tech_dashboard_live.ex test/mobile_car_wash_web/live/tech/tech_dashboard_live_test.exs
```

Expected: PASS. If it fails, run:

```bash
mix format lib/mobile_car_wash_web/live/tech/tech_dashboard_live.ex test/mobile_car_wash_web/live/tech/tech_dashboard_live_test.exs
```

Then rerun the check.

- [ ] **Step 2: Run focused dashboard tests**

Run:

```bash
mix test test/mobile_car_wash_web/live/tech/tech_dashboard_live_test.exs
```

Expected: PASS with no failures.

- [ ] **Step 3: Run adjacent tech flow tests**

Run:

```bash
mix test test/mobile_car_wash_web/live/tech/application_live_test.exs test/mobile_car_wash_web/live/tech/profile_live_test.exs test/mobile_car_wash_web/live/admin/tech_applications_live_test.exs
```

Expected: PASS. These verify the applicant/profile/admin work remains intact after dashboard changes.

- [ ] **Step 4: Run full project gate**

Run:

```bash
mix precommit
```

Expected: PASS. Existing warnings about Ash notifications, Stripe test warnings, or SQL sandbox disconnects may appear, but the command must exit `0`.

- [ ] **Step 5: Inspect final git diff**

Run:

```bash
git status --short --branch
git diff --stat HEAD
```

Expected:

- Only dashboard implementation/test files changed since Task 2 if verification forced small fixes.
- No unrelated files.
- No ignored scratch files staged.

- [ ] **Step 6: Commit verification fixes if any**

If Step 1-5 required changes, commit them:

```bash
git add lib/mobile_car_wash_web/live/tech/tech_dashboard_live.ex test/mobile_car_wash_web/live/tech/tech_dashboard_live_test.exs
git commit -m "Polish tech dashboard command card"
```

If no files changed, do not create an empty commit.

---

## Plan Self-Review

Spec coverage:

- Workday Command Card: Task 1 and Task 2.
- One primary CTA: Task 1 helper contract and Task 2 state tests.
- Off-duty, confirmed, en-route, on-site, in-progress, completed, no-work states: Task 1 and Task 2 tests.
- Admin without linked technician fallback: Task 1 test.
- Today row active/next labels: Task 2.
- Map below command card and Today: Task 2.
- Existing flows reused: Task 2 event wiring and Task 3 adjacent tests.
- Full verification: Task 3.

Marker scan: no forbidden markers are intentionally left in this plan.

Type consistency:

- `build_command_card/3`, `default_progress/0`, `appointment_row_state/3`, and `command_card_appointment_id/1` are introduced before later tasks rely on them.
- Command action maps consistently use `:type`, `:id`, `:label`, and either `:event` with `:value_id`/`:value_status` or `:to`.
