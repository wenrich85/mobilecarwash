defmodule MobileCarWashWeb.Admin.ProceduresLive do
  @moduledoc """
  SOP editor — view, add, edit, delete, and drag-to-reorder procedure steps.
  The systems that run the business.
  """
  use MobileCarWashWeb, :live_view

  alias MobileCarWash.Operations.{Procedure, ProcedureStep}

  require Ash.Query

  @impl true
  def mount(_params, _session, socket) do
    procedures = Ash.read!(Procedure) |> Enum.sort_by(& &1.name)
    steps_by_proc = load_steps(procedures)

    {:ok,
     assign(socket,
       page_title: "Standard Operating Procedures",
       procedures: procedures,
       steps_by_proc: steps_by_proc,
       expanded: MapSet.new(),
       editing_step: nil
     )}
  end

  # === Event Handlers ===

  @impl true
  def handle_event("toggle_procedure", %{"id" => id}, socket) do
    expanded =
      if MapSet.member?(socket.assigns.expanded, id) do
        MapSet.delete(socket.assigns.expanded, id)
      else
        MapSet.put(socket.assigns.expanded, id)
      end

    {:noreply, assign(socket, expanded: expanded)}
  end

  def handle_event("add_step", %{"procedure-id" => proc_id}, socket) do
    existing_steps = Map.get(socket.assigns.steps_by_proc, proc_id, [])
    next_number = (existing_steps |> Enum.map(& &1.step_number) |> Enum.max(fn -> 0 end)) + 1

    case ProcedureStep
         |> Ash.Changeset.for_create(:create, %{
           step_number: next_number,
           title: "New Step",
           estimated_minutes: 5,
           required: true
         })
         |> Ash.Changeset.force_change_attribute(:procedure_id, proc_id)
         |> Ash.create() do
      {:ok, _step} ->
        {:noreply, socket |> reload_steps() |> put_flash(:info, "Step added")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not add step")}
    end
  end

  def handle_event("edit_step", %{"id" => step_id}, socket) do
    {:noreply, assign(socket, editing_step: step_id)}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, editing_step: nil)}
  end

  def handle_event("save_step", %{"id" => step_id} = params, socket) do
    # Find the step across all procedures
    step = find_step(socket.assigns.steps_by_proc, step_id)

    if step do
      updates = %{
        title: params["title"] || step.title,
        description: params["description"],
        estimated_minutes: parse_int(params["estimated_minutes"]),
        required: params["required"] == "true"
      }

      case step |> Ash.Changeset.for_update(:update, updates) |> Ash.update() do
        {:ok, _} ->
          {:noreply, socket |> assign(editing_step: nil) |> reload_steps()}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not save step")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("delete_step", %{"id" => step_id}, socket) do
    step = find_step(socket.assigns.steps_by_proc, step_id)

    if step do
      case Ash.destroy(step) do
        :ok ->
          # Renumber remaining steps
          renumber_steps(step.procedure_id, socket)
          {:noreply, socket |> reload_steps() |> put_flash(:info, "Step deleted")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not delete step")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("reorder_steps", %{"procedure_id" => _proc_id, "step_ids" => step_ids}, socket) do
    import Ecto.Query

    # Update step_number for each step based on new position
    step_ids
    |> Enum.with_index(1)
    |> Enum.each(fn {step_id, new_number} ->
      MobileCarWash.Repo.update_all(
        from(s in "procedure_steps", where: s.id == type(^step_id, :binary_id)),
        set: [step_number: new_number]
      )
    end)

    {:noreply, socket |> reload_steps() |> put_flash(:info, "Steps reordered")}
  end

  # === Render ===

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-5xl mx-auto py-8 px-4">
      <div class="flex justify-between items-center mb-8">
        <div>
          <h1 class="text-3xl font-bold">Standard Operating Procedures</h1>
          <p class="text-base-content/60">The systems that run the business</p>
        </div>
        <div class="flex gap-2">
          <.link navigate={~p"/admin/org-chart"} class="btn btn-outline btn-sm">Org Chart</.link>
          <.link navigate={~p"/admin/metrics"} class="btn btn-outline btn-sm">Dashboard</.link>
        </div>
      </div>

      <div class="space-y-6">
        <div :for={proc <- @procedures} class="card bg-base-100 shadow-xl">
          <div class="card-body">
            <div class="flex justify-between items-start">
              <div>
                <h3 class="card-title">{proc.name}</h3>
                <p :if={proc.description} class="text-sm text-base-content/60 mt-1">{proc.description}</p>
              </div>
              <div class="flex gap-2">
                <span class="badge badge-primary">{length(Map.get(@steps_by_proc, proc.id, []))} steps</span>
                <span class="badge badge-ghost">~{total_minutes(Map.get(@steps_by_proc, proc.id, []))} min</span>
                <span class="badge badge-outline">{proc.category}</span>
              </div>
            </div>

            <div :if={MapSet.member?(@expanded, proc.id)} class="mt-4">
              <!-- Draggable step list -->
              <div
                id={"steps-#{proc.id}"}
                phx-hook="Sortable"
                data-procedure-id={proc.id}
              >
                <div
                  :for={step <- Map.get(@steps_by_proc, proc.id, [])}
                  data-sort-id={step.id}
                  draggable="true"
                  class="flex items-center gap-3 py-2 px-3 mb-1 bg-base-200 rounded-lg cursor-grab active:cursor-grabbing transition-all"
                >
                  <!-- Drag handle -->
                  <span class="text-base-content/30 select-none">⠿</span>

                  <div :if={@editing_step != step.id} class="flex-1 flex items-center gap-3">
                    <span class="font-mono text-sm text-base-content/40 w-6">{step.step_number}</span>
                    <div class="flex-1">
                      <span class="font-semibold">{step.title}</span>
                      <span :if={step.description} class="text-xs text-base-content/50 ml-2">{step.description}</span>
                    </div>
                    <span class="text-xs text-base-content/50">{step.estimated_minutes || 5}m</span>
                    <span :if={step.required} class="badge badge-error badge-xs">Req</span>
                    <span :if={!step.required} class="badge badge-ghost badge-xs">Opt</span>
                    <button class="btn btn-ghost btn-xs" phx-click="edit_step" phx-value-id={step.id}>Edit</button>
                    <button class="btn btn-ghost btn-xs text-error" phx-click="delete_step" phx-value-id={step.id}>×</button>
                  </div>

                  <!-- Inline edit form -->
                  <form :if={@editing_step == step.id} phx-submit="save_step" phx-value-id={step.id} class="flex-1 flex items-center gap-2">
                    <input type="text" name="title" value={step.title} class="input input-bordered input-xs flex-1" />
                    <input type="text" name="description" value={step.description} placeholder="Description" class="input input-bordered input-xs flex-1" />
                    <input type="number" name="estimated_minutes" value={step.estimated_minutes} class="input input-bordered input-xs w-16" min="1" />
                    <select name="required" class="select select-bordered select-xs">
                      <option value="true" selected={step.required}>Req</option>
                      <option value="false" selected={!step.required}>Opt</option>
                    </select>
                    <button type="submit" class="btn btn-primary btn-xs">Save</button>
                    <button type="button" class="btn btn-ghost btn-xs" phx-click="cancel_edit">Cancel</button>
                  </form>
                </div>
              </div>

              <!-- Add Step button -->
              <button
                class="btn btn-outline btn-sm btn-block mt-3"
                phx-click="add_step"
                phx-value-procedure-id={proc.id}
              >
                + Add Step
              </button>
            </div>

            <div class="card-actions justify-end mt-4">
              <button class="btn btn-ghost btn-sm" phx-click="toggle_procedure" phx-value-id={proc.id}>
                {if MapSet.member?(@expanded, proc.id), do: "Collapse", else: "View & Edit Steps"}
              </button>
            </div>
          </div>
        </div>
      </div>

      <div :if={@procedures == []} class="text-center py-12 text-base-content/50">
        No procedures defined yet.
      </div>

      <div class="mt-8 p-4 bg-base-200 rounded-lg">
        <p class="text-sm text-base-content/60">
          <strong>E-Myth Principle:</strong> The system is the solution.
          Every procedure is documented so anyone can follow it and deliver consistent results.
          Drag steps to reorder. When an appointment starts, a live checklist is created from these SOPs.
        </p>
      </div>
    </div>
    """
  end

  # === Private ===

  defp load_steps(procedures) do
    for proc <- procedures, into: %{} do
      steps =
        ProcedureStep
        |> Ash.Query.filter(procedure_id == ^proc.id)
        |> Ash.Query.sort(step_number: :asc)
        |> Ash.read!()

      {proc.id, steps}
    end
  end

  defp reload_steps(socket) do
    steps_by_proc = load_steps(socket.assigns.procedures)
    assign(socket, steps_by_proc: steps_by_proc)
  end

  defp find_step(steps_by_proc, step_id) do
    steps_by_proc
    |> Map.values()
    |> List.flatten()
    |> Enum.find(&(&1.id == step_id))
  end

  defp renumber_steps(procedure_id, _socket) do
    import Ecto.Query

    steps =
      ProcedureStep
      |> Ash.Query.filter(procedure_id == ^procedure_id)
      |> Ash.Query.sort(step_number: :asc)
      |> Ash.read!()

    steps
    |> Enum.with_index(1)
    |> Enum.each(fn {step, new_number} ->
      MobileCarWash.Repo.update_all(
        from(s in "procedure_steps", where: s.id == type(^step.id, :binary_id)),
        set: [step_number: new_number]
      )
    end)
  end

  defp total_minutes(steps) do
    Enum.reduce(steps, 0, fn s, acc -> acc + (s.estimated_minutes || 0) end)
  end

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil
  defp parse_int(str) when is_binary(str) do
    case Integer.parse(str) do
      {n, _} -> n
      :error -> nil
    end
  end
  defp parse_int(n) when is_integer(n), do: n
end
