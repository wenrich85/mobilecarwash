defmodule MobileCarWashWeb.Admin.BlocksLive do
  @moduledoc """
  Admin week-calendar of appointment blocks. Click a day to add a block;
  click an empty block to delete it. Blocks holding appointments are locked.
  """
  use MobileCarWashWeb, :live_view

  alias MobileCarWash.Scheduling.{AppointmentBlock, Blocks, BlockGenerator, BlockOptimizer}
  alias MobileCarWash.Scheduling.ServiceType
  alias MobileCarWash.Operations.Technician

  require Ash.Query

  @generate_days 14

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Appointment Blocks",
       week_start: monday_of(Date.utc_today()),
       adding_day: nil,
       technicians: active_technicians(),
       service_types: service_types(),
       generate_days: @generate_days
     )
     |> load_week()}
  end

  # === week navigation ===

  @impl true
  def handle_event("prev_week", _params, socket) do
    {:noreply,
     socket
     |> assign(week_start: Date.add(socket.assigns.week_start, -7), adding_day: nil)
     |> load_week()}
  end

  def handle_event("next_week", _params, socket) do
    {:noreply,
     socket
     |> assign(week_start: Date.add(socket.assigns.week_start, 7), adding_day: nil)
     |> load_week()}
  end

  def handle_event("this_week", _params, socket) do
    {:noreply,
     socket |> assign(week_start: monday_of(Date.utc_today()), adding_day: nil) |> load_week()}
  end

  # === add block ===

  def handle_event("open_add", %{"day" => day}, socket) do
    {:noreply, assign(socket, adding_day: day)}
  end

  def handle_event("cancel_add", _params, socket) do
    {:noreply, assign(socket, adding_day: nil)}
  end

  def handle_event("create_block", params, socket) do
    with {:ok, starts_at} <- parse_datetime_local(params["starts_at"]),
         {:ok, ends_at} <- parse_datetime_local(params["ends_at"]) do
      attrs = %{
        service_type_id: params["service_type_id"],
        technician_id: params["technician_id"],
        starts_at: starts_at,
        ends_at: ends_at,
        closes_at: DateTime.add(starts_at, -3600, :second),
        capacity: String.to_integer(params["capacity"] || "3"),
        status: :open
      }

      case Blocks.create_block(attrs) do
        {:ok, _block} ->
          {:noreply,
           socket
           |> assign(adding_day: nil)
           |> load_week()
           |> put_flash(:info, "Block added.")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not add block — check the fields.")}
      end
    else
      _ -> {:noreply, put_flash(socket, :error, "Invalid start/end time.")}
    end
  end

  # === delete block (guarded) ===

  def handle_event("delete_block", %{"id" => id}, socket) do
    case Blocks.delete_block(id) do
      :ok ->
        {:noreply, socket |> load_week() |> put_flash(:info, "Block deleted.")}

      {:error, :block_has_appointments} ->
        {:noreply,
         put_flash(socket, :error, "Move or cancel its appointments before deleting this block.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not delete block.")}
    end
  end

  # === existing block ops (kept) ===

  def handle_event("optimize_now", %{"id" => id}, socket) do
    case BlockOptimizer.close_and_optimize(id) do
      {:ok, _} ->
        {:noreply,
         socket |> load_week() |> put_flash(:info, "Block optimized — customers notified.")}

      {:error, :already_optimized} ->
        {:noreply, put_flash(socket, :error, "Block has already been optimized.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Optimize failed: #{inspect(reason)}")}
    end
  end

  def handle_event("generate_blocks", params, socket) do
    tech_id = params["technician_id"] || fallback_tech_id(socket)

    if tech_id in [nil, ""] do
      {:noreply,
       put_flash(
         socket,
         :error,
         "No active technician found — create one before generating blocks."
       )}
    else
      :ok = BlockGenerator.generate_ahead(@generate_days, technician_id: tech_id)

      {:noreply,
       socket
       |> load_week()
       |> put_flash(:info, "Generated blocks for the next #{@generate_days} days.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto py-8 px-4">
      <div class="flex justify-between items-center mb-6 flex-wrap gap-2">
        <h1 class="text-3xl font-bold">Appointment Blocks</h1>
        <div class="flex items-center gap-2">
          <.link navigate={~p"/admin/appointments/new"} class="btn btn-secondary btn-sm">
            + New Appointment
          </.link>
          <form phx-submit="generate_blocks" class="flex items-end gap-2">
            <select
              :if={@technicians != []}
              name="technician_id"
              class="select select-bordered select-sm"
            >
              <option :for={tech <- @technicians} value={tech.id}>{tech.name}</option>
            </select>
            <button
              type="submit"
              class="btn btn-primary btn-sm"
              data-confirm="Generate blocks for the next 14 days?"
            >
              Generate {@generate_days} Days
            </button>
          </form>
        </div>
      </div>

      <div class="flex items-center justify-between mb-4">
        <button class="btn btn-ghost btn-sm" phx-click="prev_week">← Prev</button>
        <div class="font-semibold">
          Week of {Calendar.strftime(@week_start, "%b %-d, %Y")}
        </div>
        <div class="flex gap-2">
          <button class="btn btn-ghost btn-sm" phx-click="this_week">Today</button>
          <button class="btn btn-ghost btn-sm" phx-click="next_week">Next →</button>
        </div>
      </div>

      <div id="blocks-calendar" class="grid grid-cols-1 md:grid-cols-7 gap-2">
        <div
          :for={day <- week_days(@week_start)}
          class="border border-base-200 rounded-lg p-2 min-h-40"
        >
          <div class="text-xs font-semibold text-base-content/70 mb-2">
            {Calendar.strftime(day, "%a %-m/%-d")}
          </div>

          <div
            :for={block <- blocks_on(@blocks, day)}
            id={"block-#{block.id}"}
            class="card bg-base-100 shadow-sm mb-2"
          >
            <div class="card-body p-2 text-xs">
              <div class="font-bold">{block.service_type.name}</div>
              <div>
                {Calendar.strftime(block.starts_at, "%-I:%M")}–{Calendar.strftime(
                  block.ends_at,
                  "%-I:%M %p"
                )}
              </div>
              <div class="text-base-content/70">
                {block.appointment_count} / {block.capacity} booked
              </div>
              <button
                :if={block.appointment_count in [0, nil] and block.status == :open}
                class="btn btn-error btn-outline btn-xs mt-1"
                phx-click="delete_block"
                phx-value-id={block.id}
                data-confirm="Delete this empty block?"
              >
                Delete
              </button>
              <span
                :if={block.appointment_count not in [0, nil] or block.status != :open}
                class="block-locked text-base-content/50 mt-1"
              >
                Locked
              </span>
              <button
                :if={block.status == :open and block.appointment_count not in [0, nil]}
                class="btn btn-primary btn-xs mt-1"
                phx-click="optimize_now"
                phx-value-id={block.id}
                data-confirm="Close this block now and assign arrival times?"
              >
                Optimize
              </button>
            </div>
          </div>

          <button
            class="btn btn-ghost btn-xs w-full"
            phx-click="open_add"
            phx-value-day={Date.to_iso8601(day)}
          >
            + Add
          </button>

          <form
            :if={@adding_day == Date.to_iso8601(day)}
            id="block-add-form"
            phx-submit="create_block"
            class="mt-2 space-y-1 text-xs"
          >
            <input
              type="datetime-local"
              name="starts_at"
              required
              class="input input-bordered input-xs w-full"
              value={"#{Date.to_iso8601(day)}T09:00"}
            />
            <input
              type="datetime-local"
              name="ends_at"
              required
              class="input input-bordered input-xs w-full"
              value={"#{Date.to_iso8601(day)}T12:00"}
            />
            <select name="service_type_id" required class="select select-bordered select-xs w-full">
              <option :for={st <- @service_types} value={st.id}>{st.name}</option>
            </select>
            <select name="technician_id" required class="select select-bordered select-xs w-full">
              <option :for={tech <- @technicians} value={tech.id}>{tech.name}</option>
            </select>
            <input
              type="number"
              name="capacity"
              value="3"
              min="1"
              class="input input-bordered input-xs w-full"
            />
            <div class="flex gap-1">
              <button type="submit" class="btn btn-primary btn-xs flex-1">Save</button>
              <button type="button" class="btn btn-ghost btn-xs" phx-click="cancel_add">
                Cancel
              </button>
            </div>
          </form>
        </div>
      </div>
    </div>
    """
  end

  # === helpers ===

  defp monday_of(date) do
    Date.add(date, -(Date.day_of_week(date) - 1))
  end

  defp week_days(week_start), do: Enum.map(0..6, &Date.add(week_start, &1))

  defp blocks_on(blocks, day) do
    blocks
    |> Enum.filter(fn b -> DateTime.to_date(b.starts_at) == day end)
    |> Enum.sort_by(& &1.starts_at, DateTime)
  end

  defp load_week(socket) do
    week_start = socket.assigns.week_start
    {:ok, from} = DateTime.new(week_start, ~T[00:00:00])
    {:ok, to} = DateTime.new(Date.add(week_start, 7), ~T[00:00:00])

    blocks =
      AppointmentBlock
      |> Ash.Query.filter(starts_at >= ^from and starts_at < ^to and status != :cancelled)
      |> Ash.Query.sort(starts_at: :asc)
      |> Ash.Query.load([:service_type, :technician, :appointment_count])
      |> Ash.read!(authorize?: false)

    assign(socket, blocks: blocks)
  end

  defp service_types do
    ServiceType |> Ash.read!(authorize?: false)
  end

  defp active_technicians do
    Technician
    |> Ash.Query.filter(active == true)
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.read!(authorize?: false)
  end

  defp fallback_tech_id(socket) do
    case socket.assigns.technicians do
      [first | _] -> first.id
      _ -> nil
    end
  end

  defp parse_datetime_local(value) when is_binary(value) and value != "" do
    case NaiveDateTime.from_iso8601(value <> ":00") do
      {:ok, ndt} -> {:ok, DateTime.from_naive!(ndt, "Etc/UTC")}
      error -> error
    end
  end

  defp parse_datetime_local(_), do: {:error, :invalid}
end
