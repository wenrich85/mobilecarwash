defmodule MobileCarWashWeb.Admin.OperationsComponents do
  @moduledoc "Function components for E-Myth org chart and SOPs."
  use Phoenix.Component

  attr :position, :map, required: true
  attr :children, :list, default: []

  def org_node(assigns) do
    ~H"""
    <div class="flex flex-col items-center">
      <div class="card bg-base-100 shadow-md w-56 border-l-4 border-primary">
        <div class="card-body p-4">
          <h3 class="card-title text-sm">{@position.name}</h3>
          <p :if={@position.description} class="text-xs text-base-content/80 line-clamp-2">
            {@position.description}
          </p>
          <div class="badge badge-ghost badge-xs">Level {@position.level}</div>
        </div>
      </div>
      <div :if={@children != []} class="flex gap-4 mt-4 pt-4 border-t border-base-300">
        <.org_node :for={child <- @children} position={child} children={child[:children] || []} />
      </div>
    </div>
    """
  end

  attr :procedure, :map, required: true
  attr :steps, :list, default: []
  attr :expanded, :boolean, default: false

  def procedure_card(assigns) do
    total_min = Enum.reduce(assigns.steps, 0, fn s, acc -> acc + (s.estimated_minutes || 0) end)
    assigns = assign(assigns, total_minutes: total_min)

    ~H"""
    <div class="card bg-base-100 shadow-xl">
      <div class="card-body">
        <div class="flex justify-between items-start">
          <div>
            <h3 class="card-title">{@procedure.name}</h3>
            <p :if={@procedure.description} class="text-sm text-base-content/80 mt-1">
              {@procedure.description}
            </p>
          </div>
          <div class="flex gap-2">
            <span class="badge badge-primary">{length(@steps)} steps</span>
            <span class="badge badge-ghost">~{@total_minutes} min</span>
            <span class="badge badge-outline">{@procedure.category}</span>
          </div>
        </div>

        <div :if={@expanded} class="mt-4">
          <div class="overflow-x-auto">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>#</th>
                  <th>Step</th>
                  <th>Est. Time</th>
                  <th>Required</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={step <- @steps}>
                  <td class="font-mono text-sm">{step.step_number}</td>
                  <td>
                    <div class="font-semibold">{step.title}</div>
                    <div :if={step.description} class="text-xs text-base-content/70">
                      {step.description}
                    </div>
                  </td>
                  <td>{step.estimated_minutes || "-"} min</td>
                  <td>
                    <span :if={step.required} class="badge badge-error badge-xs">Required</span>
                    <span :if={!step.required} class="badge badge-ghost badge-xs">Optional</span>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <div class="card-actions justify-end mt-4">
          <button
            class="btn btn-ghost btn-sm"
            phx-click="toggle_procedure"
            phx-value-id={@procedure.id}
          >
            {if @expanded, do: "Collapse", else: "View Steps"}
          </button>
        </div>
      </div>
    </div>
    """
  end
end
