defmodule MobileCarWashWeb.ChecklistLive do
  @moduledoc """
  Interactive technician checklist with live step timers.

  Timer colors:
  - Green: within estimated time
  - Yellow: 45 seconds remaining
  - Red: over time

  Every step completion broadcasts to the customer's status page via PubSub.
  Actual vs estimated time is recorded for process optimization.
  """
  use MobileCarWashWeb, :live_view

  alias MobileCarWash.Operations.{AppointmentChecklist, ChecklistItem, Photo, PhotoUpload}
  alias MobileCarWash.Scheduling.{Appointment, AppointmentTracker}

  require Ash.Query

  @timer_tick_ms 1000

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

        # Load customer problem area photos
        problem_photos =
          Photo
          |> Ash.Query.filter(appointment_id == ^appointment.id and photo_type == :problem_area)
          |> Ash.read!()

        total = length(items)
        done = Enum.count(items, & &1.completed)
        pct = if total > 0, do: Float.round(done / total * 100, 0), else: 0

        # Start the 1-second timer tick
        if connected?(socket), do: Process.send_after(self(), :tick, @timer_tick_ms)

        socket =
          socket
          |> assign(
            page_title: "Checklist",
            checklist: checklist,
            items: items,
            appointment: appointment,
            problem_photos: problem_photos,
            total: total,
            done: done,
            pct: pct,
            active_item_id: nil,
            elapsed_seconds: 0,
            show_photo_upload: nil,
            now: DateTime.utc_now()
          )
          |> allow_upload(:photo, accept: ~w(.jpg .jpeg .png .webp), max_entries: 1, max_file_size: 10_000_000)

        {:ok, socket}

      {:error, _} ->
        {:ok,
         socket
         |> assign(page_title: "Checklist", checklist: nil, items: [], appointment: nil,
            problem_photos: [], total: 0, done: 0, pct: 0, active_item_id: nil,
            elapsed_seconds: 0, show_photo_upload: nil, now: DateTime.utc_now())
         |> put_flash(:error, "Checklist not found")}
    end
  end

  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Checklist", checklist: nil, items: [], appointment: nil,
      problem_photos: [], total: 0, done: 0, pct: 0, active_item_id: nil,
      elapsed_seconds: 0, show_photo_upload: nil, now: DateTime.utc_now())}
  end

  # Timer tick — updates elapsed time for the active step
  @impl true
  def handle_info(:tick, socket) do
    Process.send_after(self(), :tick, @timer_tick_ms)
    {:noreply, assign(socket, now: DateTime.utc_now())}
  end

  @impl true
  def handle_event("start_step", %{"id" => item_id}, socket) do
    alias MobileCarWash.Booking.WashStateMachine

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

  def handle_event("complete_step", %{"id" => item_id}, socket) do
    alias MobileCarWash.Booking.WashStateMachine
    alias MobileCarWash.Scheduling.WashOrchestrator

    item = Enum.find(socket.assigns.items, &(&1.id == item_id))

    if item && WashStateMachine.can_complete_step?(item) do
      {:ok, updated} =
        item
        |> Ash.Changeset.for_update(:check, %{})
        |> Ash.update()

      items = Enum.map(socket.assigns.items, fn i -> if i.id == item_id, do: updated, else: i end)
      done = Enum.count(items, & &1.completed)
      pct = if socket.assigns.total > 0, do: Float.round(done / socket.assigns.total * 100, 0), else: 0

      # Find next incomplete step
      next = WashStateMachine.next_step(items)
      next_name = if next, do: next.title, else: "Finishing up"

      # Broadcast to customer
      AppointmentTracker.broadcast_step_progress(socket.assigns.appointment.id, %{
        current_step: next_name,
        steps_done: done,
        steps_total: socket.assigns.total,
        items: items
      })

      # Auto-complete wash if all required done
      socket =
        if WashStateMachine.all_required_complete?(items) and socket.assigns.checklist.status != :completed do
          {:ok, checklist} =
            socket.assigns.checklist
            |> Ash.Changeset.for_update(:complete_checklist, %{})
            |> Ash.update()

          # Also complete the appointment
          WashOrchestrator.complete_wash(socket.assigns.appointment.id)

          assign(socket, checklist: checklist)
        else
          socket
        end

      {:noreply, assign(socket, items: items, done: done, pct: pct, active_item_id: next && next.id)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("show_upload", %{"type" => type} = params, socket) do
    item_id = params["item-id"]
    {:noreply, assign(socket, show_photo_upload: %{type: type, item_id: item_id})}
  end

  def handle_event("cancel_upload", _params, socket) do
    {:noreply, assign(socket, show_photo_upload: nil)}
  end

  def handle_event("validate_upload", _params, socket), do: {:noreply, socket}

  def handle_event("save_photo", _params, socket) do
    %{type: type_str, item_id: item_id} = socket.assigns.show_photo_upload
    photo_type = String.to_existing_atom(type_str)
    appointment_id = socket.assigns.appointment.id

    consume_uploaded_entries(socket, :photo, fn %{path: path}, entry ->
      opts = [uploaded_by: :technician, checklist_item_id: item_id]
      case PhotoUpload.save_file(appointment_id, path, entry.client_name, photo_type, opts) do
        {:ok, photo} -> {:ok, photo}
        {:error, reason} -> {:postpone, reason}
      end
    end)

    AppointmentTracker.broadcast_photo(appointment_id, photo_type)

    {:noreply,
     socket
     |> assign(show_photo_upload: nil)
     |> put_flash(:info, "Photo uploaded")}
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

        <!-- Before Photo Prompt -->
        <div :if={@done == 0 and @checklist.status != :completed} class="mb-4">
          <button class="btn btn-warning btn-block btn-sm" phx-click="show_upload" phx-value-type="before">
            Take BEFORE Photo
          </button>
        </div>

        <!-- Photo Upload Modal -->
        <div :if={@show_photo_upload} class="card bg-base-200 shadow mb-4 p-4">
          <h3 class="font-semibold mb-2">Upload Photo ({@show_photo_upload.type})</h3>
          <form phx-submit="save_photo" phx-change="validate_upload">
            <.live_file_input upload={@uploads.photo} class="file-input file-input-bordered w-full mb-2" />
            <div :for={entry <- @uploads.photo.entries} class="mb-2">
              <.live_img_preview entry={entry} class="w-full h-40 object-cover rounded" />
            </div>
            <div class="flex gap-2">
              <button type="submit" class="btn btn-primary btn-sm flex-1">Save</button>
              <button type="button" class="btn btn-ghost btn-sm" phx-click="cancel_upload">Cancel</button>
            </div>
          </form>
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

                  <p :if={item.notes} class="text-xs text-info mt-1">Note: {item.notes}</p>
                </div>
              </div>

              <!-- Action Buttons -->
              <div :if={!item.completed} class="mt-2 flex gap-2 justify-end">
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
                  class="btn btn-ghost btn-xs"
                  phx-click="show_upload"
                  phx-value-type="step_completion"
                  phx-value-item-id={item.id}
                >
                  + Photo
                </button>
              </div>
            </div>
          </div>
        </div>

        <!-- After Photo Prompt -->
        <div :if={all_required_complete?(@items) and @checklist.status != :completed} class="mt-4">
          <button class="btn btn-success btn-block" phx-click="show_upload" phx-value-type="after">
            Take AFTER Photo to Complete
          </button>
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
