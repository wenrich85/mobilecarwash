defmodule MobileCarWashWeb.ChecklistLive do
  @moduledoc """
  Interactive technician checklist with live step timers.

  Timer colors:
  - Green: within estimated time
  - Yellow: 45 seconds remaining
  - Red: over time

  Photo flow:
  - Tech must upload BEFORE photos for all key areas before starting any steps.
  - Tech must upload AFTER photos for all key areas before wash can complete.
  - Before/after photos are paired by area for side-by-side documentation.

  Every step completion broadcasts to the customer's status page via PubSub.
  Actual vs estimated time is recorded for process optimization.
  """
  use MobileCarWashWeb, :live_view

  alias MobileCarWash.Booking.WashStateMachine
  alias MobileCarWash.Operations.{AppointmentChecklist, ChecklistItem, Photo, PhotoUpload}
  alias MobileCarWash.Scheduling.{Appointment, AppointmentTracker, WashOrchestrator}

  require Ash.Query

  @timer_tick_ms 1000

  # Key areas requiring before + after photos to document the wash.
  # 6 areas = 3 rows × 2 columns grid. Values must exist in Photo resource's car_part enum.
  @key_areas [
    %{id: :front, label: "Front", instruction: "Full front bumper & headlights"},
    %{id: :rear, label: "Rear", instruction: "Full rear bumper & taillights"},
    %{id: :driver_side, label: "Driver Side", instruction: "Full side panel, front to back"},
    %{
      id: :passenger_side,
      label: "Passenger Side",
      instruction: "Full side panel, front to back"
    },
    %{id: :interior, label: "Interior", instruction: "Dashboard, steering wheel & seats"},
    %{id: :wheels, label: "Wheels", instruction: "One wheel — representative of all"}
  ]
  @key_area_ids Enum.map(@key_areas, & &1.id)

  @impl true
  def mount(%{"id" => checklist_id}, _session, socket) do
    case Ash.get(AppointmentChecklist, checklist_id) do
      {:ok, checklist} ->
        items =
          ChecklistItem
          |> Ash.Query.filter(checklist_id == ^checklist.id)
          |> Ash.Query.sort(step_number: :asc)
          |> Ash.read!()

        appointment = Ash.get!(Appointment, checklist.appointment_id)

        problem_photos =
          Photo
          |> Ash.Query.filter(appointment_id == ^appointment.id and photo_type == :problem_area)
          |> Ash.read!()
          |> Enum.map(&PhotoUpload.apply_url/1)

        before_photos =
          Photo
          |> Ash.Query.filter(appointment_id == ^appointment.id and photo_type == :before)
          |> Ash.read!()
          |> Enum.map(&PhotoUpload.apply_url/1)

        after_photos =
          Photo
          |> Ash.Query.filter(appointment_id == ^appointment.id and photo_type == :after)
          |> Ash.read!()
          |> Enum.map(&PhotoUpload.apply_url/1)

        total = length(items)
        done = Enum.count(items, & &1.completed)
        pct = if total > 0, do: Float.round(done / total * 100, 0), else: 0

        if connected?(socket) do
          AppointmentTracker.subscribe(checklist.appointment_id)
          Process.send_after(self(), :tick, @timer_tick_ms)
        end

        socket =
          socket
          |> assign(
            page_title: "Checklist",
            checklist: checklist,
            items: items,
            appointment: appointment,
            problem_photos: problem_photos,
            before_photos: before_photos,
            after_photos: after_photos,
            key_areas: @key_areas,
            total: total,
            done: done,
            pct: pct,
            active_item_id: nil,
            elapsed_seconds: 0,
            show_photo_upload: nil,
            editing_note_id: nil,
            skipping_item_id: nil,
            now: DateTime.utc_now()
          )
          |> allow_upload(:photo,
            accept: ~w(.jpg .jpeg .png .webp),
            max_entries: 1,
            max_file_size: 10_000_000
          )

        {:ok, socket}

      {:error, _} ->
        {:ok,
         socket
         |> assign(
           page_title: "Checklist",
           checklist: nil,
           items: [],
           appointment: nil,
           problem_photos: [],
           before_photos: [],
           after_photos: [],
           key_areas: @key_areas,
           total: 0,
           done: 0,
           pct: 0,
           active_item_id: nil,
           elapsed_seconds: 0,
           show_photo_upload: nil,
           editing_note_id: nil,
           skipping_item_id: nil,
           now: DateTime.utc_now()
         )
         |> put_flash(:error, "Checklist not found")}
    end
  end

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Checklist",
       checklist: nil,
       items: [],
       appointment: nil,
       problem_photos: [],
       before_photos: [],
       after_photos: [],
       key_areas: @key_areas,
       total: 0,
       done: 0,
       pct: 0,
       active_item_id: nil,
       elapsed_seconds: 0,
       show_photo_upload: nil,
       editing_note_id: nil,
       skipping_item_id: nil,
       now: DateTime.utc_now()
     )}
  end

  # Timer tick
  @impl true
  def handle_info(:tick, socket) do
    Process.send_after(self(), :tick, @timer_tick_ms)
    {:noreply, assign(socket, now: DateTime.utc_now())}
  end

  # Photo uploaded elsewhere — reload our photo assigns
  def handle_info({:appointment_update, %{event: :photo_uploaded}}, socket) do
    {:noreply, reload_photos(socket)}
  end

  # Other appointment updates — reload checklist/items
  @impl true
  def handle_info({:appointment_update, _data}, socket) do
    case Ash.get(AppointmentChecklist, socket.assigns.checklist.id) do
      {:ok, checklist} ->
        items =
          ChecklistItem
          |> Ash.Query.filter(checklist_id == ^checklist.id)
          |> Ash.Query.sort(step_number: :asc)
          |> Ash.read!()

        done = Enum.count(items, & &1.completed)

        pct =
          if socket.assigns.total > 0,
            do: Float.round(done / socket.assigns.total * 100, 0),
            else: 0

        {:noreply, assign(socket, checklist: checklist, items: items, done: done, pct: pct)}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("start_step", %{"id" => item_id}, socket) do
    unless before_photos_complete?(socket.assigns.before_photos) do
      {:noreply, put_flash(socket, :error, "Upload all before photos first.")}
    else
      item = Enum.find(socket.assigns.items, &(&1.id == item_id))

      if item && WashStateMachine.can_start_step?(item, socket.assigns.items) do
        {:ok, updated} =
          item
          |> Ash.Changeset.for_update(:start_step, %{})
          |> Ash.update()

        items =
          Enum.map(socket.assigns.items, fn i -> if i.id == item_id, do: updated, else: i end)

        AppointmentTracker.broadcast_step_progress(socket.assigns.appointment.id, %{
          current_step: updated.title,
          current_step_number: updated.step_number,
          steps_done: Enum.count(items, & &1.completed),
          steps_total: socket.assigns.total,
          items: items
        })

        {:noreply, assign(socket, items: items, active_item_id: item_id)}
      else
        {:noreply,
         put_flash(
           socket,
           :error,
           "Cannot start this step yet — complete previous required steps first."
         )}
      end
    end
  end

  def handle_event("complete_step", %{"id" => item_id}, socket) do
    item = Enum.find(socket.assigns.items, &(&1.id == item_id))

    if item && WashStateMachine.can_complete_step?(item) do
      {:ok, updated} =
        item
        |> Ash.Changeset.for_update(:check, %{})
        |> Ash.update()

      items = Enum.map(socket.assigns.items, fn i -> if i.id == item_id, do: updated, else: i end)
      done = Enum.count(items, & &1.completed)

      pct =
        if socket.assigns.total > 0,
          do: Float.round(done / socket.assigns.total * 100, 0),
          else: 0

      current = current_progress_item(items)
      next = WashStateMachine.next_step(items)
      current_name = if current, do: current.title, else: "Finishing up"

      AppointmentTracker.broadcast_step_progress(socket.assigns.appointment.id, %{
        current_step: current_name,
        current_step_number: current && current.step_number,
        steps_done: done,
        steps_total: socket.assigns.total,
        items: items
      })

      socket =
        socket
        |> assign(items: items, done: done, pct: pct, active_item_id: next && next.id)
        |> maybe_complete_wash()

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_event("show_upload", %{"type" => type, "area" => area}, socket) do
    {:noreply,
     assign(socket, show_photo_upload: %{type: type, area: String.to_existing_atom(area)})}
  end

  def handle_event("cancel_upload", _params, socket) do
    {:noreply, assign(socket, show_photo_upload: nil)}
  end

  def handle_event("validate_upload", _params, socket), do: {:noreply, socket}

  def handle_event("save_photo", _params, socket) do
    %{type: type_str, area: area} = socket.assigns.show_photo_upload
    photo_type = String.to_existing_atom(type_str)
    appointment_id = socket.assigns.appointment.id

    consume_uploaded_entries(socket, :photo, fn %{path: path}, entry ->
      opts = [uploaded_by: :technician, car_part: area]

      case PhotoUpload.save_file(appointment_id, path, entry.client_name, photo_type, opts) do
        {:ok, photo} -> {:ok, photo}
        {:error, reason} -> {:postpone, reason}
      end
    end)

    AppointmentTracker.broadcast_photo(appointment_id, photo_type)

    socket =
      socket
      |> assign(show_photo_upload: nil)
      |> reload_photos()
      |> maybe_complete_wash()

    {:noreply, put_flash(socket, :info, "Photo saved.")}
  end

  def handle_event("edit_note", %{"id" => item_id}, socket) do
    {:noreply, assign(socket, editing_note_id: item_id)}
  end

  def handle_event("cancel_note", _params, socket) do
    {:noreply, assign(socket, editing_note_id: nil)}
  end

  def handle_event("save_note", %{"id" => item_id, "notes" => notes}, socket) do
    item = Enum.find(socket.assigns.items, &(&1.id == item_id))

    if item do
      {:ok, updated} =
        item
        |> Ash.Changeset.for_update(:add_note, %{notes: notes})
        |> Ash.update()

      items = Enum.map(socket.assigns.items, fn i -> if i.id == item_id, do: updated, else: i end)
      {:noreply, assign(socket, items: items, editing_note_id: nil)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("show_skip_reason", %{"id" => item_id}, socket) do
    {:noreply, assign(socket, skipping_item_id: item_id)}
  end

  def handle_event("cancel_skip", _params, socket) do
    {:noreply, assign(socket, skipping_item_id: nil)}
  end

  def handle_event("confirm_skip", %{"id" => item_id, "reason" => reason}, socket) do
    item = Enum.find(socket.assigns.items, &(&1.id == item_id))

    if item && !item.required do
      {:ok, updated} =
        item
        |> Ash.Changeset.for_update(:add_note, %{notes: "Skipped: #{reason}"})
        |> Ash.update()

      {:ok, completed} =
        updated
        |> Ash.Changeset.for_update(:check, %{})
        |> Ash.update()

      items =
        Enum.map(socket.assigns.items, fn i -> if i.id == item_id, do: completed, else: i end)

      done = Enum.count(items, & &1.completed)

      pct =
        if socket.assigns.total > 0,
          do: Float.round(done / socket.assigns.total * 100, 0),
          else: 0

      current = current_progress_item(items)
      current_name = if current, do: current.title, else: "Finishing up"

      AppointmentTracker.broadcast_step_progress(socket.assigns.appointment.id, %{
        current_step: current_name,
        current_step_number: current && current.step_number,
        steps_done: done,
        steps_total: socket.assigns.total,
        items: items
      })

      socket =
        socket
        |> assign(items: items, done: done, pct: pct, skipping_item_id: nil)
        |> maybe_complete_wash()

      {:noreply, socket}
    else
      {:noreply, put_flash(socket, :error, "Cannot skip required steps")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-lg px-4 py-4">
      <div :if={@checklist}>
        <div id="active-wash" class="space-y-6">
          <section id="wash-progress-header" class="space-y-4">
            <div class="rounded-[28px] border border-base-300/70 bg-base-100 px-4 py-4 shadow-sm">
              <div class="flex items-start justify-between gap-3">
                <div>
                  <p class="text-xs font-semibold uppercase tracking-[0.18em] text-base-content/50">
                    Active Wash
                  </p>
                  <h1 class="mt-1 text-xl font-bold">Wash Checklist</h1>
                </div>
                <span class={["badge badge-lg", checklist_badge(@checklist.status)]}>
                  {@done}/{@total}
                </span>
              </div>
              <progress class="progress progress-primary mt-4 w-full" value={@pct} max="100">
              </progress>
              <div class="mt-2 flex justify-between text-sm text-base-content/70">
                <span>{@pct}% complete</span>
                <span>ETA: ~{remaining_minutes(@items)} min</span>
              </div>
            </div>

            <div
              :if={@problem_photos != []}
              class="rounded-[24px] border border-warning/30 bg-warning/5 p-4"
            >
              <div class="mb-3 flex items-center justify-between gap-3">
                <div>
                  <h2 class="font-semibold text-warning">Customer Problem Areas</h2>
                  <p class="text-xs text-base-content/70">Reference these while you wash.</p>
                </div>
                <span class="badge badge-warning badge-outline">
                  {length(@problem_photos)} flagged
                </span>
              </div>
              <div class="flex gap-2 overflow-x-auto pb-1">
                <div :for={photo <- @problem_photos} class="flex-shrink-0">
                  <img
                    src={photo.file_path}
                    class="h-20 w-20 rounded-lg border-2 border-warning object-cover"
                  />
                  <p :if={photo.caption} class="mt-1 text-center text-xs">{photo.caption}</p>
                </div>
              </div>
            </div>
          </section>

          <section id="before-photo-progress" class="space-y-3">
            <div class="flex items-center justify-between gap-3">
              <div>
                <h2 class="font-bold">Before Photos</h2>
                <p class="text-xs text-base-content/70">Required before starting</p>
              </div>
              <span :if={before_photos_complete?(@before_photos)} class="badge badge-success">
                ✓ Complete
              </span>
              <span :if={!before_photos_complete?(@before_photos)} class="badge badge-warning">
                {Enum.count(@key_areas, &(area_photo(@before_photos, &1.id) != nil))}/{length(
                  @key_areas
                )}
              </span>
            </div>
            <div class="grid grid-cols-2 gap-3">
              <div :for={area <- @key_areas}>
                <% photo = area_photo(@before_photos, area.id) %>
                <div :if={photo} class="relative h-40 overflow-hidden rounded-2xl shadow">
                  <img src={photo.file_path} class="h-full w-full object-cover" />
                  <div class="absolute inset-0 flex flex-col justify-end bg-gradient-to-t from-black/60 to-transparent p-2">
                    <p class="text-xs font-bold leading-tight text-white">{area.label}</p>
                  </div>
                  <div class="absolute right-2 top-2 flex h-6 w-6 items-center justify-center rounded-full bg-success shadow">
                    <span class="text-xs font-bold text-white">✓</span>
                  </div>
                  <button
                    class="absolute left-2 top-2 rounded-full bg-black/40 px-2 py-0.5 text-xs text-white"
                    phx-click="show_upload"
                    phx-value-type="before"
                    phx-value-area={area.id}
                  >
                    Retake
                  </button>
                </div>
                <button
                  :if={!photo}
                  class="flex h-40 w-full flex-col items-center justify-center gap-1 rounded-2xl border-2 border-dashed border-warning bg-warning/5 transition-colors active:bg-warning/20"
                  phx-click="show_upload"
                  phx-value-type="before"
                  phx-value-area={area.id}
                >
                  <span class="text-5xl font-thin text-warning/70">+</span>
                  <span class="text-sm font-bold text-warning">{area.label}</span>
                  <span class="px-3 text-center text-xs leading-tight text-base-content/70">
                    {area.instruction}
                  </span>
                </button>
              </div>
            </div>
          </section>

          <section
            id="active-step-card"
            class="overflow-hidden rounded-[28px] border border-base-300/70 bg-base-100 shadow-sm"
          >
            <div class="border-b border-base-300/70 px-4 py-3">
              <p class="text-xs font-semibold uppercase tracking-[0.18em] text-base-content/50">
                Active Step
              </p>
              <div class="mt-2 flex items-center justify-between gap-3">
                <div>
                  <h2 class="text-lg font-bold">{active_step_title(@items)}</h2>
                  <p class="text-sm text-base-content/70">
                    {active_step_supporting_copy(@items, @checklist.status)}
                  </p>
                </div>
                <span class="badge badge-outline">{done_label(@done, @total)}</span>
              </div>
            </div>
            <div class="px-4 py-4">
              <%= case current_progress_item(@items) do %>
                <% nil -> %>
                  <div class="rounded-2xl border border-dashed border-base-300 px-4 py-6 text-sm text-base-content/70">
                    No steps are loaded for this checklist yet.
                  </div>
                <% item -> %>
                  <div class="space-y-3">
                    <div class="flex items-start justify-between gap-3">
                      <div>
                        <p class="text-xs font-semibold uppercase tracking-[0.16em] text-base-content/45">
                          Step {item.step_number}
                        </p>
                        <p :if={item.description} class="mt-1 text-sm text-base-content/70">
                          {item.description}
                        </p>
                      </div>
                      <span :if={item.required} class="badge badge-error badge-sm">Required</span>
                    </div>

                    <div
                      :if={item.started_at && !item.completed}
                      class="rounded-2xl bg-base-200/70 px-3 py-3"
                    >
                      <div class="flex items-center gap-2">
                        <span class={["font-mono text-lg font-bold", timer_text_color(item, @now)]}>
                          {format_elapsed(item.started_at, @now)}
                        </span>
                        <span class="text-xs text-base-content/70">
                          / {item.estimated_minutes || 5}:00 est
                        </span>
                      </div>
                      <progress
                        class={["progress mt-2 h-2 w-full", timer_progress_color(item, @now)]}
                        value={elapsed_seconds(item.started_at, @now)}
                        max={(item.estimated_minutes || 5) * 60}
                      >
                      </progress>
                    </div>

                    <div
                      :if={item.completed && item.actual_seconds}
                      class="rounded-2xl bg-success/10 px-3 py-3 text-sm"
                    >
                      <span class={
                        if item.actual_seconds <= (item.estimated_minutes || 5) * 60,
                          do: "text-success",
                          else: "text-error"
                      }>
                        Actual: {format_seconds(item.actual_seconds)}
                      </span>
                      <span class="text-base-content/70">
                        / Est: {item.estimated_minutes || 5} min
                      </span>
                    </div>
                  </div>
              <% end %>
            </div>
          </section>

          <section id="all-steps-list" class="space-y-2">
            <div class="flex items-center justify-between gap-3">
              <div>
                <h2 class="font-bold">All Steps</h2>
                <p class="text-xs text-base-content/70">
                  Use the focused card above, then work down the list.
                </p>
              </div>
              <span class="text-xs font-medium text-base-content/50">{@total} total</span>
            </div>

            <div class="space-y-2">
              <div
                :for={item <- @items}
                class={[
                  "card shadow-sm transition-all",
                  item.completed && "bg-base-100 opacity-60",
                  !item.completed && item.started_at && "border-l-4 bg-base-100",
                  !item.completed && item.started_at && timer_border_color(item, @now),
                  !item.completed && !item.started_at && "bg-base-100"
                ]}
              >
                <div class="card-body p-4">
                  <div class="flex items-start gap-3">
                    <div class="flex flex-col items-center">
                      <div :if={item.completed} class="text-xl text-success">✓</div>
                      <div :if={!item.completed} class="text-lg font-mono text-base-content/70">
                        {item.step_number}
                      </div>
                    </div>

                    <div class="flex-1">
                      <div class="flex items-start justify-between">
                        <span class={["font-semibold", item.completed && "line-through"]}>
                          {item.title}
                        </span>
                        <span :if={item.required} class="badge badge-error badge-xs">Req</span>
                      </div>
                      <p :if={item.description} class="mt-1 text-xs text-base-content/80">
                        {item.description}
                      </p>

                      <div :if={item.started_at && !item.completed} class="mt-2">
                        <div class="flex items-center gap-2">
                          <span class={["font-mono text-lg font-bold", timer_text_color(item, @now)]}>
                            {format_elapsed(item.started_at, @now)}
                          </span>
                          <span class="text-xs text-base-content/70">
                            / {item.estimated_minutes || 5}:00 est
                          </span>
                        </div>
                        <progress
                          class={["progress h-2 w-full", timer_progress_color(item, @now)]}
                          value={elapsed_seconds(item.started_at, @now)}
                          max={(item.estimated_minutes || 5) * 60}
                        >
                        </progress>
                      </div>

                      <div :if={item.completed && item.actual_seconds} class="mt-1 text-xs">
                        <span class={
                          if item.actual_seconds <= (item.estimated_minutes || 5) * 60,
                            do: "text-success",
                            else: "text-error"
                        }>
                          Actual: {format_seconds(item.actual_seconds)}
                        </span>
                        <span class="text-base-content/70">
                          / Est: {item.estimated_minutes || 5} min
                        </span>
                      </div>

                      <div :if={@editing_note_id == item.id} class="mt-2 space-y-2">
                        <form phx-submit="save_note" phx-value-id={item.id}>
                          <textarea
                            name="notes"
                            class="textarea textarea-bordered textarea-sm w-full"
                            placeholder="Add a note about this step..."
                          >{item.notes}</textarea>
                          <div class="mt-1 flex gap-1">
                            <button type="submit" class="btn btn-primary btn-xs flex-1">Save</button>
                            <button type="button" class="btn btn-ghost btn-xs" phx-click="cancel_note">
                              Cancel
                            </button>
                          </div>
                        </form>
                      </div>
                      <div :if={@editing_note_id != item.id} class="mt-2">
                        <p :if={item.notes} class="text-xs text-info">Note: {item.notes}</p>
                        <button
                          :if={item.notes || !item.completed}
                          class="mt-1 text-xs link link-primary"
                          phx-click="edit_note"
                          phx-value-id={item.id}
                        >
                          {if item.notes, do: "Edit note", else: "Add note"}
                        </button>
                      </div>
                    </div>
                  </div>

                  <div :if={!item.completed} class="mt-2 flex flex-wrap justify-end gap-2">
                    <button
                      :if={!item.started_at}
                      class="btn btn-primary btn-sm"
                      phx-click="start_step"
                      phx-value-id={item.id}
                    >
                      Start Step
                    </button>
                    <button
                      :if={item.started_at}
                      class="btn btn-success btn-sm"
                      phx-click="complete_step"
                      phx-value-id={item.id}
                    >
                      Done ✓
                    </button>
                    <button
                      :if={!item.required && @skipping_item_id != item.id}
                      class="btn btn-outline btn-sm"
                      phx-click="show_skip_reason"
                      phx-value-id={item.id}
                    >
                      Skip (Opt)
                    </button>
                    <div :if={@skipping_item_id == item.id} class="flex w-full gap-1">
                      <form phx-submit="confirm_skip" phx-value-id={item.id} class="flex flex-1 gap-1">
                        <input
                          type="text"
                          name="reason"
                          class="input input-bordered input-sm flex-1"
                          placeholder="Why skip?"
                          required
                        />
                        <button type="submit" class="btn btn-sm btn-outline">Skip</button>
                        <button type="button" class="btn btn-ghost btn-sm" phx-click="cancel_skip">
                          Cancel
                        </button>
                      </form>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </section>

          <section id="after-photo-progress" class="space-y-3">
            <div class="flex items-center justify-between gap-3">
              <div>
                <h2 class="font-bold">After Photos</h2>
                <p class="text-xs text-base-content/70">Match each before photo</p>
              </div>
              <span :if={after_photos_complete?(@after_photos)} class="badge badge-success">
                ✓ Complete
              </span>
              <span
                :if={!after_photos_complete?(@after_photos)}
                class="badge badge-success badge-outline"
              >
                {Enum.count(@key_areas, &(area_photo(@after_photos, &1.id) != nil))}/{length(
                  @key_areas
                )}
              </span>
            </div>

            <div
              :if={!all_required_complete?(@items) and @checklist.status != :completed}
              class="rounded-[24px] border border-dashed border-base-300 bg-base-200/40 px-4 py-5 text-sm text-base-content/70"
            >
              Finish all required wash steps to unlock after-photo capture.
            </div>

            <div
              :if={all_required_complete?(@items) or @checklist.status == :completed}
              class="grid grid-cols-2 gap-3"
            >
              <div :for={area <- @key_areas}>
                <% before_photo = area_photo(@before_photos, area.id) %>
                <% after_photo = area_photo(@after_photos, area.id) %>
                <div :if={after_photo} class="relative h-40 overflow-hidden rounded-2xl shadow">
                  <img src={after_photo.file_path} class="h-full w-full object-cover" />
                  <div
                    :if={before_photo}
                    class="absolute bottom-2 left-2 h-12 w-12 overflow-hidden rounded-lg border-2 border-white shadow"
                  >
                    <img src={before_photo.file_path} class="h-full w-full object-cover" />
                  </div>
                  <div class="absolute inset-0 flex flex-col justify-end bg-gradient-to-t from-black/60 to-transparent p-2 pl-16">
                    <p class="text-xs font-bold leading-tight text-white">{area.label}</p>
                  </div>
                  <div class="absolute right-2 top-2 flex h-6 w-6 items-center justify-center rounded-full bg-success shadow">
                    <span class="text-xs font-bold text-white">✓</span>
                  </div>
                  <button
                    :if={@checklist.status != :completed}
                    class="absolute left-2 top-2 rounded-full bg-black/40 px-2 py-0.5 text-xs text-white"
                    phx-click="show_upload"
                    phx-value-type="after"
                    phx-value-area={area.id}
                  >
                    Retake
                  </button>
                </div>
                <button
                  :if={!after_photo and @checklist.status != :completed}
                  class="relative flex h-40 w-full flex-col items-center justify-center gap-1 overflow-hidden rounded-2xl border-2 border-dashed border-success bg-success/5 transition-colors active:bg-success/20"
                  phx-click="show_upload"
                  phx-value-type="after"
                  phx-value-area={area.id}
                >
                  <img
                    :if={before_photo}
                    src={before_photo.file_path}
                    class="absolute inset-0 h-full w-full object-cover opacity-20"
                  />
                  <span class="relative text-5xl font-thin text-success/70">+</span>
                  <span class="relative text-sm font-bold text-success">{area.label}</span>
                  <span class="relative px-3 text-center text-xs leading-tight text-base-content/70">
                    {area.instruction}
                  </span>
                </button>
                <div
                  :if={!after_photo and @checklist.status == :completed}
                  class="flex h-40 items-center justify-center rounded-2xl border border-base-300 bg-base-200/40 px-3 text-center text-xs text-base-content/60"
                >
                  No after photo captured for {area.label}.
                </div>
              </div>
            </div>

            <div
              :if={after_photos_complete?(@after_photos) and @checklist.status != :completed}
              class="alert alert-success mt-4 rounded-2xl"
            >
              <span class="font-semibold">All photos complete — finishing wash...</span>
            </div>
          </section>

          <section
            :if={@checklist.status == :completed}
            id="wrap-up-panel"
            class="rounded-[28px] border border-success/30 bg-success/10 px-4 py-5 text-center"
          >
            <div class="text-4xl text-success">✓</div>
            <h2 class="mt-2 text-xl font-bold text-success">Checklist Complete!</h2>
            <p class="mt-1 text-sm text-base-content/80">All steps verified</p>

            <div class="mx-auto mt-4 max-w-sm rounded-[24px] bg-base-100 shadow">
              <div class="p-4">
                <h3 class="mb-2 text-sm font-semibold">Time Analysis</h3>
                <div
                  :for={item <- @items}
                  :if={item.actual_seconds}
                  class="flex justify-between border-b border-base-200 py-1 text-xs"
                >
                  <span>{item.title}</span>
                  <span class={
                    if item.actual_seconds <= (item.estimated_minutes || 5) * 60,
                      do: "text-success",
                      else: "text-error"
                  }>
                    {format_seconds(item.actual_seconds)} / {item.estimated_minutes}m est
                  </span>
                </div>
                <div class="mt-2 flex justify-between text-sm font-bold">
                  <span>Total</span>
                  <span>{format_seconds(total_actual_seconds(@items))}</span>
                </div>
              </div>
            </div>
          </section>
        </div>
        
    <!-- Photo Upload Overlay (full-screen on mobile) -->
        <div :if={@show_photo_upload} class="fixed inset-0 z-50 bg-base-100 flex flex-col">
          <div class="flex items-center justify-between p-4 border-b border-base-300">
            <div>
              <p class="text-xs font-semibold uppercase tracking-wide text-base-content/70">
                {String.capitalize(@show_photo_upload.type)} Photo
              </p>
              <h3 class="text-lg font-bold leading-tight">{area_label(@show_photo_upload.area)}</h3>
              <p class="text-sm text-base-content/70">{area_instruction(@show_photo_upload.area)}</p>
            </div>
            <button phx-click="cancel_upload" class="btn btn-ghost btn-sm btn-circle text-lg">
              ✕
            </button>
          </div>
          <div class="flex-1 overflow-y-auto p-4">
            <form phx-submit="save_photo" phx-change="validate_upload" class="flex flex-col gap-4">
              <!-- Preview (shown once a file is selected) -->
              <div :if={@uploads.photo.entries != []}>
                <div :for={entry <- @uploads.photo.entries}>
                  <.live_img_preview entry={entry} class="w-full rounded-2xl object-cover max-h-72" />
                </div>
              </div>
              
    <!-- Placeholder (shown when no file yet) — non-interactive, file input below handles taps -->
              <div
                :if={@uploads.photo.entries == []}
                class="rounded-2xl border-2 border-dashed border-base-300 flex flex-col items-center justify-center gap-2 py-16 pointer-events-none"
              >
                <span class="text-6xl font-thin text-base-content/20">+</span>
                <p class="text-sm text-base-content/70">Select photo below</p>
              </div>
              
    <!-- Single file input — always mounted so LiveView's upload hook stays attached -->
              <.live_file_input upload={@uploads.photo} class="file-input file-input-bordered w-full" />

              <button
                type="submit"
                class="btn btn-primary btn-lg w-full rounded-2xl"
                disabled={@uploads.photo.entries == []}
              >
                Save Photo
              </button>
            </form>
          </div>
        </div>
      </div>

      <div :if={!@checklist} class="text-center py-12">
        <p class="text-base-content/70">No active checklist</p>
      </div>
    </div>
    """
  end

  # --- Photo Helpers ---

  defp reload_photos(socket) do
    appointment_id = socket.assigns.appointment.id

    before_photos =
      Photo
      |> Ash.Query.filter(appointment_id == ^appointment_id and photo_type == :before)
      |> Ash.read!()
      |> Enum.map(&PhotoUpload.apply_url/1)

    after_photos =
      Photo
      |> Ash.Query.filter(appointment_id == ^appointment_id and photo_type == :after)
      |> Ash.read!()
      |> Enum.map(&PhotoUpload.apply_url/1)

    assign(socket, before_photos: before_photos, after_photos: after_photos)
  end

  defp maybe_complete_wash(socket) do
    if WashStateMachine.all_required_complete?(socket.assigns.items) and
         after_photos_complete?(socket.assigns.after_photos) and
         socket.assigns.checklist.status != :completed do
      {:ok, checklist} =
        socket.assigns.checklist
        |> Ash.Changeset.for_update(:complete_checklist, %{})
        |> Ash.update()

      WashOrchestrator.complete_wash(socket.assigns.appointment.id)

      assign(socket, checklist: checklist)
    else
      socket
    end
  end

  defp before_photos_complete?(before_photos) do
    taken = MapSet.new(before_photos, & &1.car_part)
    Enum.all?(@key_area_ids, &MapSet.member?(taken, &1))
  end

  defp after_photos_complete?(after_photos) do
    taken = MapSet.new(after_photos, & &1.car_part)
    Enum.all?(@key_area_ids, &MapSet.member?(taken, &1))
  end

  defp area_photo(photos, area_id) do
    Enum.find(photos, &(&1.car_part == area_id))
  end

  defp area_label(area_id) do
    case Enum.find(@key_areas, &(&1.id == area_id)) do
      %{label: label} -> label
      nil -> to_string(area_id)
    end
  end

  defp area_instruction(area_id) do
    case Enum.find(@key_areas, &(&1.id == area_id)) do
      %{instruction: instruction} -> instruction
      nil -> ""
    end
  end

  # --- Timer Helpers ---

  defp elapsed_seconds(started_at, now) do
    DateTime.diff(now, started_at)
  end

  defp format_elapsed(started_at, now) do
    seconds = DateTime.diff(now, started_at) |> max(0)
    format_seconds(seconds)
  end

  defp format_seconds(seconds) when is_integer(seconds) do
    mins = div(seconds, 60)
    secs = rem(seconds, 60)
    "#{String.pad_leading("#{mins}", 2, "0")}:#{String.pad_leading("#{secs}", 2, "0")}"
  end

  defp format_seconds(_), do: "--:--"

  defp timer_border_color(item, now) do
    case timer_zone(item, now) do
      :green -> "border-success"
      :yellow -> "border-warning"
      :red -> "border-error"
    end
  end

  defp timer_text_color(item, now) do
    case timer_zone(item, now) do
      :green -> "text-success"
      :yellow -> "text-warning"
      :red -> "text-error"
    end
  end

  defp current_progress_item(items) do
    active = Enum.find(items, &(&1.started_at && !&1.completed))
    last_completed = items |> Enum.filter(& &1.completed) |> List.last()
    next_pending = Enum.find(items, &(not &1.completed))

    active || last_completed || next_pending
  end

  defp active_step_title(items) do
    case current_progress_item(items) do
      nil -> "No active step"
      item -> item.title
    end
  end

  defp active_step_supporting_copy(_items, :completed) do
    "Everything is wrapped. Review the completed wash details below."
  end

  defp active_step_supporting_copy(items, _status) do
    case current_progress_item(items) do
      %{completed: true} -> "Nice. This was the last finished step."
      %{started_at: %DateTime{}} -> "Timer is live for the step currently in motion."
      %{required: true} -> "This is the next required step to keep the wash moving."
      %{required: false} -> "This optional step is next up if you want to complete it."
      nil -> "Steps will appear here once the checklist has been created."
    end
  end

  defp done_label(done, total), do: "#{done}/#{total} done"

  defp timer_progress_color(item, now) do
    case timer_zone(item, now) do
      :green -> "progress-success"
      :yellow -> "progress-warning"
      :red -> "progress-error"
    end
  end

  defp timer_zone(item, now) do
    elapsed = DateTime.diff(now, item.started_at) |> max(0)
    estimated_secs = (item.estimated_minutes || 5) * 60
    remaining = estimated_secs - elapsed

    cond do
      remaining < 0 -> :red
      remaining <= 45 -> :yellow
      true -> :green
    end
  end

  defp remaining_minutes(items) do
    items
    |> Enum.reject(& &1.completed)
    |> Enum.reduce(0, fn item, acc -> acc + (item.estimated_minutes || 5) end)
  end

  defp total_actual_seconds(items) do
    items
    |> Enum.map(& &1.actual_seconds)
    |> Enum.reject(&is_nil/1)
    |> Enum.sum()
  end

  defp all_required_complete?(items) do
    items |> Enum.filter(& &1.required) |> Enum.all?(& &1.completed)
  end

  defp checklist_badge(:completed), do: "badge-success"
  defp checklist_badge(:in_progress), do: "badge-info"
  defp checklist_badge(_), do: "badge-ghost"
end
