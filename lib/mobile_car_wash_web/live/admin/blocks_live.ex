defmodule MobileCarWashWeb.Admin.BlocksLive do
  @moduledoc """
  Admin view of upcoming appointment blocks. Shows time window, capacity,
  status, and assigned technician. Supports triggering the route optimizer
  manually and cancelling a block.
  """
  use MobileCarWashWeb, :live_view

  alias MobileCarWash.Scheduling.{AppointmentBlock, BlockGenerator, BlockOptimizer}
  alias MobileCarWash.Operations.Technician

  require Ash.Query

  @generate_days 14

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Appointment Blocks",
       blocks: load_blocks(),
       expanded: MapSet.new(),
       editing_closes_at: nil,
       technicians: active_technicians(),
       generate_days: @generate_days
     )}
  end

  @impl true
  def handle_event("optimize_now", %{"id" => id}, socket) do
    case BlockOptimizer.close_and_optimize(id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(blocks: load_blocks())
         |> put_flash(:info, "Block optimized — customers notified.")}

      {:error, :already_optimized} ->
        {:noreply, put_flash(socket, :error, "Block has already been optimized.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Optimize failed: #{inspect(reason)}")}
    end
  end

  def handle_event("cancel_block", %{"id" => id}, socket) do
    case Ash.get(AppointmentBlock, id) do
      {:ok, block} ->
        case block
             |> Ash.Changeset.for_update(:update, %{status: :cancelled})
             |> Ash.update() do
          {:ok, _} ->
            {:noreply,
             socket
             |> assign(blocks: load_blocks())
             |> put_flash(:info, "Block cancelled.")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Could not cancel block.")}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("generate_blocks", params, socket) do
    tech_id = params["technician_id"] || fallback_tech_id(socket)

    cond do
      tech_id in [nil, ""] ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "No active technician found — seed or create one before generating blocks."
         )}

      true ->
        :ok = BlockGenerator.generate_ahead(@generate_days, technician_id: tech_id)

        tech_name =
          Enum.find_value(socket.assigns.technicians, "selected tech", fn t ->
            t.id == tech_id and t.name
          end)

        {:noreply,
         socket
         |> assign(blocks: load_blocks())
         |> put_flash(
           :info,
           "Generated blocks for the next #{@generate_days} days under #{tech_name}."
         )}
    end
  end

  def handle_event("edit_closes_at", %{"id" => id}, socket) do
    {:noreply, assign(socket, editing_closes_at: id)}
  end

  def handle_event("cancel_closes_at_edit", _params, socket) do
    {:noreply, assign(socket, editing_closes_at: nil)}
  end

  def handle_event("save_closes_at", %{"id" => id, "closes_at" => value}, socket) do
    with {:ok, closes_at} <- parse_datetime_local(value),
         {:ok, block} <- Ash.get(AppointmentBlock, id),
         {:ok, _} <-
           block
           |> Ash.Changeset.for_update(:update, %{closes_at: closes_at})
           |> Ash.update() do
      {:noreply,
       socket
       |> assign(blocks: load_blocks(), editing_closes_at: nil)
       |> put_flash(:info, "Closing time updated.")}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not update closing time.")}
    end
  end

  def handle_event("toggle_expand", %{"id" => id}, socket) do
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
    <div class="max-w-6xl mx-auto py-8 px-4">
      <div class="flex justify-between items-start mb-6">
        <div>
          <h1 class="text-3xl font-bold mb-2">Appointment Blocks</h1>
          <p class="text-base-content/80">
            Upcoming windows. Blocks close automatically at midnight the day before; the route optimizer assigns each customer an exact arrival time and texts it to them.
          </p>
        </div>
        <form phx-submit="generate_blocks" class="flex items-end gap-2">
          <div :if={@technicians != []} class="form-control">
            <label class="label label-text text-xs">Technician</label>
            <select name="technician_id" class="select select-bordered select-sm">
              <option :for={tech <- @technicians} value={tech.id}>{tech.name}</option>
            </select>
          </div>
          <button
            type="submit"
            class="btn btn-primary btn-sm"
            data-confirm="Generate blocks for the next 14 days? Existing blocks will not be duplicated."
          >
            Generate Next {@generate_days} Days
          </button>
        </form>
      </div>

      <div :if={@blocks == []} class="text-center py-12 text-base-content/70">
        No upcoming blocks. Click "Generate Next {@generate_days} Days" to seed the schedule.
      </div>

      <div class="space-y-3">
        <div
          :for={block <- @blocks}
          class="card bg-base-100 shadow-sm"
        >
          <div class="card-body p-4">
            <div class="flex justify-between items-start">
              <div class="flex-1">
                <div class="flex items-center gap-2 flex-wrap">
                  <h4 class="font-bold">{block.service_type.name}</h4>
                  <span class={["badge badge-sm", status_class(block.status)]}>
                    {block.status}
                  </span>
                  <span class="text-xs text-base-content/70">
                    Tech: {(block.technician && block.technician.name) || "—"}
                  </span>
                </div>

                <p class="text-sm mt-1">
                  <span class="font-semibold">
                    {Calendar.strftime(block.starts_at, "%a %b %-d · %-I:%M %p")} – {Calendar.strftime(
                      block.ends_at,
                      "%-I:%M %p"
                    )}
                  </span>
                </p>

                <p :if={@editing_closes_at != block.id} class="text-sm text-base-content/80 mt-1">
                  {block.appointment_count} / {block.capacity} booked · closes {Calendar.strftime(
                    block.closes_at,
                    "%a %b %-d %-I:%M %p"
                  )}
                  <button
                    :if={block.status == :open}
                    class="btn btn-ghost btn-xs ml-1"
                    phx-click="edit_closes_at"
                    phx-value-id={block.id}
                  >
                    Edit
                  </button>
                </p>

                <form
                  :if={@editing_closes_at == block.id}
                  phx-submit="save_closes_at"
                  phx-value-id={block.id}
                  class="flex items-center gap-2 mt-1 text-sm"
                >
                  <label class="text-base-content/80">Closes at:</label>
                  <input
                    type="datetime-local"
                    name="closes_at"
                    class="input input-bordered input-xs"
                    value={format_datetime_local(block.closes_at)}
                    required
                  />
                  <button type="submit" class="btn btn-primary btn-xs">Save</button>
                  <button type="button" class="btn btn-ghost btn-xs" phx-click="cancel_closes_at_edit">
                    Cancel
                  </button>
                </form>
              </div>

              <div class="flex gap-2 flex-wrap justify-end">
                <button
                  class="btn btn-ghost btn-xs"
                  phx-click="toggle_expand"
                  phx-value-id={block.id}
                >
                  {if MapSet.member?(@expanded, block.id), do: "Hide", else: "View"} appointments
                </button>
                <button
                  :if={block.status == :open and block.appointment_count > 0}
                  class="btn btn-primary btn-xs"
                  phx-click="optimize_now"
                  phx-value-id={block.id}
                >
                  Optimize Now
                </button>
                <button
                  :if={block.status in [:open, :scheduled]}
                  class="btn btn-error btn-outline btn-xs"
                  phx-click="cancel_block"
                  phx-value-id={block.id}
                  data-confirm="Cancel this block? Booked customers will need to be rebooked manually."
                >
                  Cancel
                </button>
              </div>
            </div>

            <div
              :if={MapSet.member?(@expanded, block.id)}
              class="mt-3 pt-3 border-t border-base-200"
            >
              <div :if={block.appointments == []} class="text-sm text-base-content/70">
                No appointments in this block yet.
              </div>

              <table :if={block.appointments != []} class="table table-sm">
                <thead>
                  <tr>
                    <th>#</th>
                    <th>Time</th>
                    <th>Customer</th>
                    <th>Address</th>
                    <th>Status</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={appt <- sorted_appointments(block.appointments)}>
                    <td>{appt.route_position || "—"}</td>
                    <td>{Calendar.strftime(appt.scheduled_at, "%-I:%M %p")}</td>
                    <td>{(appt.customer && appt.customer.name) || "—"}</td>
                    <td class="text-xs">
                      {(appt.address && "#{appt.address.street}, #{appt.address.city}") || "—"}
                    </td>
                    <td><span class="badge badge-sm badge-ghost">{appt.status}</span></td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # --- helpers ---

  defp status_class(:open), do: "badge-success"
  defp status_class(:scheduled), do: "badge-info"
  defp status_class(:in_progress), do: "badge-warning"
  defp status_class(:completed), do: "badge-ghost"
  defp status_class(:cancelled), do: "badge-error"
  defp status_class(_), do: "badge-ghost"

  defp sorted_appointments(appointments) do
    Enum.sort_by(appointments, fn a -> a.route_position || 999 end)
  end

  defp format_datetime_local(%DateTime{} = dt) do
    # HTML5 datetime-local wants "YYYY-MM-DDTHH:MM" without timezone.
    Calendar.strftime(dt, "%Y-%m-%dT%H:%M")
  end

  defp parse_datetime_local(value) when is_binary(value) do
    case NaiveDateTime.from_iso8601(value <> ":00") do
      {:ok, ndt} -> {:ok, DateTime.from_naive!(ndt, "Etc/UTC")}
      error -> error
    end
  end

  defp active_technicians do
    Technician
    |> Ash.Query.filter(active == true)
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.read!()
  end

  defp fallback_tech_id(socket) do
    case socket.assigns.technicians do
      [first | _] -> first.id
      _ -> nil
    end
  end

  defp load_blocks do
    today = Date.utc_today() |> DateTime.new!(~T[00:00:00])

    AppointmentBlock
    |> Ash.Query.filter(starts_at >= ^today)
    |> Ash.Query.sort(starts_at: :asc)
    |> Ash.Query.load([
      :service_type,
      :technician,
      :appointment_count,
      appointments: [:customer, :address]
    ])
    |> Ash.read!()
  end
end
