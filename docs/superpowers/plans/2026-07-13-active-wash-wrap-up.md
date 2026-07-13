# Active Wash Wrap-Up Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn `/tech/checklist/:id` into a guided active-wash command screen with persisted final notes, supply usage, and job earnings in wrap-up.

**Architecture:** Keep `MobileCarWashWeb.ChecklistLive` as the single active-wash page and add a small command-card view model above the existing photo and step sections. Add `final_notes` to `AppointmentChecklist`, then reuse `MobileCarWash.Inventory` for supply usage and `MobileCarWash.Operations.TechEarnings` for pay display. Existing photo gates, checklist completion, appointment completion, upload transport, and lightbox behavior remain unchanged.

**Tech Stack:** Phoenix LiveView, Ash 3, AshPostgres, Ecto migrations, ExUnit, Phoenix.LiveViewTest, Tailwind/DaisyUI.

## Global Constraints

- Use the existing `/tech/checklist/:id` route.
- Keep the one-page checklist; do not replace it with a wizard.
- Preserve before-photo and after-photo gates.
- Preserve current automatic checklist/appointment completion when required steps and after photos are complete.
- Do not change photo upload transport, S3PUT behavior, or lightbox behavior.
- Do not add admin inventory reporting or supply catalog UI.
- Store technician final wrap-up notes on `AppointmentChecklist.final_notes`.
- Use `MobileCarWash.Inventory.log_usage/1` for supply logging.
- Tie wrap-up supply usage to the appointment's `technician_id`; do not accept technician ids from the browser.
- Show earnings using `MobileCarWash.Operations.TechEarnings.wash_earnings/2`.
- Treat `checklist.final_notes == nil` as "wrap-up not saved" even if `checklist.status == :completed`.
- Run `mix precommit` after implementation and fix any failures.

---

## File Structure

Create:

- `priv/repo/migrations/<timestamp>_add_final_notes_to_appointment_checklists.exs`
  - Adds nullable `final_notes` text to `appointment_checklists`.
- `test/mobile_car_wash/operations/appointment_checklist_wrap_up_test.exs`
  - Resource-level coverage for `AppointmentChecklist.final_notes` and `:save_wrap_up`.

Modify:

- `lib/mobile_car_wash/operations/appointment_checklist.ex`
  - Adds `final_notes` attribute and `:save_wrap_up` update action.
- `lib/mobile_car_wash_web/live/checklist_live.ex`
  - Adds command-card view model and rendering.
  - Loads supplies and appointment supply usage.
  - Adds wrap-up form state and `save_wrap_up` event.
  - Renders final notes, supply usage rows, time analysis, earnings, and dashboard return.
- `test/mobile_car_wash_web/live/checklist_live_test.exs`
  - Adds command card, wrap-up, supply usage, and earnings tests.

No separate component module is required for this slice. If `ChecklistLive` becomes hard to read during implementation, extract only small pure helpers inside the same module first; defer a new component module unless the final diff clearly benefits from it.

---

### Task 1: AppointmentChecklist Wrap-Up Data

**Files:**
- Create: `priv/repo/migrations/<timestamp>_add_final_notes_to_appointment_checklists.exs`
- Create: `test/mobile_car_wash/operations/appointment_checklist_wrap_up_test.exs`
- Modify: `lib/mobile_car_wash/operations/appointment_checklist.ex`

**Interfaces:**
- Produces: `MobileCarWash.Operations.AppointmentChecklist.final_notes :: String.t() | nil`
- Produces: `AppointmentChecklist` update action `:save_wrap_up` accepting `%{final_notes: String.t() | nil}`
- Consumes: existing `AppointmentChecklist` `:create` action and appointment/procedure relationships.

- [ ] **Step 1: Generate the migration**

Run:

```bash
mix ecto.gen.migration add_final_notes_to_appointment_checklists
```

Expected: a new file under `priv/repo/migrations/` named like `*_add_final_notes_to_appointment_checklists.exs`.

- [ ] **Step 2: Fill in the migration**

Edit the generated migration to exactly this shape:

```elixir
defmodule MobileCarWash.Repo.Migrations.AddFinalNotesToAppointmentChecklists do
  use Ecto.Migration

  def change do
    alter table(:appointment_checklists) do
      add :final_notes, :text
    end
  end
end
```

- [ ] **Step 3: Write the failing resource test**

Create `test/mobile_car_wash/operations/appointment_checklist_wrap_up_test.exs`:

