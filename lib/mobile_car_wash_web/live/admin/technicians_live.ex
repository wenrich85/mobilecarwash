defmodule MobileCarWashWeb.Admin.TechniciansLive do
  @moduledoc """
  Admin index of all technicians. Each row links to the detailed profile view.
  Also supports adding a new technician inline.
  """
  use MobileCarWashWeb, :live_view

  alias MobileCarWash.Operations.{Technician, Van}
  alias MobileCarWash.Zones

  require Ash.Query

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Technicians",
       technicians: load_technicians(),
       vans: load_vans(),
       editing: nil
     )}
  end

  @impl true
  def handle_event("add_technician", %{"tech" => params}, socket) do
    attrs = %{
      name: params["name"],
      phone: blank_to_nil(params["phone"]),
      zone: parse_zone(params["zone"]),
      pay_rate_cents: parse_int(params["pay_rate_cents"]) || 2500,
      active: true
    }

    case Technician |> Ash.Changeset.for_create(:create, attrs) |> Ash.create() do
      {:ok, _} ->
        {:noreply,
         socket |> assign(technicians: load_technicians()) |> put_flash(:info, "Technician added.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not add technician.")}
    end
  end

  def handle_event("toggle_active", %{"id" => id}, socket) do
    case Ash.get(Technician, id) do
      {:ok, tech} ->
        tech
        |> Ash.Changeset.for_update(:update, %{active: !tech.active})
        |> Ash.update!()

        {:noreply, assign(socket, technicians: load_technicians())}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-5xl mx-auto py-8 px-4">
      <div class="flex justify-between items-start mb-6">
        <div>
          <h1 class="text-3xl font-bold mb-2">Technicians</h1>
          <p class="text-base-content/60">
            Manage your wash technicians, zones, pay rates, and van assignments.
          </p>
        </div>
      </div>

      <!-- Add technician -->
      <div class="card bg-base-100 shadow mb-6">
        <div class="card-body p-4">
          <h3 class="font-bold mb-3">Add Technician</h3>
          <form phx-submit="add_technician" class="grid grid-cols-1 md:grid-cols-5 gap-3 items-end">
            <div class="form-control">
              <label class="label label-text text-xs">Name</label>
              <input type="text" name="tech[name]" class="input input-bordered input-sm" required />
            </div>
            <div class="form-control">
              <label class="label label-text text-xs">Phone</label>
              <input type="text" name="tech[phone]" class="input input-bordered input-sm" placeholder="512-555-0000" />
            </div>
            <div class="form-control">
              <label class="label label-text text-xs">Zone</label>
              <select name="tech[zone]" class="select select-bordered select-sm">
                <option value="">Any (floater)</option>
                <option value="nw">NW</option>
                <option value="ne">NE</option>
                <option value="sw">SW</option>
                <option value="se">SE</option>
              </select>
            </div>
            <div class="form-control">
              <label class="label label-text text-xs">Pay Rate (cents/wash)</label>
              <input type="number" name="tech[pay_rate_cents]" class="input input-bordered input-sm" value="2500" min="0" />
            </div>
            <button type="submit" class="btn btn-primary btn-sm">Add</button>
          </form>
        </div>
      </div>

      <!-- List -->
      <div :if={@technicians == []} class="text-center py-12 text-base-content/50">
        No technicians yet. Add one above.
      </div>

      <div class="space-y-3">
        <div
          :for={tech <- @technicians}
          class={["card bg-base-100 shadow-sm", !tech.active && "opacity-50"]}
        >
          <div class="card-body p-4 flex-row items-center justify-between">
            <div>
              <div class="flex items-center gap-2 flex-wrap">
                <h4 class="font-bold">{tech.name}</h4>
                <span :if={tech.zone} class={["badge badge-sm", Zones.badge_class(tech.zone)]}>
                  {Zones.short_label(tech.zone)}
                </span>
                <span :if={!tech.active} class="badge badge-sm badge-error">Inactive</span>
              </div>
              <p class="text-sm text-base-content/60 mt-1">
                {tech.phone || "No phone"} · ${div(tech.pay_rate_cents || 0, 100)}/wash
                <span :if={tech.van_id}>· van assigned</span>
              </p>
            </div>
            <div class="flex gap-2">
              <.link
                navigate={~p"/admin/technicians/#{tech.id}"}
                class="btn btn-primary btn-sm"
              >
                Open Profile
              </.link>
              <button
                class={["btn btn-xs", if(tech.active, do: "btn-warning", else: "btn-success")]}
                phx-click="toggle_active"
                phx-value-id={tech.id}
              >
                {if tech.active, do: "Deactivate", else: "Activate"}
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # --- helpers ---

  defp load_technicians do
    Technician
    |> Ash.Query.sort([{:active, :desc}, :name])
    |> Ash.read!()
  end

  defp load_vans do
    Van |> Ash.Query.filter(active == true) |> Ash.read!()
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(s), do: s

  defp parse_zone(""), do: nil
  defp parse_zone(nil), do: nil

  defp parse_zone(z) when is_binary(z) do
    case z do
      "nw" -> :nw
      "ne" -> :ne
      "sw" -> :sw
      "se" -> :se
      _ -> nil
    end
  end

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil
  defp parse_int(n) when is_integer(n), do: n

  defp parse_int(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, _} -> n
      _ -> nil
    end
  end
end
