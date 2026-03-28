defmodule MobileCarWashWeb.ChecklistLive do
  @moduledoc """
  Mobile-friendly checklist UI for technicians to use during appointments.
  Shows the SOP steps — tap to check off each one. This is the E-Myth
  system in action: the system runs the business, not the person.
  """
  use MobileCarWashWeb, :live_view

  alias MobileCarWash.Operations.{AppointmentChecklist, ChecklistItem}
  alias MobileCarWash.Scheduling.Appointment

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

        total = length(items)
        done = Enum.count(items, & &1.completed)
        pct = if total > 0, do: Float.round(done / total * 100, 0), else: 0

        {:ok,
         assign(socket,
           page_title: "Checklist",
           checklist: checklist,
           items: items,
           appointment: appointment,
           total: total,
           done: done,
           pct: pct
         )}

      {:error, _} ->
        {:ok,
         socket
         |> assign(page_title: "Checklist", checklist: nil, items: [], appointment: nil, total: 0, done: 0, pct: 0)
         |> put_flash(:error, "Checklist not found")}
    end
  end

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Checklist", checklist: nil, items: [], appointment: nil, total: 0, done: 0, pct: 0)
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

      # Auto-complete checklist when all required items done
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

  def handle_event("add_note", %{"id" => item_id, "note" => note}, socket) do
    item = Enum.find(socket.assigns.items, &(&1.id == item_id))

    if item do
      {:ok, updated} =
        item
        |> Ash.Changeset.for_update(:add_note, %{notes: note})
        |> Ash.update()

      items = Enum.map(socket.assigns.items, fn i -> if i.id == item_id, do: updated, else: i end)
      {:noreply, assign(socket, items: items)}
    else
      {:noreply, socket}
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
            <span class={[
              "badge badge-lg",
              @checklist.status == :completed && "badge-success",
              @checklist.status == :in_progress && "badge-info",
              @checklist.status == :not_started && "badge-ghost"
            ]}>
              {@done}/{@total}
            </span>
          </div>
          <progress class="progress progress-primary w-full" value={@pct} max="100"></progress>
          <p class="text-sm text-base-content/50 mt-1">{@pct}% complete</p>
        </div>

        <!-- Checklist Items -->
        <div class="space-y-2">
          <div
            :for={item <- @items}
            class={[
              "card bg-base-100 shadow-sm cursor-pointer transition-all",
              item.completed && "opacity-60"
            ]}
            phx-click="toggle_item"
            phx-value-id={item.id}
          >
            <div class="card-body p-4 flex-row items-start gap-3">
              <div class="mt-1">
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
          </div>
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

  defp all_required_complete?(items) do
    items
    |> Enum.filter(& &1.required)
    |> Enum.all?(& &1.completed)
  end
end