```elixir
defmodule MobileCarWash.Operations.AppointmentChecklistWrapUpTest do
  use MobileCarWash.DataCase, async: true

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Fleet.{Address, Vehicle}
  alias MobileCarWash.Operations.{AppointmentChecklist, Procedure}
  alias MobileCarWash.Scheduling.{Appointment, ServiceType}

  test "save_wrap_up persists final notes" do
    checklist = create_checklist!()

    {:ok, updated} =
      checklist
      |> Ash.Changeset.for_update(:save_wrap_up, %{final_notes: "Customer loved the shine."})
      |> Ash.update(authorize?: false)

    assert updated.final_notes == "Customer loved the shine."

    reloaded = Ash.get!(AppointmentChecklist, checklist.id, authorize?: false)
    assert reloaded.final_notes == "Customer loved the shine."
  end

  test "save_wrap_up accepts a blank final note" do
    checklist = create_checklist!()

    {:ok, updated} =
      checklist
      |> Ash.Changeset.for_update(:save_wrap_up, %{final_notes: ""})
      |> Ash.update(authorize?: false)

    assert updated.final_notes == ""
  end

  defp create_checklist! do
    {:ok, customer} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "wrap-checklist-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Wrap Customer",
        phone: "+15125550900"
      })
      |> Ash.create()

    {:ok, service} =
      ServiceType
      |> Ash.Changeset.for_create(:create, %{
        name: "Wrap Wash",
        slug: "wrap-wash-#{System.unique_integer([:positive])}",
        base_price_cents: 5_000,
        duration_minutes: 45
      })
      |> Ash.create()

    {:ok, vehicle} =
      Vehicle
      |> Ash.Changeset.for_create(:create, %{make: "Toyota", model: "Camry"})
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create()

    {:ok, address} =
      Address
      |> Ash.Changeset.for_create(:create, %{
        street: "100 Wrap Ave",
        city: "San Antonio",
        state: "TX",
        zip: "78259"
      })
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create()

    {:ok, appointment} =
      Appointment
      |> Ash.Changeset.for_create(:book, %{
        customer_id: customer.id,
        vehicle_id: vehicle.id,
        address_id: address.id,
        service_type_id: service.id,
        scheduled_at:
          DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second),
        price_cents: 5_000,
        duration_minutes: 45
      })
      |> Ash.create()

    {:ok, procedure} =
      Procedure
      |> Ash.Changeset.for_create(:create, %{
        name: "Wrap SOP",
        slug: "wrap-sop-#{System.unique_integer([:positive])}"
      })
      |> Ash.Changeset.force_change_attribute(:service_type_id, service.id)
      |> Ash.create()

    AppointmentChecklist
    |> Ash.Changeset.for_create(:create, %{status: :completed})
    |> Ash.Changeset.force_change_attribute(:appointment_id, appointment.id)
    |> Ash.Changeset.force_change_attribute(:procedure_id, procedure.id)
    |> Ash.create!(authorize?: false)
  end
end
```

- [ ] **Step 4: Run the resource test to verify RED**

Run:

```bash
mix test test/mobile_car_wash/operations/appointment_checklist_wrap_up_test.exs
```

Expected: FAIL because `:save_wrap_up` and/or `final_notes` does not exist.

- [ ] **Step 5: Add the resource attribute and action**

In `lib/mobile_car_wash/operations/appointment_checklist.ex`, add this attribute inside `attributes do` after `completed_at`:

```elixir
    attribute :final_notes, :string do
      public?(true)
    end
```

Add this action inside `actions do` after `complete_checklist`:

```elixir
    update :save_wrap_up do
      accept([:final_notes])
    end
```

- [ ] **Step 6: Migrate and verify GREEN**

Run:

```bash
mix ecto.migrate
mix test test/mobile_car_wash/operations/appointment_checklist_wrap_up_test.exs
```

Expected: `2 tests, 0 failures`.

- [ ] **Step 7: Commit**

```bash
git add lib/mobile_car_wash/operations/appointment_checklist.ex priv/repo/migrations test/mobile_car_wash/operations/appointment_checklist_wrap_up_test.exs
git commit -m "Add checklist wrap-up notes"
```

---

### Task 2: Wash Command Card

**Files:**
- Modify: `lib/mobile_car_wash_web/live/checklist_live.ex`
- Modify: `test/mobile_car_wash_web/live/checklist_live_test.exs`

**Interfaces:**
- Consumes: existing `before_photos_complete?/1`, `after_photos_complete?/1`, `all_required_complete?/1`, `current_progress_item/1`, `start_step`, and `complete_step`.
- Produces: private helper `wash_command(assigns :: map()) :: map()`
- Produces DOM selectors:
  - `#wash-command-card`
  - `[data-role='wash-primary-action']`
  - `#wash-command-before-photos`
  - `#wash-command-start-step`
  - `#wash-command-complete-step`
  - `#wash-command-after-photos`
  - `#wash-command-wrap-up`
  - `#wash-command-dashboard`

- [ ] **Step 1: Add command-card test helpers**

In `test/mobile_car_wash_web/live/checklist_live_test.exs`, add these helpers after `create_photo/4`:

```elixir
  defp create_all_photos!(appointment, photo_type) do
    for area <- [:front, :rear, :driver_side, :passenger_side, :interior, :wheels] do
      create_photo(appointment, photo_type, area)
    end
  end

  defp checklist_items(checklist) do
    ChecklistItem
    |> Ash.Query.filter(checklist_id == ^checklist.id)
    |> Ash.Query.sort(step_number: :asc)
    |> Ash.read!(authorize?: false)
  end

  defp start_item!(item) do
    item
    |> Ash.Changeset.for_update(:start_step, %{})
    |> Ash.update!(authorize?: false)
  end

  defp complete_item!(item) do
    item
    |> Ash.Changeset.for_update(:check, %{})
    |> Ash.update!(authorize?: false)
  end

  defp primary_action_count(html) do
    html
    |> Floki.parse_document!()
    |> Floki.find("[data-role='wash-primary-action']")
    |> length()
  end
```

The test module already uses `async: false`, so no further async changes are required.

- [ ] **Step 2: Write failing command-card tests**

