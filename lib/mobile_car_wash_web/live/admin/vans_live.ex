defmodule MobileCarWashWeb.Admin.VansLive do
  @moduledoc """
  Admin page for managing service vans.
  """
  use MobileCarWashWeb, :live_view

  alias MobileCarWash.Operations.Van

  require Ash.Query

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Vans",
       vans: load_vans(),
       editing_van: nil
     )}
  end

  @impl true
  def handle_event("add_van", %{"van" => params}, socket) do
    attrs = %{
      name: params["name"],
      license_plate: blank_to_nil(params["license_plate"]),
      active: true
    }

    case Van |> Ash.Changeset.for_create(:create, attrs) |> Ash.create() do
      {:ok, _} ->
        {:noreply, socket |> assign(vans: load_vans()) |> put_flash(:info, "Van added")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not add van")}
    end
  end

  def handle_event("edit_van", %{"id" => id}, socket) do
    {:noreply, assign(socket, editing_van: id)}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, editing_van: nil)}
  end

  def handle_event("update_van", %{"id" => id, "van" => params}, socket) do
    case Ash.get(Van, id) do
      {:ok, van} ->
        attrs = %{
          name: params["name"],
          license_plate: blank_to_nil(params["license_plate"])
        }

        case van |> Ash.Changeset.for_update(:update, attrs) |> Ash.update() do
          {:ok, _} ->
            {:noreply,
             socket |> assign(vans: load_vans(), editing_van: nil) |> put_flash(:info, "Van updated")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Could not update van")}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("toggle_van", %{"id" => id}, socket) do
    case Ash.get(Van, id) do
      {:ok, van} ->
        van
        |> Ash.Changeset.for_update(:update, %{active: !van.active})
        |> Ash.update()

        {:noreply, assign(socket, vans: load_vans())}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-5xl mx-auto py-8 px-4">
      <h1 class="text-3xl font-bold mb-2">Vans</h1>
      <p class="text-base-content/80 mb-6">Manage service vans and equipment.</p>

      <!-- Add Van -->
      <div class="card bg-base-100 shadow mb-6">
        <div class="card-body p-4">
          <h3 class="font-bold mb-3">Add Van</h3>
          <form phx-submit="add_van" class="grid grid-cols-1 md:grid-cols-3 gap-3 items-end">
            <div class="form-control">
              <label class="label label-text text-xs">Van Name</label>
              <input type="text" name="van[name]" class="input input-bordered input-sm" required placeholder="Van 1" />
            </div>
            <div class="form-control">
              <label class="label label-text text-xs">License Plate</label>
              <input type="text" name="van[license_plate]" class="input input-bordered input-sm" placeholder="ABC123" />
            </div>
            <button type="submit" class="btn btn-primary btn-sm">Add Van</button>
          </form>
        </div>
      </div>

      <!-- Van List -->
      <div class="space-y-3">
        <div :for={van <- @vans} class={["card bg-base-100 shadow-sm", !van.active && "opacity-50"]}>
          <div class="card-body p-4">
            <!-- View mode -->
            <div :if={@editing_van != van.id} class="flex justify-between items-center">
              <div>
                <div class="flex items-center gap-2">
                  <h4 class="font-bold">{van.name}</h4>
                  <span :if={van.license_plate} class="badge badge-sm badge-ghost">{van.license_plate}</span>
                  <span :if={!van.active} class="badge badge-sm badge-error">Inactive</span>
                </div>
              </div>
              <div class="flex gap-2">
                <button class="btn btn-ghost btn-xs" phx-click="edit_van" phx-value-id={van.id}>Edit</button>
                <button
                  class={["btn btn-xs", if(van.active, do: "btn-warning", else: "btn-success")]}
                  phx-click="toggle_van"
                  phx-value-id={van.id}
                >
                  {if van.active, do: "Deactivate", else: "Activate"}
                </button>
              </div>
            </div>

            <!-- Edit mode -->
            <form :if={@editing_van == van.id} phx-submit="update_van" phx-value-id={van.id} class="grid grid-cols-1 md:grid-cols-3 gap-3 items-end">
              <div class="form-control">
                <label class="label label-text text-xs">Van Name</label>
                <input type="text" name="van[name]" class="input input-bordered input-sm" value={van.name} required />
              </div>
              <div class="form-control">
                <label class="label label-text text-xs">License Plate</label>
                <input type="text" name="van[license_plate]" class="input input-bordered input-sm" value={van.license_plate} />
              </div>
              <div class="flex gap-1">
                <button type="submit" class="btn btn-primary btn-sm flex-1">Save</button>
                <button type="button" class="btn btn-ghost btn-sm" phx-click="cancel_edit">Cancel</button>
              </div>
            </form>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # --- Helpers ---

  defp load_vans do
    Van |> Ash.Query.sort(name: :asc) |> Ash.read!()
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(str), do: str
end
