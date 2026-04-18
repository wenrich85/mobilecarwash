defmodule MobileCarWashWeb.Admin.OrgChartLive do
  @moduledoc """
  E-Myth organizational chart — shows the franchise prototype structure.
  Every position is defined even though one person fills them all (for now).
  """
  use MobileCarWashWeb, :live_view

  import MobileCarWashWeb.Admin.OperationsComponents

  alias MobileCarWash.Operations.{OrgPosition, PositionContract}

  require Ash.Query

  @impl true
  def mount(_params, _session, socket) do
    positions = load_positions()

    # Build tree structure
    root = Enum.find(positions, &(&1.level == 0))
    tree = if root, do: build_tree(root, positions), else: nil

    {:ok,
     assign(socket,
       page_title: "Org Chart",
       positions: positions,
       tree: tree,
       editing_position: nil,
       selected_position_id: nil,
       contracts: []
     )}
  end

  # === Event Handlers ===

  @impl true
  def handle_event("add_position", %{"position" => params}, socket) do
    attrs = %{
      name: params["name"],
      slug: Slug.slugify(params["name"]),
      description: params["description"],
      level: parse_int(params["level"]),
      sort_order: parse_int(params["sort_order"]),
      parent_position_id: blank_to_nil(params["parent_position_id"])
    }

    case OrgPosition |> Ash.Changeset.for_create(:create, attrs) |> Ash.create() do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(positions: load_positions())
         |> put_flash(:info, "Position added")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not add position")}
    end
  end

  def handle_event("edit_position", %{"id" => id}, socket) do
    {:noreply, assign(socket, editing_position: id)}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, editing_position: nil)}
  end

  def handle_event("update_position", %{"id" => id, "position" => params}, socket) do
    case Ash.get(OrgPosition, id) do
      {:ok, pos} ->
        attrs = %{
          name: params["name"],
          description: params["description"],
          level: parse_int(params["level"]),
          sort_order: parse_int(params["sort_order"]),
          parent_position_id: blank_to_nil(params["parent_position_id"])
        }

        case pos |> Ash.Changeset.for_update(:update, attrs) |> Ash.update() do
          {:ok, _} ->
            {:noreply,
             socket
             |> assign(positions: load_positions(), editing_position: nil)
             |> put_flash(:info, "Position updated")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Could not update position")}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("delete_position", %{"id" => id}, socket) do
    case Ash.get(OrgPosition, id) do
      {:ok, pos} ->
        case Ash.destroy(pos) do
          :ok ->
            {:noreply,
             socket
             |> assign(positions: load_positions(), selected_position_id: nil, contracts: [])
             |> put_flash(:info, "Position deleted")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Could not delete position")}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("select_position", %{"id" => id}, socket) do
    contracts = load_contracts(id)
    {:noreply, assign(socket, selected_position_id: id, contracts: contracts)}
  end

  def handle_event("add_contract", %{"position_id" => position_id, "contract" => params}, socket) do
    attrs = %{
      title: params["title"],
      purpose: params["purpose"],
      responsibilities: params["responsibilities"],
      standards: params["standards"],
      active: true
    }

    case PositionContract
         |> Ash.Changeset.for_create(:create, attrs)
         |> Ash.Changeset.force_change_attribute(:position_id, position_id)
         |> Ash.create() do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(contracts: load_contracts(position_id))
         |> put_flash(:info, "Contract added")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not add contract")}
    end
  end

  def handle_event("delete_contract", %{"id" => id}, socket) do
    case Ash.get(PositionContract, id) do
      {:ok, contract} ->
        case Ash.destroy(contract) do
          :ok ->
            {:noreply,
             socket
             |> assign(contracts: load_contracts(socket.assigns.selected_position_id))
             |> put_flash(:info, "Contract deleted")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Could not delete contract")}
        end

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto py-8 px-4">
      <div class="flex justify-between items-center mb-8">
        <div>
          <h1 class="text-3xl font-bold">Organization Chart</h1>
          <p class="text-base-content/80">E-Myth franchise prototype — every position defined</p>
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

      <!-- Add Position -->
      <div class="card bg-base-100 shadow mb-6">
        <div class="card-body p-4">
          <h3 class="font-bold mb-3">Add Position</h3>
          <form phx-submit="add_position" class="grid grid-cols-1 md:grid-cols-5 gap-3 items-end">
            <div class="form-control">
              <label class="label label-text text-xs">Name</label>
              <input type="text" name="position[name]" class="input input-bordered input-sm" required placeholder="Position title" />
            </div>
            <div class="form-control">
              <label class="label label-text text-xs">Level</label>
              <input type="number" name="position[level]" class="input input-bordered input-sm" value="0" min="0" />
            </div>
            <div class="form-control">
              <label class="label label-text text-xs">Sort Order</label>
              <input type="number" name="position[sort_order]" class="input input-bordered input-sm" value="0" />
            </div>
            <div class="form-control">
              <label class="label label-text text-xs">Parent Position</label>
              <select name="position[parent_position_id]" class="select select-bordered select-sm">
                <option value="">None</option>
                <option :for={p <- @positions} value={p.id}>{p.name}</option>
              </select>
            </div>
            <button type="submit" class="btn btn-primary btn-sm">Add Position</button>
          </form>
          <div class="form-control mt-3">
            <label class="label label-text text-xs">Description</label>
            <input type="text" name="position[description]" form="add_position" class="input input-bordered input-sm" placeholder="Job description" />
          </div>
        </div>
      </div>

      <!-- Position List with CRUD -->
      <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mb-8">
        <div :for={pos <- @positions} class="card bg-base-100 shadow">
          <div class="card-body p-4">
            <!-- View mode -->
            <div :if={@editing_position != pos.id} class="flex justify-between items-start">
              <div class="flex-1 cursor-pointer" phx-click="select_position" phx-value-id={pos.id}>
                <h3 class="font-bold hover:text-primary">{pos.name}</h3>
                <span class="badge badge-primary badge-sm">Level {pos.level}</span>
                <p :if={pos.description} class="text-sm text-base-content/80 mt-2">{pos.description}</p>
              </div>
              <div class="flex gap-1">
                <button class="btn btn-ghost btn-xs" phx-click="edit_position" phx-value-id={pos.id}>Edit</button>
                <button class="btn btn-ghost btn-xs text-error" phx-click="delete_position" phx-value-id={pos.id}>Delete</button>
              </div>
            </div>

            <!-- Edit mode -->
            <form :if={@editing_position == pos.id} phx-submit="update_position" phx-value-id={pos.id} class="space-y-3">
              <div class="grid grid-cols-1 gap-3">
                <div class="form-control">
                  <label class="label label-text text-xs">Name</label>
                  <input type="text" name="position[name]" class="input input-bordered input-sm" value={pos.name} required />
                </div>
                <div class="grid grid-cols-3 gap-2">
                  <div class="form-control">
                    <label class="label label-text text-xs">Level</label>
                    <input type="number" name="position[level]" class="input input-bordered input-sm" value={pos.level} min="0" />
                  </div>
                  <div class="form-control">
                    <label class="label label-text text-xs">Sort Order</label>
                    <input type="number" name="position[sort_order]" class="input input-bordered input-sm" value={pos.sort_order} />
                  </div>
                  <div class="form-control">
                    <label class="label label-text text-xs">Parent</label>
                    <select name="position[parent_position_id]" class="select select-bordered select-sm">
                      <option value="">None</option>
                      <option :for={p <- @positions} value={p.id} selected={pos.parent_position_id == p.id}>{p.name}</option>
                    </select>
                  </div>
                </div>
                <div class="form-control">
                  <label class="label label-text text-xs">Description</label>
                  <textarea name="position[description]" class="textarea textarea-bordered textarea-sm">{pos.description}</textarea>
                </div>
              </div>
              <div class="flex gap-1">
                <button type="submit" class="btn btn-primary btn-sm flex-1">Save</button>
                <button type="button" class="btn btn-ghost btn-sm" phx-click="cancel_edit">Cancel</button>
              </div>
            </form>
          </div>
        </div>
      </div>

      <!-- Position Contracts Panel -->
      <div :if={@selected_position_id} class="card bg-base-100 shadow mb-8">
        <div class="card-body">
          <h3 class="card-title mb-4">Position Contract for {Enum.find(@positions, &(&1.id == @selected_position_id)).name}</h3>

          <!-- Add Contract Form -->
          <div class="mb-6 pb-6 border-b">
            <h4 class="font-semibold mb-3">Add Contract</h4>
            <form phx-submit="add_contract" phx-value-position-id={@selected_position_id} class="space-y-3">
              <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
                <div class="form-control">
                  <label class="label label-text text-xs">Contract Title</label>
                  <input type="text" name="contract[title]" class="input input-bordered input-sm" required placeholder="e.g., Lead Technician Agreement" />
                </div>
              </div>
              <div class="form-control">
                <label class="label label-text text-xs">Purpose</label>
                <textarea name="contract[purpose]" class="textarea textarea-bordered textarea-sm" placeholder="Primary purpose of this position"></textarea>
              </div>
              <div class="form-control">
                <label class="label label-text text-xs">Responsibilities (Markdown)</label>
                <textarea name="contract[responsibilities]" class="textarea textarea-bordered textarea-sm" placeholder="- Manage team scheduling&#10;- Conduct quality inspections&#10;- etc."></textarea>
              </div>
              <div class="form-control">
                <label class="label label-text text-xs">Performance Standards</label>
                <textarea name="contract[standards]" class="textarea textarea-bordered textarea-sm" placeholder="- 95% customer satisfaction&#10;- Complete 5 appointments/day&#10;- etc."></textarea>
              </div>
              <button type="submit" class="btn btn-primary btn-sm">Add Contract</button>
            </form>
          </div>

          <!-- Contracts List -->
          <div class="space-y-4">
            <div :for={contract <- @contracts} class="collapse collapse-arrow border border-base-300 bg-base-200">
              <input type="radio" name="contract-accordion" />
              <div class="collapse-title font-medium">
                <div class="flex justify-between items-center">
                  <span>{contract.title}</span>
                  <button class="btn btn-ghost btn-xs text-error" phx-click="delete_contract" phx-value-id={contract.id}>Delete</button>
                </div>
              </div>
              <div class="collapse-content space-y-3">
                <div :if={contract.purpose}>
                  <h5 class="font-semibold">Purpose</h5>
                  <p class="text-sm">{contract.purpose}</p>
                </div>
                <div :if={contract.responsibilities}>
                  <h5 class="font-semibold">Responsibilities</h5>
                  <div class="text-sm whitespace-pre-wrap">{contract.responsibilities}</div>
                </div>
                <div :if={contract.standards}>
                  <h5 class="font-semibold">Performance Standards</h5>
                  <div class="text-sm whitespace-pre-wrap">{contract.standards}</div>
                </div>
              </div>
            </div>
          </div>

          <div :if={@contracts == []} class="text-center py-8 text-base-content/70">
            No contracts defined for this position yet.
          </div>
        </div>
      </div>

      <div class="mt-8 p-4 bg-base-200 rounded-lg">
        <p class="text-sm text-base-content/80">
          <strong>E-Myth Principle:</strong> Build it as if you're going to franchise 5,000 of them.
          Define every position now — when you hire, the systems (not the people) run the business.
        </p>
      </div>
    </div>
    """
  end

  # === Private Helpers ===

  defp load_positions do
    OrgPosition |> Ash.read!() |> Enum.sort_by(& &1.sort_order)
  end

  defp load_contracts(position_id) do
    PositionContract
    |> Ash.Query.filter(position_id == ^position_id)
    |> Ash.read!()
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

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil
  defp parse_int(str) when is_binary(str) do
    case Integer.parse(str) do
      {n, _} -> n
      :error -> nil
    end
  end
  defp parse_int(n) when is_integer(n), do: n

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(str), do: str
end