Append this describe block after `"active wash regions"`:

```elixir
  describe "wash command card" do
    setup %{conn: conn} do
      user = create_tech_customer()
      tech = create_tech_record(user)
      customer = create_customer()
      appointment = create_appointment(customer.id, tech.id, :in_progress)
      checklist = create_checklist(appointment, :in_progress)

      {:ok,
       conn: sign_in(conn, user),
       tech: tech,
       customer: customer,
       appointment: appointment,
       checklist: checklist}
    end

    test "points to before photos when required before photos are missing", %{
      conn: conn,
      checklist: checklist
    } do
      {:ok, view, html} = live(conn, ~p"/tech/checklist/#{checklist.id}")

      assert has_element?(view, "#wash-command-card")
      assert has_element?(view, "#wash-command-before-photos[href='#before-photo-progress']")
      assert html =~ "Finish before photos"
      assert primary_action_count(html) == 1
    end

    test "starts the next step after before photos are complete", %{
      conn: conn,
      appointment: appointment,
      checklist: checklist
    } do
      create_all_photos!(appointment, :before)

      {:ok, view, html} = live(conn, ~p"/tech/checklist/#{checklist.id}")
      [first | _] = checklist_items(checklist)

      assert has_element?(
               view,
               "#wash-command-start-step[phx-click='start_step'][phx-value-id='#{first.id}']",
               "Start Pre-rinse"
             )

      assert primary_action_count(html) == 1
    end

    test "completes the active step when a step is running", %{
      conn: conn,
      appointment: appointment,
      checklist: checklist
    } do
      create_all_photos!(appointment, :before)
      [first | _] = checklist_items(checklist)
      start_item!(first)

      {:ok, view, html} = live(conn, ~p"/tech/checklist/#{checklist.id}")

      assert has_element?(
               view,
               "#wash-command-complete-step[phx-click='complete_step'][phx-value-id='#{first.id}']",
               "Complete Pre-rinse"
             )

      assert primary_action_count(html) == 1
    end

    test "points to after photos after required steps are complete", %{
      conn: conn,
      appointment: appointment,
      checklist: checklist
    } do
      create_all_photos!(appointment, :before)
      checklist |> checklist_items() |> Enum.each(&complete_item!/1)

      {:ok, view, html} = live(conn, ~p"/tech/checklist/#{checklist.id}")

      assert has_element?(view, "#wash-command-after-photos[href='#after-photo-progress']")
      assert html =~ "Finish after photos"
      assert primary_action_count(html) == 1
    end

    test "points to wrap-up after after photos complete", %{
      conn: conn,
      appointment: appointment,
      checklist: checklist
    } do
      create_all_photos!(appointment, :before)
      checklist |> checklist_items() |> Enum.each(&complete_item!/1)
      create_all_photos!(appointment, :after)

      {:ok, view, html} = live(conn, ~p"/tech/checklist/#{checklist.id}")

      assert has_element?(view, "#wash-command-wrap-up[href='#wrap-up-panel']")
      assert html =~ "Wrap up"
      assert primary_action_count(html) == 1
    end
  end
```

- [ ] **Step 3: Run command-card tests to verify RED**

Run:

```bash
mix test test/mobile_car_wash_web/live/checklist_live_test.exs --only describe:"wash command card"
```

Expected: FAIL because `#wash-command-card` does not exist.

- [ ] **Step 4: Assign and render the command card**

In `lib/mobile_car_wash_web/live/checklist_live.ex`, no mount assign is required if `wash_command(assigns)` derives from existing assigns in render.

Inside `render/1`, immediately inside `<div id="active-wash" class="space-y-6">`, before `<section id="wash-progress-header"...>`, add:

```elixir
          <.wash_command_card command={wash_command(assigns)} />
```

Add this function component near `photo_tile/1`:

```elixir
  defp wash_command_card(assigns) do
    ~H"""
    <section
      id="wash-command-card"
      class="rounded-[28px] border border-primary/20 bg-base-100 px-4 py-4 shadow-sm"
    >
      <div class="flex items-start justify-between gap-3">
        <div>
          <p class="text-xs font-semibold uppercase tracking-[0.18em] text-primary/70">
            Now
          </p>
          <h2 class="mt-1 text-xl font-bold">{@command.title}</h2>
          <p class="mt-1 text-sm text-base-content/70">{@command.body}</p>
        </div>
        <span class={["badge", @command.badge_class]}>{@command.badge}</span>
      </div>

      <div class="mt-4">
        <%= case @command.action do %>
          <% %{type: :anchor, id: id, to: to, label: label} -> %>
            <a
              id={id}
              href={to}
              data-role="wash-primary-action"
              class="btn btn-primary w-full"
            >
              {label}
            </a>
          <% %{type: :event, id: id, event: event, item_id: item_id, label: label} -> %>
            <button
              id={id}
              type="button"
              phx-click={event}
              phx-value-id={item_id}
              data-role="wash-primary-action"
              class="btn btn-primary w-full"
            >
              {label}
            </button>
          <% %{type: :navigate, id: id, to: to, label: label} -> %>
            <.link
              id={id}
              navigate={to}
              data-role="wash-primary-action"
              class="btn btn-primary w-full"
            >
              {label}
            </.link>
          <% nil -> %>
            <p id="wash-command-no-action" class="text-sm text-base-content/60">
              No action needed right now.
            </p>
        <% end %>
      </div>
    </section>
    """
  end
```

