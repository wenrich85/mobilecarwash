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

  import MobileCarWashWeb.Lightbox, only: [lightbox_root: 1]

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

  # One upload config per tile. The config NAME encodes photo_type and
  # car_part (e.g. :before_front), so concurrent uploads need no
  # entry-to-area bookkeeping.
  @tile_uploads for type <- [:before, :after], area <- @key_area_ids, do: :"#{type}_#{area}"

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
            supplies: MobileCarWash.Inventory.list_supplies(),
            supply_usages: MobileCarWash.Inventory.usage_for_appointment(appointment.id),
            wrap_up_error: nil,
            wrap_up_saved?: not is_nil(checklist.final_notes),
            key_areas: @key_areas,
            total: total,
            done: done,
            pct: pct,
            active_item_id: nil,
            elapsed_seconds: 0,
            editing_note_id: nil,
            skipping_item_id: nil,
            now: DateTime.utc_now()
          )
          |> assign(tile_errors: %{})
          |> then(fn sock ->
            Enum.reduce(@tile_uploads, sock, fn name, s ->
              allow_upload(s, name, tile_upload_opts())
            end)
          end)

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
           supplies: [],
           supply_usages: [],
           wrap_up_error: nil,
           wrap_up_saved?: false,
           key_areas: @key_areas,
           total: 0,
           done: 0,
           pct: 0,
           active_item_id: nil,
           elapsed_seconds: 0,
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
       supplies: [],
       supply_usages: [],
       wrap_up_error: nil,
       wrap_up_saved?: false,
       key_areas: @key_areas,
       total: 0,
       done: 0,
       pct: 0,
       active_item_id: nil,
       elapsed_seconds: 0,
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

  def handle_event("validate_upload", _params, socket), do: {:noreply, socket}

  def handle_event("retry_tile_upload", %{"name" => name, "ref" => ref}, socket) do
    name = String.to_existing_atom(name)

    if name in @tile_uploads do
      {:noreply,
       socket
       |> cancel_upload(name, ref)
       |> update(:tile_errors, &Map.delete(&1, name))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("edit_note", %{"id" => item_id}, socket) do
    {:noreply, assign(socket, editing_note_id: item_id)}
  end

  def handle_event("cancel_note", _params, socket) do
    {:noreply, assign(socket, editing_note_id: nil)}
  end

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
       |> assign(
         supply_usages:
           MobileCarWash.Inventory.usage_for_appointment(socket.assigns.appointment.id)
       )}
    else
      {:error, message} when is_binary(message) ->
        {:noreply, assign(socket, wrap_up_error: message, wrap_up_saved?: false)}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(
           wrap_up_error: "Could not save wrap-up: #{inspect(reason)}",
           wrap_up_saved?: false
         )
         |> assign(
           supply_usages:
             MobileCarWash.Inventory.usage_for_appointment(socket.assigns.appointment.id)
         )}
    end
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
          <.wash_command_card command={wash_command(assigns)} />

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
                    alt={photo.caption || "Customer problem photo"}
                    data-lightbox="problem-photos"
                    data-lightbox-caption={photo.caption}
                    class="h-20 w-20 rounded-lg border-2 border-warning object-cover cursor-zoom-in"
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
            <form
              id="before-photo-form"
              phx-change="validate_upload"
              phx-hook="ImageDownscale"
              class="grid grid-cols-2 gap-3"
            >
              <.photo_tile
                :for={area <- @key_areas}
                area={area}
                type={:before}
                photo={area_photo(@before_photos, area.id)}
                ghost={nil}
                upload={@uploads[tile_upload_name(:before, area.id)]}
                tile_error={@tile_errors[tile_upload_name(:before, area.id)]}
                completed={@checklist.status == :completed}
              />
            </form>
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

            <form
              :if={all_required_complete?(@items) or @checklist.status == :completed}
              id="after-photo-form"
              phx-change="validate_upload"
              phx-hook="ImageDownscale"
              class="grid grid-cols-2 gap-3"
            >
              <.photo_tile
                :for={area <- @key_areas}
                area={area}
                type={:after}
                photo={area_photo(@after_photos, area.id)}
                ghost={area_photo(@before_photos, area.id)}
                upload={@uploads[tile_upload_name(:after, area.id)]}
                tile_error={@tile_errors[tile_upload_name(:after, area.id)]}
                completed={@checklist.status == :completed}
              />
            </form>

            <div
              :if={after_photos_complete?(@after_photos) and @checklist.status != :completed}
              class="alert alert-success mt-4 rounded-2xl"
            >
              <span class="font-semibold">All photos complete — finishing wash...</span>
            </div>
          </section>

          <section
            :if={wrap_up_ready?(@items, @after_photos, @checklist)}
            id="wrap-up-panel"
            class="rounded-[28px] border border-success/30 bg-success/10 px-4 py-5 text-center"
          >
            <div class="text-4xl text-success">✓</div>
            <h2 class="mt-2 text-xl font-bold text-success">Checklist Complete!</h2>
            <p class="mt-1 text-sm text-base-content/80">All steps verified</p>

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
                  <select
                    name={"wrap_up[supplies][#{index}][supply_id]"}
                    class="select select-bordered select-sm w-full"
                  >
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
                {if @checklist.final_notes in [nil, ""],
                  do: "No final notes entered.",
                  else: @checklist.final_notes}
              </p>
            </div>

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
              <p class="mt-1 text-2xl font-bold text-success">
                {format_cents(wrap_up_earnings(@appointment))}
              </p>
            </div>

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
      </div>

      <div :if={!@checklist} class="text-center py-12">
        <p class="text-base-content/70">No active checklist</p>
      </div>

      <.lightbox_root />
    </div>
    """
  end

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

  # One grid tile. States, in precedence order: uploading (entry, no
  # errors) → upload failed (entry with errors) → saved (persisted photo)
  # → capture label (empty) → completed-and-missing placeholder.
  defp photo_tile(assigns) do
    entry = List.first(assigns.upload.entries)

    errors =
      if entry,
        do: upload_errors(assigns.upload, entry) ++ upload_errors(assigns.upload),
        else: upload_errors(assigns.upload)

    assigns = assign(assigns, entry: entry, upload_errs: errors)

    ~H"""
    <div id={"tile-#{@type}-#{@area.id}"}>
      <div
        :if={@entry && @upload_errs == []}
        class="relative h-40 overflow-hidden rounded-2xl shadow"
      >
        <.live_img_preview entry={@entry} class="h-full w-full object-cover" />
        <div class="absolute inset-x-2 bottom-2">
          <progress
            class="progress progress-primary h-1.5 w-full"
            value={@entry.progress}
            max="100"
          >
          </progress>
        </div>
        <p class="absolute left-2 top-2 rounded-full bg-black/40 px-2 py-0.5 text-xs text-white">
          {@area.label}
        </p>
      </div>

      <div
        :if={@entry && @upload_errs != []}
        class="flex h-40 w-full flex-col items-center justify-center gap-2 rounded-2xl border-2 border-dashed border-error bg-error/5 px-3 text-center"
      >
        <p class="text-sm font-bold text-error">{@area.label}</p>
        <p class="text-xs text-error">
          {MobileCarWashWeb.PhotoUploader.error_message(hd(@upload_errs))}
        </p>
        <button
          type="button"
          class="btn btn-outline btn-error btn-xs"
          phx-click="retry_tile_upload"
          phx-value-name={@upload.name}
          phx-value-ref={@entry.ref}
        >
          Try again
        </button>
      </div>

      <div :if={!@entry && @photo} class="relative h-40 overflow-hidden rounded-2xl shadow">
        <img
          src={@photo.file_path}
          alt={"#{if @type == :before, do: "Before", else: "After"} — #{@area.label}"}
          data-lightbox="checklist-photos"
          class="h-full w-full object-cover cursor-zoom-in"
        />
        <div
          :if={@ghost}
          class="absolute bottom-2 left-2 h-12 w-12 overflow-hidden rounded-lg border-2 border-white shadow"
        >
          <img src={@ghost.file_path} alt="" class="h-full w-full object-cover" />
        </div>
        <div class={[
          "absolute inset-0 flex flex-col justify-end bg-gradient-to-t from-black/60 to-transparent p-2",
          @ghost && "pl-16"
        ]}>
          <p class="text-xs font-bold leading-tight text-white">{@area.label}</p>
        </div>
        <div class="absolute right-2 top-2 flex h-6 w-6 items-center justify-center rounded-full bg-success shadow">
          <span class="text-xs font-bold text-white">✓</span>
        </div>
        <label
          :if={!@completed}
          for={@upload.ref}
          class="absolute left-2 top-2 cursor-pointer rounded-full bg-black/40 px-2 py-0.5 text-xs text-white"
        >
          Retake
        </label>
      </div>

      <label
        :if={!@entry && !@photo && !@completed}
        for={@upload.ref}
        class={[
          "relative flex h-40 w-full cursor-pointer flex-col items-center justify-center gap-1",
          "overflow-hidden rounded-2xl border-2 border-dashed transition-colors",
          tile_accent(@type)
        ]}
      >
        <img
          :if={@ghost}
          src={@ghost.file_path}
          alt=""
          class="absolute inset-0 h-full w-full object-cover opacity-20"
        />
        <span class="relative text-5xl font-thin opacity-70">+</span>
        <span class="relative text-sm font-bold">{@area.label}</span>
        <span class="relative px-3 text-center text-xs leading-tight text-base-content/70">
          {@area.instruction}
        </span>
        <p :if={@tile_error} class="relative text-xs font-semibold text-error">{@tile_error}</p>
      </label>

      <div
        :if={!@entry && !@photo && @completed}
        class="flex h-40 items-center justify-center rounded-2xl border border-base-300 bg-base-200/40 px-3 text-center text-xs text-base-content/60"
      >
        No {@type} photo captured for {@area.label}.
      </div>

      <.live_file_input
        :if={!@completed}
        upload={@upload}
        capture="environment"
        class="sr-only"
      />
    </div>
    """
  end

  defp tile_accent(:before), do: "border-warning bg-warning/5 text-warning active:bg-warning/20"
  defp tile_accent(:after), do: "border-success bg-success/5 text-success active:bg-success/20"

  # --- Photo Helpers ---

  defp tile_upload_opts do
    base = [
      accept: ~w(.jpg .jpeg .png .webp),
      max_entries: 1,
      max_file_size: 10_000_000,
      auto_upload: true,
      progress: &handle_tile_progress/3
    ]

    if PhotoUpload.external_uploads?() do
      base ++ [external: &presign_photo/2]
    else
      base
    end
  end

  defp presign_photo(entry, socket) do
    {photo_type, _area} = parse_tile_name(entry.upload_config)

    case PhotoUpload.external_entry_meta(entry, socket.assigns.appointment.id, photo_type) do
      {:ok, meta} -> {:ok, meta, socket}
      {:error, reason} -> {:error, %{reason: inspect(reason)}, socket}
    end
  end

  # Auto-save: each tile's entry is consumed the moment its transfer
  # completes. Success re-renders the tile with the persisted photo;
  # failure lands in @tile_errors for that tile (no flash either way).
  defp handle_tile_progress(name, entry, socket) do
    if entry.done? do
      {photo_type, area} = parse_tile_name(name)
      appointment_id = socket.assigns.appointment.id

      result =
        consume_uploaded_entry(socket, entry, fn meta ->
          {:ok, save_tile_file(meta, appointment_id, entry.client_name, photo_type, area)}
        end)

      case result do
        {:ok, _photo} ->
          AppointmentTracker.broadcast_photo(appointment_id, photo_type)

          {:noreply,
           socket
           |> update(:tile_errors, &Map.delete(&1, name))
           |> reload_photos()
           |> maybe_complete_wash()}

        {:error, reason} ->
          {:noreply, update(socket, :tile_errors, &Map.put(&1, name, save_error_message(reason)))}
      end
    else
      {:noreply, update(socket, :tile_errors, &Map.delete(&1, name))}
    end
  end

  defp save_tile_file(%{key: key}, appointment_id, client_name, photo_type, area) do
    case PhotoUpload.save_external_file(appointment_id, key, client_name, photo_type,
           uploaded_by: :technician,
           car_part: area
         ) do
      {:ok, _photo} = ok ->
        ok

      {:error, reason} ->
        # The object is already in the bucket but has no DB row — remove
        # it best-effort so failed saves don't strand orphans.
        _ = PhotoUpload.delete_file(%{file_path: key})
        {:error, reason}
    end
  end

  defp save_tile_file(%{path: path}, appointment_id, client_name, photo_type, area) do
    PhotoUpload.save_file(appointment_id, path, client_name, photo_type,
      uploaded_by: :technician,
      car_part: area
    )
  end

  defp save_error_message(reason) when is_binary(reason), do: "Could not save photo: #{reason}"
  defp save_error_message(_reason), do: "Could not save photo — please try again."

  defp tile_upload_name(type, area_id), do: :"#{type}_#{area_id}"

  defp parse_tile_name(name) do
    [type, area] = name |> Atom.to_string() |> String.split("_", parts: 2)
    {String.to_existing_atom(type), String.to_existing_atom(area)}
  end

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

  defp save_wrap_up_notes(checklist, final_notes) do
    checklist
    |> Ash.Changeset.for_update(:save_wrap_up, %{final_notes: final_notes})
    |> Ash.update(authorize?: false)
  end

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
        MobileCarWash.Operations.TechEarnings.wash_earnings(
          %{price_cents: price_cents},
          technician
        )

      _ ->
        nil
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

  defp wrap_up_ready?(_items, _after_photos, %{status: :completed}), do: true

  defp wrap_up_ready?(items, after_photos, _checklist) do
    all_required_complete?(items) and after_photos_complete?(after_photos)
  end

  defp wash_command(%{checklist: %{status: :completed, final_notes: final_notes}})
       when not is_nil(final_notes) do
    %{
      title: "Wash complete",
      body: "Review wrap-up details, then return to your dashboard for the next assignment.",
      badge: "Done",
      badge_class: "badge-success",
      action: %{
        type: :navigate,
        id: "wash-command-dashboard",
        to: ~p"/tech",
        label: "Back to dashboard"
      }
    }
  end

  defp wash_command(%{checklist: %{status: :completed, final_notes: nil}}) do
    %{
      title: "Wrap up",
      body: "The wash is complete. Add final notes and supplies used before leaving the job.",
      badge: "Wrap-up",
      badge_class: "badge-success",
      action: %{
        type: :anchor,
        id: "wash-command-wrap-up",
        to: "#wrap-up-panel",
        label: "Wrap up"
      }
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
          action: %{
            type: :anchor,
            id: "wash-command-before-photos",
            to: "#before-photo-progress",
            label: "Finish before photos"
          }
        }

      active = Enum.find(assigns.items, &(&1.started_at && !&1.completed)) ->
        %{
          title: "Complete #{active.title}",
          body: "Timer is running. Finish this step when the work is done.",
          badge: "Active",
          badge_class: "badge-info",
          action: %{
            type: :event,
            id: "wash-command-complete-step",
            event: "complete_step",
            item_id: active.id,
            label: "Complete #{active.title}"
          }
        }

      next = Enum.find(assigns.items, &(not &1.completed)) ->
        %{
          title: "Start #{next.title}",
          body: "Before photos are complete. Start the next checklist step.",
          badge: "Step",
          badge_class: "badge-primary",
          action: %{
            type: :event,
            id: "wash-command-start-step",
            event: "start_step",
            item_id: next.id,
            label: "Start #{next.title}"
          }
        }

      not after_photos_complete?(assigns.after_photos) ->
        %{
          title: "Finish after photos",
          body: "All required steps are complete. Match the before photos before wrap-up.",
          badge: "Photos",
          badge_class: "badge-success",
          action: %{
            type: :anchor,
            id: "wash-command-after-photos",
            to: "#after-photo-progress",
            label: "Finish after photos"
          }
        }

      true ->
        %{
          title: "Wrap up",
          body: "Photos and steps are complete. Add final notes and supplies used.",
          badge: "Wrap-up",
          badge_class: "badge-success",
          action: %{
            type: :anchor,
            id: "wash-command-wrap-up",
            to: "#wrap-up-panel",
            label: "Wrap up"
          }
        }
    end
  end

  defp area_photo(photos, area_id) do
    Enum.find(photos, &(&1.car_part == area_id))
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
