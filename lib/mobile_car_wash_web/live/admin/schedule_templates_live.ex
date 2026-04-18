defmodule MobileCarWashWeb.Admin.ScheduleTemplatesLive do
  @moduledoc """
  Admin page for managing BlockTemplate rows — the weekly schedule that
  drives daily block generation. Each row is "for service X on day Y, start
  a block at hour H."
  """
  use MobileCarWashWeb, :live_view

  alias MobileCarWash.Scheduling.{BlockTemplate, ServiceType}

  require Ash.Query

  @days_of_week [
    {1, "Monday"},
    {2, "Tuesday"},
    {3, "Wednesday"},
    {4, "Thursday"},
    {5, "Friday"},
    {6, "Saturday"},
    {7, "Sunday"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Schedule Templates",
       services: load_services(),
       templates: load_templates(),
       days_of_week: @days_of_week
     )}
  end

  @impl true
  def handle_event("add_template", %{"template" => params}, socket) do
    attrs = %{
      service_type_id: params["service_type_id"],
      day_of_week: to_int(params["day_of_week"]),
      start_hour: to_int(params["start_hour"]),
      active: true
    }

    case BlockTemplate |> Ash.Changeset.for_create(:create, attrs) |> Ash.create() do
      {:ok, _} ->
        {:noreply,
         socket |> assign(templates: load_templates()) |> put_flash(:info, "Template added.")}

      {:error, _} ->
        {:noreply,
         put_flash(socket, :error, "Could not add template — may already exist for that slot.")}
    end
  end

  def handle_event("toggle_template", %{"id" => id}, socket) do
    case Ash.get(BlockTemplate, id) do
      {:ok, template} ->
        template
        |> Ash.Changeset.for_update(:update, %{active: !template.active})
        |> Ash.update!()

        {:noreply, assign(socket, templates: load_templates())}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("delete_template", %{"id" => id}, socket) do
    case Ash.get(BlockTemplate, id) do
      {:ok, template} ->
        Ash.destroy!(template)

        {:noreply,
         socket |> assign(templates: load_templates()) |> put_flash(:info, "Template removed.")}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-5xl mx-auto py-8 px-4">
      <h1 class="text-3xl font-bold mb-2">Schedule Templates</h1>
      <p class="text-base-content/60 mb-6">
        Each row defines a recurring block slot. When the daily generator runs, it creates an AppointmentBlock for every active row whose day-of-week matches the target date.
      </p>

      <!-- Add form -->
      <div class="card bg-base-100 shadow mb-6">
        <div class="card-body p-4">
          <h3 class="font-bold mb-3">Add Template</h3>
          <form phx-submit="add_template" class="grid grid-cols-1 md:grid-cols-4 gap-3 items-end">
            <div class="form-control">
              <label class="label label-text text-xs">Service</label>
              <select name="template[service_type_id]" class="select select-bordered select-sm" required>
                <option :for={svc <- @services} value={svc.id}>{svc.name}</option>
              </select>
            </div>
            <div class="form-control">
              <label class="label label-text text-xs">Day of Week</label>
              <select name="template[day_of_week]" class="select select-bordered select-sm" required>
                <option :for={{num, label} <- @days_of_week} value={num}>{label}</option>
              </select>
            </div>
            <div class="form-control">
              <label class="label label-text text-xs">Start Hour (0–23)</label>
              <input
                type="number"
                name="template[start_hour]"
                class="input input-bordered input-sm"
                min="0"
                max="23"
                required
                placeholder="8"
              />
            </div>
            <button type="submit" class="btn btn-primary btn-sm">Add</button>
          </form>
        </div>
      </div>

      <!-- Templates list -->
      <div :if={@templates == []} class="text-center py-12 text-base-content/50">
        No templates yet. The generator will fall back to default 8am + 1pm slots until you add some.
      </div>

      <div class="space-y-2">
        <div
          :for={t <- @templates}
          class={["card bg-base-100 shadow-sm", !t.active && "opacity-50"]}
        >
          <div class="card-body p-3 flex-row items-center justify-between">
            <div class="flex items-center gap-3">
              <span class="font-bold">{service_name(@services, t.service_type_id)}</span>
              <span class="badge badge-ghost badge-sm">{day_label(t.day_of_week)}</span>
              <span class="text-sm">{format_hour(t.start_hour)}</span>
              <span :if={!t.active} class="badge badge-sm badge-error">Inactive</span>
            </div>
            <div class="flex gap-2">
              <button
                class={["btn btn-xs", if(t.active, do: "btn-warning", else: "btn-success")]}
                phx-click="toggle_template"
                phx-value-id={t.id}
              >
                {if t.active, do: "Deactivate", else: "Activate"}
              </button>
              <button
                class="btn btn-error btn-outline btn-xs"
                phx-click="delete_template"
                phx-value-id={t.id}
                data-confirm="Delete this template? Future generation runs will no longer create blocks for this slot."
              >
                Delete
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # --- helpers ---

  defp day_label(dow) do
    {_, label} = Enum.find(@days_of_week, fn {n, _} -> n == dow end)
    label
  end

  defp service_name(services, id) do
    case Enum.find(services, &(&1.id == id)) do
      nil -> "—"
      svc -> svc.name
    end
  end

  defp format_hour(h) when h < 12, do: "#{if h == 0, do: 12, else: h}:00 AM"
  defp format_hour(12), do: "12:00 PM"
  defp format_hour(h), do: "#{h - 12}:00 PM"

  defp load_services do
    ServiceType
    |> Ash.Query.filter(active == true)
    |> Ash.Query.sort(name: :asc)
    |> Ash.read!()
  end

  defp load_templates do
    BlockTemplate
    |> Ash.Query.sort([:day_of_week, :start_hour])
    |> Ash.read!()
  end

  defp to_int(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, _} -> n
      _ -> 0
    end
  end

  defp to_int(_), do: 0
end