Add these helpers near the timer/status helpers:

```elixir
  defp wash_command(%{checklist: %{status: :completed, final_notes: final_notes}})
       when not is_nil(final_notes) do
    %{
      title: "Wash complete",
      body: "Review wrap-up details, then return to your dashboard for the next assignment.",
      badge: "Done",
      badge_class: "badge-success",
      action: %{type: :navigate, id: "wash-command-dashboard", to: ~p"/tech", label: "Back to dashboard"}
    }
  end

  defp wash_command(assigns) do
    cond do
      not before_photos_complete?(assigns.before_photos) ->
        %{
          title: "Finish before photos",
          body: "Capture every required angle before starting checklist steps.",
          badge: "Photos",
          badge_class: "badge-warning",
          action: %{type: :anchor, id: "wash-command-before-photos", to: "#before-photo-progress", label: "Finish before photos"}
        }

      active = Enum.find(assigns.items, &(&1.started_at && !&1.completed)) ->
        %{
          title: "Complete #{active.title}",
          body: "Timer is running. Finish this step when the work is done.",
          badge: "Active",
          badge_class: "badge-info",
          action: %{type: :event, id: "wash-command-complete-step", event: "complete_step", item_id: active.id, label: "Complete #{active.title}"}
        }

      next = Enum.find(assigns.items, &(not &1.completed)) ->
        %{
          title: "Start #{next.title}",
          body: "Before photos are complete. Start the next checklist step.",
          badge: "Step",
          badge_class: "badge-primary",
          action: %{type: :event, id: "wash-command-start-step", event: "start_step", item_id: next.id, label: "Start #{next.title}"}
        }

      not after_photos_complete?(assigns.after_photos) ->
        %{
          title: "Finish after photos",
          body: "All required steps are complete. Match the before photos before wrap-up.",
          badge: "Photos",
          badge_class: "badge-success",
          action: %{type: :anchor, id: "wash-command-after-photos", to: "#after-photo-progress", label: "Finish after photos"}
        }

      true ->
        %{
          title: "Wrap up",
          body: "Photos and steps are complete. Add final notes and supplies used.",
          badge: "Wrap-up",
          badge_class: "badge-success",
          action: %{type: :anchor, id: "wash-command-wrap-up", to: "#wrap-up-panel", label: "Wrap up"}
        }
    end
  end
```

If the formatter wraps long map literals, keep the same keys and ids.

- [ ] **Step 5: Run tests to verify GREEN**

Run:

```bash
mix test test/mobile_car_wash_web/live/checklist_live_test.exs --only describe:"wash command card"
mix test test/mobile_car_wash_web/live/checklist_live_test.exs
```

Expected: command-card tests pass, then the full checklist suite passes.

- [ ] **Step 6: Commit**

```bash
git add lib/mobile_car_wash_web/live/checklist_live.ex test/mobile_car_wash_web/live/checklist_live_test.exs
git commit -m "Add active wash command card"
```

---

### Task 3: Wrap-Up Form And Final Notes

**Files:**
- Modify: `lib/mobile_car_wash_web/live/checklist_live.ex`
- Modify: `test/mobile_car_wash_web/live/checklist_live_test.exs`

**Interfaces:**
- Consumes: Task 1 `AppointmentChecklist :save_wrap_up`.
- Consumes: Task 2 `#wash-command-wrap-up`.
- Produces event: `save_wrap_up` accepting `%{"wrap_up" => %{"final_notes" => String.t(), "supplies" => map()}}`
- Produces selectors:
  - `#wrap-up-form`
  - `#wrap-up-final-notes`
  - `#wrap-up-save`
  - `#wrap-up-saved-final-notes`
  - `#wrap-up-error`

- [ ] **Step 1: Write failing final-note LiveView tests**

Append this describe block to `test/mobile_car_wash_web/live/checklist_live_test.exs`:

```elixir
  describe "wrap-up final notes" do
    setup %{conn: conn} do
      user = create_tech_customer()
      tech = create_tech_record(user)
      customer = create_customer()
      appointment = create_appointment(customer.id, tech.id, :in_progress)
      checklist = create_checklist(appointment, :in_progress)
      create_all_photos!(appointment, :before)
      checklist |> checklist_items() |> Enum.each(&complete_item!/1)
      create_all_photos!(appointment, :after)

      {:ok,
       conn: sign_in(conn, user),
       tech: tech,
       customer: customer,
       appointment: appointment,
       checklist: checklist}
    end

    test "persists final notes from the wrap-up form", %{conn: conn, checklist: checklist} do
      {:ok, view, _html} = live(conn, ~p"/tech/checklist/#{checklist.id}")

      assert has_element?(view, "#wrap-up-form")
      assert has_element?(view, "#wrap-up-final-notes")

      view
      |> form("#wrap-up-form", %{
        "wrap_up" => %{
          "final_notes" => "Customer requested extra attention on wheels.",
          "supplies" => %{}
        }
      })
      |> render_submit()

      reloaded = Ash.get!(AppointmentChecklist, checklist.id, authorize?: false)
      assert reloaded.final_notes == "Customer requested extra attention on wheels."
      assert has_element?(view, "#wrap-up-saved-final-notes")
      assert render(view) =~ "Customer requested extra attention on wheels."
    end

    test "can save wrap-up with blank notes", %{conn: conn, checklist: checklist} do
      {:ok, view, _html} = live(conn, ~p"/tech/checklist/#{checklist.id}")

      view
      |> form("#wrap-up-form", %{"wrap_up" => %{"final_notes" => "", "supplies" => %{}}})
      |> render_submit()

      reloaded = Ash.get!(AppointmentChecklist, checklist.id, authorize?: false)
      assert reloaded.final_notes == ""
      assert render(view) =~ "Wrap-up saved"
    end
  end
```

