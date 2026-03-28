defmodule MobileCarWashWeb.ChecklistLive do
  @moduledoc """
  Mobile-friendly checklist UI for technicians during appointments.
  Features: step checkoff, photo uploads (before/after/per-step),
  customer problem area display, and real-time PubSub broadcasting.
  """
  use MobileCarWashWeb, :live_view

  alias MobileCarWash.Operations.{AppointmentChecklist, ChecklistItem, Photo, PhotoUpload}
  alias MobileCarWash.Scheduling.{Appointment, AppointmentTracker}

  require Ash.Query

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

        # Load photos
        all_photos =
          Ash.read!(Photo,
            action: :for_appointment,
            arguments: %{appointment_id: appointment.id}
          )

        problem_photos = Enum.filter(all_photos, &(&1.photo_type == :problem_area))
        step_photos = Enum.filter(all_photos, &(&1.photo_type in [:before, :after, :step_completion]))

        total = length(items)
        done = Enum.count(items, & &1.completed)
        pct = if total > 0, do: Float.round(done / total * 100, 0), else: 0

        socket =
          socket
          |> assign(
            page_title: "Checklist",
            checklist: checklist,
            items: items,
            appointment: appointment,
            problem_photos: problem_photos,
            step_photos: step_photos,
            total: total,
            done: done,
            pct: pct,
            show_photo_upload: nil
          )
          |> allow_upload(:photo, accept: ~w(.jpg .jpeg .png .webp), max_entries: 1, max_file_size: 10_000_000)

        {:ok, socket}

      {:error, _} ->
        {:ok,
         socket
         |> assign(page_title: "Checklist", checklist: nil, items: [], appointment: nil,
            problem_photos: [], step_photos: [], total: 0, done: 0, pct: 0, show_photo_upload: nil)
         |> put_flash(:error, "Checklist not found")}
    end
  end

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Checklist", checklist: nil, items: [], appointment: nil,
        problem_photos: [], step_photos: [], total: 0, done: 0, pct: 0, show_photo_upload: nil)
     |> put_flash(:error, "No checklist specified")}
  end

  @impl true
  def handle_event("toggle_item", %{"id" => item_id}, socket) do
    item = Enum.find(socket.assigns.items, &(&1.id == item_id))

    if item do
      action = if item.completed, do: :uncheck, else: :check

      {:ok, updated} =
        item
        |> Ash.Changeset.for_update(action, %{})
        |> Ash.update()

      items = Enum.map(socket.assigns.items, fn i -> if i.id == item_id, do: updated, else: i end)
      done = Enum.count(items, & &1.completed)
      pct = if socket.assigns.total > 0, do: Float.round(done / socket.assigns.total * 100, 0), else: 0

      # Broadcast progress
      remaining = Enum.filter(items, &(!&1.completed))
      current_step_name = if updated.completed, do: next_step_name(items, updated), else: updated.title

      AppointmentTracker.broadcast_progress(socket.assigns.appointment.id, %{
        current_step: current_step_name,
        steps_done: done,
        steps_total: socket.assigns.total,
        steps_remaining: Enum.map(remaining, fn _ -> %{estimated_minutes: 5} end)
      })

      # Auto-complete checklist
      socket =
        if all_required_complete?(items) and socket.assigns.checklist.status != :completed do
          {:ok, checklist} =
            socket.assigns.checklist
            |> Ash.Changeset.for_update(:complete_checklist, %{})
            |> Ash.update()

          assign(socket, checklist: checklist)
        else
          socket
        end

      {:noreply, assign(socket, items: items, done: done, pct: pct)}
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

  def handle_event("save_photo", _params, socket) do
    %{type: type_str, item_id: item_id} = socket.assigns.show_photo_upload
    photo_type = String.to_existing_atom(type_str)
    appointment_id = socket.assigns.appointment.id

    uploaded_files =
      consume_uploaded_entries(socket, :photo, fn %{path: path}, entry ->
        opts = [
          uploaded_by: :technician,
          checklist_item_id: item_id
        ]

        case PhotoUpload.save_file(appointment_id, path, entry.client_name, photo_type, opts) do
          {:ok, photo} -> {:ok, photo}
          {:error, reason} -> {:postpone, reason}
        end
      end)

    # Broadcast photo uploaded
    AppointmentTracker.broadcast_photo(appointment_id, photo_type)

    # Refresh photos
    step_photos = socket.assigns.step_photos ++ uploaded_files

    {:noreply,
     socket
     |> assign(step_photos: step_photos, show_photo_upload: nil)
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
            <span class={[
              "badge badge-lg",
              checklist_badge_class(@checklist.status)
            ]}>
              {@done}/{@total}
            </span>
          </div>
          <progress class="progress progress-primary w-full" value={@pct} max="100"></progress>
          <p class="text-sm text-base-content/50 mt-1">{@pct}% complete</p>
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

        <!-- Uploaded Step Photos -->
        <div :if={@step_photos != []} class="flex gap-2 overflow-x-auto mb-4">
          <div :for={photo <- @step_photos} class="flex-shrink-0 relative">
            <img src={photo.file_path} class="w-16 h-16 object-cover rounded" />
            <span class={["badge badge-xs absolute -top-1 -right-1", photo_badge(@photo_type)]}>
              {photo_label(photo.photo_type)}
            </span>
          </div>
        </div>

        <!-- Checklist Items -->
        <div class="space-y-2">
          <div
            :for={item <- @items}
            class={[
              "card bg-base-100 shadow-sm transition-all",
              item.completed && "opacity-60"
            ]}
          >
            <div class="card-body p-4">
              <div class="flex items-start gap-3">
                <div class="mt-1 cursor-pointer" phx-click="toggle_item" phx-value-id={item.id}>
                  <input
                    type="checkbox"
                    class="checkbox checkbox-primary"
                    checked={item.completed}
                    readonly
                  />
                </div>
                <div class="flex-1">
                  <div class="flex justify-between">
                    <span class={["font-semibold", item.completed && "line-through"]}>
                      {item.step_number}. {item.title}
                    </span>
                    <span :if={item.required} class="badge badge-error badge-xs">Required</span>
                  </div>
                  <p :if={item.description} class="text-xs text-base-content/60 mt-1">{item.description}</p>
                  <p :if={item.notes} class="text-xs text-info mt-1">Note: {item.notes}</p>
                </div>
              </div>
              <!-- Per-step photo button -->
              <div :if={!item.completed} class="mt-2 pl-10">
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
          <button class="btn btn-success btn-block btn-sm" phx-click="show_upload" phx-value-type="after">
            Take AFTER Photo to Complete
          </button>
        </div>

        <!-- Complete Banner -->
        <div :if={@checklist.status == :completed} class="mt-6 text-center">
          <div class="text-4xl mb-2">✓</div>
          <h2 class="text-xl font-bold text-success">Checklist Complete!</h2>
          <p class="text-sm text-base-content/60">All steps verified</p>
        </div>
      </div>

      <div :if={!@checklist} class="text-center py-12">
        <p class="text-base-content/50">No active checklist</p>
      </div>
    </div>
    """
  end

  # Suppress unused upload validation
  @impl true
  def handle_event("validate_upload", _params, socket), do: {:noreply, socket}

  defp all_required_complete?(items) do
    items |> Enum.filter(& &1.required) |> Enum.all?(& &1.completed)
  end

  defp next_step_name(items, current) do
    next = Enum.find(items, fn i -> i.step_number > current.step_number and not i.completed end)
    if next, do: next.title, else: "Finishing up"
  end

  defp checklist_badge_class(:completed), do: "badge-success"
  defp checklist_badge_class(:in_progress), do: "badge-info"
  defp checklist_badge_class(_), do: "badge-ghost"

  defp photo_badge(:before), do: "badge-warning"
  defp photo_badge(:after), do: "badge-success"
  defp photo_badge(_), do: "badge-ghost"

  defp photo_label(:before), do: "B"
  defp photo_label(:after), do: "A"
  defp photo_label(:step_completion), do: "S"
  defp photo_label(_), do: ""
end
