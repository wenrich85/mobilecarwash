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
    %{id: :front,          label: "Front",           instruction: "Full front bumper & headlights"},
    %{id: :rear,           label: "Rear",            instruction: "Full rear bumper & taillights"},
    %{id: :driver_side,    label: "Driver Side",     instruction: "Full side panel, front to back"},
    %{id: :passenger_side, label: "Passenger Side",  instruction: "Full side panel, front to back"},
    %{id: :interior,       label: "Interior",        instruction: "Dashboard, steering wheel & seats"},
    %{id: :wheels,         label: "Wheels",          instruction: "One wheel — representative of all"}
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
          |> allow_upload(:photo, accept: ~w(.jpg .jpeg .png .webp), max_entries: 1, max_file_size: 10_000_000)

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
        pct = if socket.assigns.total > 0, do: Float.round(done / socket.assigns.total * 100, 0), else: 0

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

        items = Enum.map(socket.assigns.items, fn i -> if i.id == item_id, do: updated, else: i end)

        {:noreply, assign(socket, items: items, active_item_id: item_id)}
      else
        {:noreply, put_flash(socket, :error, "Cannot start this step yet — complete previous required steps first.")}
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
      pct = if socket.assigns.total > 0, do: Float.round(done / socket.assigns.total * 100, 0), else: 0

      next = WashStateMachine.next_step(items)
      next_name = if next, do: next.title, else: "Finishing up"

      AppointmentTracker.broadcast_step_progress(socket.assigns.appointment.id, %{
        current_step: next_name,
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
    {:noreply, assign(socket, show_photo_upload: %{type: type, area: String.to_existing_atom(area)})}
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

      items = Enum.map(socket.assigns.items, fn i -> if i.id == item_id, do: completed, else: i end)
      done = Enum.count(items, & &1.completed)
      pct = if socket.assigns.total > 0, do: Float.round(done / socket.assigns.total * 100, 0), else: 0

      next = WashStateMachine.next_step(items)
      next_name = if next, do: next.title, else: "Finishing up"

      AppointmentTracker.broadcast_step_progress(socket.assigns.appointment.id, %{
        current_step: next_name,
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
    <div class="max-w-lg mx-auto py-4 px-4">
      <div :if={@checklist}>
        <!-- Progress Header -->
        <div class="mb-6">
          <div class="flex justify-between items-center mb-2">
            <h1 class="text-xl font-bold">Wash Checklist</h1>
            <span class={["badge badge-lg", checklist_badge(@checklist.status)]}>
              {@done}/{@total}
            </span>
          </div>
          <progress class="progress progress-primary w-full" value={@pct} max="100"></progress>
          <div class="flex justify-between text-sm text-base-content/50 mt-1">
            <span>{@pct}% complete</span>
            <span>ETA: ~{remaining_minutes(@items)} min</span>
          </div>
        </div>

        <!-- Customer Problem Area Photos -->
        <div :if={@problem_photos != []} class="mb-6">
          <h3 class="font-semibold text-sm mb-2 text-warning">Customer Problem Areas</h3>
          <div class="flex gap-2 overflow-x-auto">
            <div :for={photo <- @problem_photos} class="flex-shrink-0">
              <img src={photo.file_path} class="w-20 h-20 object-cover rounded-lg border-2 border-warning" />
              <p :if={photo.caption} class="text-xs text-center mt-1">{photo.caption}</p>
            </div>
          </div>
        </div>

        <!-- Before Photos Grid (required before steps can start) -->
        <div :if={@checklist.status != :completed} class="mb-6">
          <div class="flex justify-between items-center mb-3">
            <div>
              <h3 class="font-bold">Before Photos</h3>
              <p class="text-xs text-base-content/50">Required before starting</p>
            </div>
            <span :if={before_photos_complete?(@before_photos)} class="badge badge-success">
              ✓ Complete
            </span>
            <span :if={!before_photos_complete?(@before_photos)} class="badge badge-warning">
              {Enum.count(@key_areas, &area_photo(@before_photos, &1.id) != nil)}/{length(@key_areas)}
            </span>
          </div>
          <div class="grid grid-cols-2 gap-3">
            <div :for={area <- @key_areas}>
              <% photo = area_photo(@before_photos, area.id) %>
              <!-- Filled -->
              <div :if={photo} class="relative h-40 rounded-2xl overflow-hidden shadow">
                <img src={photo.file_path} class="w-full h-full object-cover" />
                <div class="absolute inset-0 bg-gradient-to-t from-black/60 to-transparent flex flex-col justify-end p-2">
                  <p class="text-white text-xs font-bold leading-tight">{area.label}</p>
                </div>
                <div class="absolute top-2 right-2 bg-success rounded-full w-6 h-6 flex items-center justify-center shadow">
                  <span class="text-white text-xs font-bold">✓</span>
                </div>
                <button
                  class="absolute top-2 left-2 bg-black/40 rounded-full px-2 py-0.5 text-white text-xs"
                  phx-click="show_upload"
                  phx-value-type="before"
                  phx-value-area={area.id}
                >
                  Retake
                </button>
              </div>
              <!-- Empty -->
              <button
                :if={!photo}
                class="w-full h-40 rounded-2xl border-2 border-dashed border-warning bg-warning/5 flex flex-col items-center justify-center gap-1 active:bg-warning/20 transition-colors"
                phx-click="show_upload"
                phx-value-type="before"
                phx-value-area={area.id}
              >
                <span class="text-5xl font-thin text-warning/70">+</span>
                <span class="text-sm font-bold text-warning">{area.label}</span>
                <span class="text-xs text-base-content/40 text-center px-3 leading-tight">{area.instruction}</span>
              </button>
            </div>
          </div>
        </div>

        <!-- Photo Upload Overlay (full-screen on mobile) -->
        <div :if={@show_photo_upload} class="fixed inset-0 z-50 bg-base-100 flex flex-col">
          <div class="flex items-center justify-between p-4 border-b border-base-300">
            <div>
              <p class="text-xs font-semibold uppercase tracking-wide text-base-content/50">
                {String.capitalize(@show_photo_upload.type)} Photo
              </p>
              <h3 class="text-lg font-bold leading-tight">{area_label(@show_photo_upload.area)}</h3>
              <p class="text-sm text-base-content/50">{area_instruction(@show_photo_upload.area)}</p>
            </div>
            <button phx-click="cancel_upload" class="btn btn-ghost btn-sm btn-circle text-lg">✕</button>
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
              <div :if={@uploads.photo.entries == []} class="rounded-2xl border-2 border-dashed border-base-300 flex flex-col items-center justify-center gap-2 py-16 pointer-events-none">
                <span class="text-6xl font-thin text-base-content/20">+</span>
                <p class="text-sm text-base-content/40">Select photo below</p>
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

        <!-- Checklist Items with Timers -->
        <div class="space-y-2">
          <div :for={item <- @items} class={[
            "card shadow-sm transition-all",
            item.completed && "bg-base-100 opacity-60",
            !item.completed && item.started_at && "bg-base-100 border-l-4",
            !item.completed && item.started_at && timer_border_color(item, @now),
            !item.completed && !item.started_at && "bg-base-100"
          ]}>
            <div class="card-body p-4">
              <div class="flex items-start gap-3">
                <!-- Step number / check -->
                <div class="flex flex-col items-center">
                  <div :if={item.completed} class="text-success text-xl">✓</div>
                  <div :if={!item.completed} class="text-lg font-mono text-base-content/40">{item.step_number}</div>
                </div>

                <div class="flex-1">
                  <div class="flex justify-between items-start">
                    <span class={["font-semibold", item.completed && "line-through"]}>
                      {item.title}
                    </span>
                    <span :if={item.required} class="badge badge-error badge-xs">Req</span>
                  </div>
                  <p :if={item.description} class="text-xs text-base-content/60 mt-1">{item.description}</p>

                  <!-- Timer Display -->
                  <div :if={item.started_at && !item.completed} class="mt-2">
                    <div class="flex items-center gap-2">
                      <span class={["font-mono text-lg font-bold", timer_text_color(item, @now)]}>
                        {format_elapsed(item.started_at, @now)}
                      </span>
                      <span class="text-xs text-base-content/50">
                        / {item.estimated_minutes || 5}:00 est
                      </span>
                    </div>
                    <progress
                      class={["progress w-full h-2", timer_progress_color(item, @now)]}
                      value={elapsed_seconds(item.started_at, @now)}
                      max={(item.estimated_minutes || 5) * 60}
                    />
                  </div>

                  <!-- Completed time stats -->
                  <div :if={item.completed && item.actual_seconds} class="mt-1 text-xs">
                    <span class={if item.actual_seconds <= (item.estimated_minutes || 5) * 60, do: "text-success", else: "text-error"}>
                      Actual: {format_seconds(item.actual_seconds)}
                    </span>
                    <span class="text-base-content/40"> / Est: {item.estimated_minutes || 5} min</span>
                  </div>

                  <!-- Notes Section -->
                  <div :if={@editing_note_id == item.id} class="mt-2 space-y-2">
                    <form phx-submit="save_note" phx-value-id={item.id}>
                      <textarea
                        name="notes"
                        class="textarea textarea-bordered textarea-sm w-full"
                        placeholder="Add a note about this step..."
                      >{item.notes}</textarea>
                      <div class="flex gap-1 mt-1">
                        <button type="submit" class="btn btn-primary btn-xs flex-1">Save</button>
                        <button type="button" class="btn btn-ghost btn-xs" phx-click="cancel_note">Cancel</button>
                      </div>
                    </form>
                  </div>
                  <div :if={@editing_note_id != item.id} class="mt-2">
                    <p :if={item.notes} class="text-xs text-info">Note: {item.notes}</p>
                    <button
                      :if={item.notes || !item.completed}
                      class="text-xs link link-primary mt-1"
                      phx-click="edit_note"
                      phx-value-id={item.id}
                    >
                      {if item.notes, do: "Edit note", else: "Add note"}
                    </button>
                  </div>
                </div>
              </div>

              <!-- Action Buttons -->
              <div :if={!item.completed} class="mt-2 flex gap-2 justify-end flex-wrap">
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
                <div :if={@skipping_item_id == item.id} class="flex gap-1 w-full">
                  <form phx-submit="confirm_skip" phx-value-id={item.id} class="flex gap-1 flex-1">
                    <input
                      type="text"
                      name="reason"
                      class="input input-bordered input-sm flex-1"
                      placeholder="Why skip?"
                      required
                    />
                    <button type="submit" class="btn btn-sm btn-outline">Skip</button>
                    <button type="button" class="btn btn-ghost btn-sm" phx-click="cancel_skip">Cancel</button>
                  </form>
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- After Photos Grid (shown when all required steps done) -->
        <div :if={all_required_complete?(@items) and @checklist.status != :completed} class="mt-6">
          <div class="flex justify-between items-center mb-3">
            <div>
              <h3 class="font-bold">After Photos</h3>
              <p class="text-xs text-base-content/50">Match each before photo</p>
            </div>
            <span :if={after_photos_complete?(@after_photos)} class="badge badge-success">
              ✓ Complete
            </span>
            <span :if={!after_photos_complete?(@after_photos)} class="badge badge-success animate-pulse">
              {Enum.count(@key_areas, &area_photo(@after_photos, &1.id) != nil)}/{length(@key_areas)}
            </span>
          </div>
          <div class="grid grid-cols-2 gap-3">
            <div :for={area <- @key_areas}>
              <% before_photo = area_photo(@before_photos, area.id) %>
              <% after_photo = area_photo(@after_photos, area.id) %>
              <!-- Filled -->
              <div :if={after_photo} class="relative h-40 rounded-2xl overflow-hidden shadow">
                <img src={after_photo.file_path} class="w-full h-full object-cover" />
                <!-- Before thumbnail inset -->
                <div :if={before_photo} class="absolute bottom-2 left-2 w-12 h-12 rounded-lg overflow-hidden border-2 border-white shadow">
                  <img src={before_photo.file_path} class="w-full h-full object-cover" />
                </div>
                <div class="absolute inset-0 bg-gradient-to-t from-black/60 to-transparent flex flex-col justify-end p-2 pl-16">
                  <p class="text-white text-xs font-bold leading-tight">{area.label}</p>
                </div>
                <div class="absolute top-2 right-2 bg-success rounded-full w-6 h-6 flex items-center justify-center shadow">
                  <span class="text-white text-xs font-bold">✓</span>
                </div>
                <button
                  class="absolute top-2 left-2 bg-black/40 rounded-full px-2 py-0.5 text-white text-xs"
                  phx-click="show_upload"
                  phx-value-type="after"
                  phx-value-area={area.id}
                >
                  Retake
                </button>
              </div>
              <!-- Empty -->
              <button
                :if={!after_photo}
                class="relative w-full h-40 rounded-2xl border-2 border-dashed border-success bg-success/5 flex flex-col items-center justify-center gap-1 active:bg-success/20 transition-colors overflow-hidden"
                phx-click="show_upload"
                phx-value-type="after"
                phx-value-area={area.id}
              >
                <!-- Faded before photo as background guide -->
                <img :if={before_photo} src={before_photo.file_path} class="absolute inset-0 w-full h-full object-cover opacity-20" />
                <span class="relative text-5xl font-thin text-success/70">+</span>
                <span class="relative text-sm font-bold text-success">{area.label}</span>
                <span class="relative text-xs text-base-content/40 text-center px-3 leading-tight">{area.instruction}</span>
              </button>
            </div>
          </div>
          <div :if={after_photos_complete?(@after_photos)} class="mt-4 alert alert-success rounded-2xl">
            <span class="font-semibold">All photos complete — finishing wash...</span>
          </div>
        </div>

        <!-- Complete Banner -->
        <div :if={@checklist.status == :completed} class="mt-6 text-center">
          <div class="text-4xl mb-2">✓</div>
          <h2 class="text-xl font-bold text-success">Checklist Complete!</h2>
          <p class="text-sm text-base-content/60 mb-4">All steps verified</p>

          <!-- Time Summary -->
          <div class="card bg-base-100 shadow mx-auto max-w-sm">
            <div class="card-body p-4">
              <h3 class="font-semibold text-sm mb-2">Time Analysis</h3>
              <div :for={item <- @items} :if={item.actual_seconds} class="flex justify-between text-xs py-1 border-b border-base-200">
                <span>{item.title}</span>
                <span class={if item.actual_seconds <= (item.estimated_minutes || 5) * 60, do: "text-success", else: "text-error"}>
                  {format_seconds(item.actual_seconds)} / {item.estimated_minutes}m est
                </span>
              </div>
              <div class="flex justify-between font-bold text-sm mt-2">
                <span>Total</span>
                <span>{format_seconds(total_actual_seconds(@items))}</span>
              </div>
            </div>
          </div>
        </div>
      </div>

      <div :if={!@checklist} class="text-center py-12">
        <p class="text-base-content/50">No active checklist</p>
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