- [ ] **Step 2: Run tests to verify RED**

Run:

```bash
mix test test/mobile_car_wash_web/live/checklist_live_test.exs --only describe:"wrap-up final notes"
```

Expected: FAIL because `#wrap-up-form` does not exist.

- [ ] **Step 3: Add wrap-up assigns in mount**

In the successful checklist branch of `mount/3`, add these keys to the main `assign(...)`:

```elixir
            supply_usages: MobileCarWash.Inventory.usage_for_appointment(appointment.id),
            wrap_up_error: nil,
            wrap_up_saved?: not is_nil(checklist.final_notes)
```

In the error/no-checklist assigns, add:

```elixir
           supply_usages: [],
           wrap_up_error: nil,
           wrap_up_saved?: false
```

- [ ] **Step 4: Add the save event**

In `ChecklistLive`, add this event handler near the note/skip handlers:

```elixir
  def handle_event("save_wrap_up", %{"wrap_up" => params}, socket) do
    final_notes = Map.get(params, "final_notes", "")

    case save_wrap_up_notes(socket.assigns.checklist, final_notes) do
      {:ok, checklist} ->
        {:noreply,
         socket
         |> assign(checklist: checklist, wrap_up_error: nil, wrap_up_saved?: true)
         |> assign(supply_usages: MobileCarWash.Inventory.usage_for_appointment(socket.assigns.appointment.id))}

      {:error, reason} ->
        {:noreply,
         assign(socket,
           wrap_up_error: "Could not save wrap-up notes: #{inspect(reason)}",
           wrap_up_saved?: false
         )}
    end
  end

  defp save_wrap_up_notes(checklist, final_notes) do
    checklist
    |> Ash.Changeset.for_update(:save_wrap_up, %{final_notes: final_notes})
    |> Ash.update(authorize?: false)
  end
```

- [ ] **Step 5: Replace the completed panel with a wrap-up-ready form shell**

Change the `#wrap-up-panel` section condition from:

```elixir
            :if={@checklist.status == :completed}
```

to:

```elixir
            :if={wrap_up_ready?(@items, @after_photos, @checklist)}
```

Add this helper near the existing completion helpers:

```elixir
  defp wrap_up_ready?(_items, _after_photos, %{status: :completed}), do: true

  defp wrap_up_ready?(items, after_photos, _checklist) do
    all_required_complete?(items) and after_photos_complete?(after_photos)
  end
```

Then keep the time analysis markup but add this form before the time analysis card:

```elixir
            <form
              id="wrap-up-form"
              phx-submit="save_wrap_up"
              class="mx-auto mt-4 max-w-sm space-y-3 text-left"
            >
              <label class="form-control">
                <span class="label-text font-semibold">Final notes</span>
                <textarea
                  id="wrap-up-final-notes"
                  name="wrap_up[final_notes]"
                  class="textarea textarea-bordered min-h-24"
                  placeholder="Anything dispatch or admin should know?"
                >{@checklist.final_notes}</textarea>
              </label>

              <input type="hidden" name="wrap_up[supplies]" value="" />

              <p :if={@wrap_up_error} id="wrap-up-error" class="text-sm font-semibold text-error">
                {@wrap_up_error}
              </p>

              <button id="wrap-up-save" type="submit" class="btn btn-success w-full">
                Save wrap-up
              </button>
            </form>

            <div
              :if={@wrap_up_saved?}
              id="wrap-up-saved-final-notes"
              class="mx-auto mt-4 max-w-sm rounded-2xl bg-base-100 px-4 py-3 text-left text-sm shadow"
            >
              <p class="font-semibold text-success">Wrap-up saved</p>
              <p class="mt-1 text-base-content/70">
                {if @checklist.final_notes in [nil, ""], do: "No final notes entered.", else: @checklist.final_notes}
              </p>
            </div>
```

Keep `<.lightbox_root />` unchanged.

- [ ] **Step 6: Run tests to verify GREEN**

Run:

```bash
mix test test/mobile_car_wash_web/live/checklist_live_test.exs --only describe:"wrap-up final notes"
mix test test/mobile_car_wash_web/live/checklist_live_test.exs
```

Expected: wrap-up note tests pass, then the full checklist suite passes.

- [ ] **Step 7: Commit**

```bash
git add lib/mobile_car_wash_web/live/checklist_live.ex test/mobile_car_wash_web/live/checklist_live_test.exs
git commit -m "Persist checklist wrap-up notes"
```

---

### Task 4: Supply Usage And Earnings In Wrap-Up

**Files:**
- Modify: `lib/mobile_car_wash_web/live/checklist_live.ex`
- Modify: `test/mobile_car_wash_web/live/checklist_live_test.exs`

