defmodule MobileCarWashWeb.Admin.OrgChartLive do
  @moduledoc """
  E-Myth organizational chart — shows the franchise prototype structure.
  Every position is defined even though one person fills them all (for now).
  """
  use MobileCarWashWeb, :live_view

  import MobileCarWashWeb.Admin.OperationsComponents

  alias MobileCarWash.Operations.OrgPosition

  require Ash.Query

  @impl true
  def mount(_params, _session, socket) do
    positions = Ash.read!(OrgPosition) |> Enum.sort_by(& &1.sort_order)

    # Build tree structure
    root = Enum.find(positions, &(&1.level == 0))
    tree = if root, do: build_tree(root, positions), else: nil

    {:ok,
     assign(socket,
       page_title: "Org Chart",
       positions: positions,
       tree: tree
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto py-8 px-4">
      <div class="flex justify-between items-center mb-8">
        <div>
          <h1 class="text-3xl font-bold">Organization Chart</h1>
          <p class="text-base-content/60">E-Myth franchise prototype — every position defined</p>
        </div>
        <div class="flex gap-2">
          <.link navigate={~p"/admin/procedures"} class="btn btn-outline btn-sm">SOPs</.link>
          <.link navigate={~p"/admin/metrics"} class="btn btn-outline btn-sm">Dashboard</.link>
        </div>
      </div>

      <!-- Visual Org Chart -->
      <div :if={@tree} class="flex justify-center mb-12 overflow-x-auto p-8">
        <.org_node position={@tree} children={@tree[:children] || []} />
      </div>

      <!-- Position List -->
      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div :for={pos <- @positions} class="card bg-base-100 shadow">
          <div class="card-body p-4">
            <div class="flex justify-between items-start">
              <h3 class="font-bold">{pos.name}</h3>
              <span class="badge badge-primary badge-sm">Level {pos.level}</span>
            </div>
            <p :if={pos.description} class="text-sm text-base-content/60 mt-2">{pos.description}</p>
          </div>
        </div>
      </div>

      <div class="mt-8 p-4 bg-base-200 rounded-lg">
        <p class="text-sm text-base-content/60">
          <strong>E-Myth Principle:</strong> Build it as if you're going to franchise 5,000 of them.
          Define every position now — when you hire, the systems (not the people) run the business.
        </p>
      </div>
    </div>
    """
  end

  defp build_tree(position, all_positions) do
    children =
      all_positions
      |> Enum.filter(&(&1.parent_position_id == position.id))
      |> Enum.sort_by(& &1.sort_order)
      |> Enum.map(&build_tree(&1, all_positions))

    %{
      id: position.id,
      name: position.name,
      slug: position.slug,
      description: position.description,
      level: position.level,
      children: children
    }
  end
end
