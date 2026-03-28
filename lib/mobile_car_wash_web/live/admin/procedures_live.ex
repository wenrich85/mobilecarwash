defmodule MobileCarWashWeb.Admin.ProceduresLive do
  @moduledoc """
  SOP (Standard Operating Procedures) manager — view and manage
  the step-by-step systems that run the business.
  """
  use MobileCarWashWeb, :live_view

  import MobileCarWashWeb.Admin.OperationsComponents

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
       expanded: MapSet.new()
     )}
  end

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
        <.procedure_card
          :for={proc <- @procedures}
          procedure={proc}
          steps={Map.get(@steps_by_proc, proc.id, [])}
          expanded={MapSet.member?(@expanded, proc.id)}
        />
      </div>

      <div :if={@procedures == []} class="text-center py-12 text-base-content/50">
        No procedures defined yet.
      </div>

      <div class="mt-8 p-4 bg-base-200 rounded-lg">
        <p class="text-sm text-base-content/60">
          <strong>E-Myth Principle:</strong> The system is the solution.
          Every procedure is documented so anyone can follow it and deliver consistent results.
          When an appointment starts, a live checklist is created from these SOPs.
        </p>
      </div>
    </div>
    """
  end

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
end