**Interfaces:**
- Consumes: `MobileCarWash.Inventory.list_supplies/0`
- Consumes: `MobileCarWash.Inventory.log_usage/1`
- Consumes: `MobileCarWash.Operations.TechEarnings.wash_earnings/2`
- Produces selectors:
  - `#wrap-up-supply-0`
  - `#wrap-up-supply-0-quantity`
  - `#wrap-up-supply-0-note`
  - `#wrap-up-usage-list`
  - `#wrap-up-earnings`

- [ ] **Step 1: Add imports/aliases for tests**

In `test/mobile_car_wash_web/live/checklist_live_test.exs`, add:

```elixir
  alias MobileCarWash.Inventory.{Supply, SupplyUsage}
```

near the other aliases.

Add this helper after `complete_item!/1`:

```elixir
  defp create_supply!(attrs \\ %{}) do
    Supply
    |> Ash.Changeset.for_create(
      :create,
      Map.merge(
        %{
          name: "Soap #{System.unique_integer([:positive])}",
          category: :chemicals,
          unit: "oz",
          quantity_on_hand: Decimal.new("32"),
          active: true
        },
        attrs
      )
    )
    |> Ash.create!(authorize?: false)
  end
```

- [ ] **Step 2: Write failing supply and earnings tests**

Append these tests inside the `"wrap-up final notes"` describe block:

```elixir
    test "logs supply usage and decrements inventory", %{
      conn: conn,
      tech: tech,
      appointment: appointment,
      checklist: checklist
    } do
      supply = create_supply!(name: "Foam Soap", quantity_on_hand: Decimal.new("16"))

      {:ok, view, _html} = live(conn, ~p"/tech/checklist/#{checklist.id}")

      view
      |> form("#wrap-up-form", %{
        "wrap_up" => %{
          "final_notes" => "Used normal soap amount.",
          "supplies" => %{
            "0" => %{
              "supply_id" => supply.id,
              "quantity_used" => "2.5",
              "notes" => "Foam pass"
            }
          }
        }
      })
      |> render_submit()

      usages =
        SupplyUsage
        |> Ash.Query.filter(appointment_id == ^appointment.id)
        |> Ash.read!(authorize?: false)

      assert [
               %{
                 supply_id: supply_id,
                 technician_id: technician_id,
                 quantity_used: quantity_used,
                 notes: "Foam pass"
               }
             ] = usages

      assert supply_id == supply.id
      assert technician_id == tech.id
      assert Decimal.equal?(quantity_used, Decimal.new("2.5"))

      reloaded_supply = Ash.get!(Supply, supply.id, authorize?: false)
      assert Decimal.equal?(reloaded_supply.quantity_on_hand, Decimal.new("13.5"))

      assert has_element?(view, "#wrap-up-usage-list")
      assert render(view) =~ "Foam Soap"
    end

    test "invalid supply quantity shows an inline error and creates no usage", %{
      conn: conn,
      appointment: appointment,
      checklist: checklist
    } do
      supply = create_supply!(name: "Interior Cleaner")

      {:ok, view, _html} = live(conn, ~p"/tech/checklist/#{checklist.id}")

      view
      |> form("#wrap-up-form", %{
        "wrap_up" => %{
          "final_notes" => "",
          "supplies" => %{
            "0" => %{"supply_id" => supply.id, "quantity_used" => "0", "notes" => ""}
          }
        }
      })
      |> render_submit()

      assert has_element?(view, "#wrap-up-error")
      assert render(view) =~ "Enter a quantity greater than 0"

      usages =
        SupplyUsage
        |> Ash.Query.filter(appointment_id == ^appointment.id)
        |> Ash.read!(authorize?: false)

      assert usages == []
    end

    test "renders flat-rate earnings summary", %{conn: conn, checklist: checklist} do
      {:ok, view, _html} = live(conn, ~p"/tech/checklist/#{checklist.id}")

      assert has_element?(view, "#wrap-up-earnings")
      assert render(view) =~ "$25.00"
    end
```

The default `create_tech_record/1` helper creates technicians without a pay rate, and `TechEarnings.wash_earnings/2` falls back to `$25.00`.

- [ ] **Step 3: Run tests to verify RED**

Run:

```bash
mix test test/mobile_car_wash_web/live/checklist_live_test.exs --only describe:"wrap-up final notes"
```

Expected: FAIL because supply inputs and earnings markup do not exist.

- [ ] **Step 4: Load supplies in mount**

In the successful checklist branch of `mount/3`, add:

```elixir
            supplies: MobileCarWash.Inventory.list_supplies(),
```

In the error/no-checklist assigns, add:

```elixir
           supplies: [],
```

If the file has no alias for `MobileCarWash.Inventory`, use the full module name in this task to keep the diff small.

- [ ] **Step 5: Render one supply row, usage list, and earnings**

Inside `#wrap-up-form`, replace the hidden `wrap_up[supplies]` input from Task 3 with a fixed three-row supply logger. This avoids adding client-side dynamic form behavior while still allowing multiple supplies:

```elixir
              <div class="rounded-2xl border border-base-300 bg-base-100 p-3">
                <div class="mb-2 flex items-center justify-between gap-3">
                  <span class="text-sm font-semibold">Supplies used</span>
                  <span :if={@supplies == []} class="text-xs text-base-content/60">
                    No supplies to log
                  </span>
                </div>

                <div
                  :for={index <- 0..2}
                  :if={@supplies != []}
                  id={"wrap-up-supply-#{index}"}
                  class="space-y-2 border-t border-base-200 pt-2 first:border-t-0 first:pt-0"
                >
                  <select name={"wrap_up[supplies][#{index}][supply_id]"} class="select select-bordered select-sm w-full">
                    <option value="">No supply</option>
                    <option :for={supply <- @supplies} value={supply.id}>
                      {supply.name} ({format_decimal(supply.quantity_on_hand)} {supply.unit})
                    </option>
                  </select>
                  <input
                    id={"wrap-up-supply-#{index}-quantity"}
                    type="number"
                    min="0"
                    step="0.01"
                    name={"wrap_up[supplies][#{index}][quantity_used]"}
                    class="input input-bordered input-sm w-full"
                    placeholder="Quantity used"
                  />
                  <input
                    id={"wrap-up-supply-#{index}-note"}
                    type="text"
                    name={"wrap_up[supplies][#{index}][notes]"}
                    class="input input-bordered input-sm w-full"
                    placeholder="Supply note"
                  />
                </div>
              </div>
```

Add this block below the saved-final-notes block:

```elixir
            <div
              :if={@supply_usages != []}
              id="wrap-up-usage-list"
              class="mx-auto mt-4 max-w-sm rounded-2xl bg-base-100 px-4 py-3 text-left text-sm shadow"
            >
              <p class="font-semibold">Logged supplies</p>
              <div :for={usage <- @supply_usages} class="mt-2 flex justify-between gap-3 text-xs">
                <span>{supply_name(@supplies, usage.supply_id)}</span>
                <span>{format_decimal(usage.quantity_used)}</span>
              </div>
            </div>

            <div
              id="wrap-up-earnings"
              class="mx-auto mt-4 max-w-sm rounded-2xl bg-base-100 px-4 py-3 text-left shadow"
            >
              <p class="text-sm font-semibold">Estimated job earnings</p>
              <p class="mt-1 text-2xl font-bold text-success">{format_cents(wrap_up_earnings(@appointment))}</p>
            </div>
```

Add helpers near the bottom:

```elixir
  defp supply_name(supplies, supply_id) do
    case Enum.find(supplies, &(&1.id == supply_id)) do
      nil -> "Supply"
      supply -> supply.name
    end
  end

  defp format_decimal(%Decimal{} = decimal), do: Decimal.to_string(decimal, :normal)
  defp format_decimal(value), do: to_string(value)

  defp format_cents(cents) when is_integer(cents) do
    dollars = div(cents, 100)
    cents_part = cents |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")
    "$#{dollars}.#{cents_part}"
  end

  defp format_cents(_), do: "Not available"

  defp wrap_up_earnings(%{technician_id: nil}), do: nil

  defp wrap_up_earnings(%{technician_id: technician_id, price_cents: price_cents}) do
    case Ash.get(MobileCarWash.Operations.Technician, technician_id, authorize?: false) do
      {:ok, technician} ->
        MobileCarWash.Operations.TechEarnings.wash_earnings(%{price_cents: price_cents}, technician)

      _ ->
        nil
    end
  end
```

- [ ] **Step 6: Parse and log supply rows on submit**

Replace the `save_wrap_up` event from Task 3 with:

```elixir
  def handle_event("save_wrap_up", %{"wrap_up" => params}, socket) do
    final_notes = Map.get(params, "final_notes", "")
    supply_rows = params |> Map.get("supplies", %{}) |> normalize_supply_rows()

    with {:ok, usage_attrs} <- build_usage_attrs(supply_rows, socket.assigns.appointment),
         {:ok, checklist} <- save_wrap_up_notes(socket.assigns.checklist, final_notes),
         :ok <- log_supply_usage(usage_attrs) do
      {:noreply,
       socket
       |> assign(checklist: checklist, wrap_up_error: nil, wrap_up_saved?: true)
       |> assign(supplies: MobileCarWash.Inventory.list_supplies())
       |> assign(supply_usages: MobileCarWash.Inventory.usage_for_appointment(socket.assigns.appointment.id))}
    else
      {:error, message} when is_binary(message) ->
        {:noreply, assign(socket, wrap_up_error: message, wrap_up_saved?: false)}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(wrap_up_error: "Could not save wrap-up: #{inspect(reason)}", wrap_up_saved?: false)
         |> assign(supply_usages: MobileCarWash.Inventory.usage_for_appointment(socket.assigns.appointment.id))}
    end
  end
```

Add these helpers:

```elixir
  defp normalize_supply_rows(rows) when is_map(rows) do
    rows
    |> Map.values()
    |> Enum.filter(fn row ->
      row["supply_id"] not in [nil, ""] or row["quantity_used"] not in [nil, ""]
    end)
  end

  defp normalize_supply_rows(_), do: []

  defp build_usage_attrs(rows, appointment) do
    rows
    |> Enum.reduce_while({:ok, []}, fn row, {:ok, attrs} ->
      case build_usage_attr(row, appointment) do
        {:ok, attr} -> {:cont, {:ok, [attr | attrs]}}
        {:error, message} -> {:halt, {:error, message}}
      end
    end)
    |> case do
      {:ok, attrs} -> {:ok, Enum.reverse(attrs)}
      error -> error
    end
  end

  defp build_usage_attr(%{"supply_id" => supply_id}, _appointment) when supply_id in [nil, ""] do
    {:error, "Choose a supply or leave the supply row blank."}
  end

  defp build_usage_attr(row, appointment) do
    with {:ok, quantity} <- parse_positive_decimal(row["quantity_used"]) do
      {:ok,
       %{
         supply_id: row["supply_id"],
         appointment_id: appointment.id,
         technician_id: appointment.technician_id,
         van_id: nil,
         quantity_used: quantity,
         notes: blank_to_nil(row["notes"])
       }}
    end
  end

  defp parse_positive_decimal(value) do
    case Decimal.parse(to_string(value || "")) do
      {decimal, ""} ->
        if Decimal.compare(decimal, Decimal.new("0")) == :gt do
          {:ok, decimal}
        else
          {:error, "Enter a quantity greater than 0."}
        end

      _ ->
        {:error, "Enter a quantity greater than 0."}
    end
  end

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value

  defp log_supply_usage(attrs) do
    Enum.reduce_while(attrs, :ok, fn attr, :ok ->
      case MobileCarWash.Inventory.log_usage(attr) do
        {:ok, _usage} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end
```

If the formatter changes line breaks, keep the behavior and helper names exactly.

- [ ] **Step 7: Run tests to verify GREEN**

Run:

```bash
mix test test/mobile_car_wash_web/live/checklist_live_test.exs --only describe:"wrap-up final notes"
mix test test/mobile_car_wash_web/live/checklist_live_test.exs
```

Expected: wrap-up supply and earnings tests pass, then the full checklist suite passes.

- [ ] **Step 8: Commit**

```bash
git add lib/mobile_car_wash_web/live/checklist_live.ex test/mobile_car_wash_web/live/checklist_live_test.exs
git commit -m "Log supplies during checklist wrap-up"
```

---

### Task 5: Regression Polish And Verification

**Files:**
- Modify: `lib/mobile_car_wash_web/live/checklist_live.ex`
- Modify: `test/mobile_car_wash_web/live/checklist_live_test.exs`

**Interfaces:**
- Consumes all prior task interfaces.
- Produces final verified active-wash and wrap-up UX.

- [ ] **Step 1: Add completed-state command and read-only regression tests**

Append these tests to the `"wrap-up final notes"` describe block or a new `"wrap-up completed state"` describe block:

```elixir
    test "completed checklist command returns to dashboard", %{
      conn: conn,
      appointment: appointment,
      checklist: checklist
    } do
      create_all_photos!(appointment, :before)
      create_all_photos!(appointment, :after)

      {:ok, checklist} =
        checklist
        |> Ash.Changeset.for_update(:complete_checklist, %{})
        |> Ash.update(authorize?: false)

      {:ok, view, html} = live(conn, ~p"/tech/checklist/#{checklist.id}")

      assert has_element?(view, "#wash-command-dashboard[href='/tech']", "Back to dashboard")
      assert primary_action_count(html) == 1
      refute has_element?(view, "#before-photo-form input[type='file']")
      refute has_element?(view, "#after-photo-form input[type='file']")
    end

    test "saving wrap-up does not remove lightbox wiring or time analysis", %{
      conn: conn,
      appointment: appointment,
      checklist: checklist
    } do
      create_photo(appointment, :problem_area, :front, "Bug marks")

      {:ok, view, _html} = live(conn, ~p"/tech/checklist/#{checklist.id}")

      view
      |> form("#wrap-up-form", %{"wrap_up" => %{"final_notes" => "Done", "supplies" => %{}}})
      |> render_submit()

      html = render(view)
      assert html =~ ~s(data-lightbox="problem-photos")
      assert has_element?(view, "#wrap-up-panel")
      assert html =~ "Time Analysis"
    end
```

- [ ] **Step 2: Run focused checklist tests**

Run:

```bash
mix test test/mobile_car_wash_web/live/checklist_live_test.exs
```

Expected: all checklist tests pass.

- [ ] **Step 3: Run adjacent tech-flow tests**

Run:

```bash
mix test test/mobile_car_wash_web/live/tech/tech_dashboard_live_test.exs test/mobile_car_wash_web/live/tech/job_live_test.exs
```

Expected: all adjacent tech dashboard and job brief tests pass.

- [ ] **Step 4: Run formatter check on touched files**

Run:

```bash
mix format --check-formatted lib/mobile_car_wash/operations/appointment_checklist.ex lib/mobile_car_wash_web/live/checklist_live.ex test/mobile_car_wash/operations/appointment_checklist_wrap_up_test.exs test/mobile_car_wash_web/live/checklist_live_test.exs
```

Expected: exit 0.

- [ ] **Step 5: Run full precommit**

Run:

```bash
mix precommit
```

Expected: full suite passes. Existing Ash missed-notification warnings may print, but failures must be fixed before finishing.

- [ ] **Step 6: Commit final polish if any files changed**

If Step 1 or verification fixes changed files:

```bash
git add lib/mobile_car_wash_web/live/checklist_live.ex test/mobile_car_wash_web/live/checklist_live_test.exs
git commit -m "Polish active wash wrap-up regressions"
```

If no files changed after Task 4, do not create an empty commit.
