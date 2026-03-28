defmodule MobileCarWashWeb.Admin.DispatchLive do
  @moduledoc """
  Admin dispatch dashboard — the daily operations command center.
  Assign technicians, view schedules, monitor active washes in real-time.
  """
  use MobileCarWashWeb, :live_view

  import MobileCarWashWeb.Admin.DispatchComponents

  alias MobileCarWash.Scheduling.{Dispatch, AppointmentTracker}
  alias MobileCarWash.Operations.Technician
  alias MobileCarWash.Scheduling.ServiceType
  alias MobileCarWash.Accounts.Customer

  require Ash.Query

  @refresh_interval :timer.seconds(30)

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: schedule_refresh()

    technicians = Ash.read!(Technician) |> Enum.filter(& &1.active)
    date = Date.utc_today()

    socket =
      socket
      |> assign(
        page_title: "Dispatch Center",
        technicians: technicians,
        selected_date: date,
        service_map: load_service_map(),
        customer_map: %{}
      )
      |> load_appointments()

    {:ok, socket}
  end

  @impl true
  def handle_event("assign_tech", %{"appointment-id" => appt_id, "technician_id" => ""}, socket) do
    Dispatch.unassign_technician(appt_id)
    {:noreply, load_appointments(socket)}
  end

  def handle_event("assign_tech", %{"appointment-id" => appt_id, "technician_id" => tech_id}, socket) do
    Dispatch.assign_technician(appt_id, tech_id)
    {:noreply, load_appointments(socket)}
  end

  def handle_event("change_date", %{"date" => date_str}, socket) do
    case Date.from_iso8601(date_str) do
      {:ok, date} ->
        {:noreply, socket |> assign(selected_date: date) |> load_appointments()}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info(:refresh, socket) do
    schedule_refresh()
    {:noreply, load_appointments(socket)}
  end

  def handle_info({:appointment_update, data}, socket) do
    # Real-time update from a technician — refresh the active wash progress
    {:noreply, load_appointments(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto py-8 px-4">
      <!-- Header -->
      <div class="flex justify-between items-center mb-8">
        <div>
          <h1 class="text-3xl font-bold">Dispatch Center</h1>
          <p class="text-base-content/60">{Calendar.strftime(@selected_date, "%A, %B %d, %Y")}</p>
        </div>
        <div class="flex items-center gap-4">
          <form phx-change="change_date">
            <input
              type="date"
              class="input input-bordered input-sm"
              value={Date.to_string(@selected_date)}
              name="date"
            />
          </form>
          <.link navigate={~p"/admin/metrics"} class="btn btn-outline btn-sm">Dashboard</.link>
        </div>
      </div>

      <!-- Unassigned Appointments -->
      <div :if={@unassigned != []} class="mb-8">
        <h2 class="text-lg font-bold mb-4 flex items-center gap-2">
          <span class="badge badge-error">{length(@unassigned)}</span>
          Unassigned
        </h2>
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          <.appointment_card
            :for={appt <- @unassigned}
            appointment={appt}
            customer_name={Map.get(@customer_map, appt.customer_id, "Customer")}
            service_name={Map.get(@service_map, appt.service_type_id, "Service")}
            technicians={@technicians}
          />
        </div>
      </div>

      <!-- Active Washes -->
      <div :if={@active != []} class="mb-8">
        <h2 class="text-lg font-bold mb-4 flex items-center gap-2">
          <span class="badge badge-success">{length(@active)}</span>
          Active Washes
        </h2>
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
          <.active_wash_card
            :for={{appt, progress} <- @active}
            appointment={appt}
            customer_name={Map.get(@customer_map, appt.customer_id, "Customer")}
            service_name={Map.get(@service_map, appt.service_type_id, "Service")}
            tech_name={tech_name(appt.technician_id, @technicians)}
            progress={progress}
          />
        </div>
      </div>

      <!-- Today's Schedule by Technician -->
      <div class="mb-8">
        <h2 class="text-lg font-bold mb-4">Schedule</h2>

        <div :if={@technicians == []} class="text-base-content/50">
          No technicians. Add one via the seed data.
        </div>

        <.technician_schedule
          :for={tech <- @technicians}
          tech_name={tech.name}
          appointments={tech_appointments(tech.id, @all_appointments)}
          service_map={@service_map}
          customer_map={@customer_map}
        />

        <!-- Unassigned in schedule view -->
        <div :if={@unassigned != []}>
          <.technician_schedule
            tech_name="Unassigned"
            appointments={@unassigned}
            service_map={@service_map}
            customer_map={@customer_map}
          />
        </div>
      </div>

      <!-- Empty state -->
      <div :if={@all_appointments == []} class="text-center py-12">
        <p class="text-base-content/50 text-lg">No appointments for {Calendar.strftime(@selected_date, "%B %d")}</p>
      </div>
    </div>
    """
  end

  # --- Private ---

  defp load_appointments(socket) do
    date = socket.assigns.selected_date
    all = Dispatch.appointments_for_date(date)

    # Load customer names
    customer_ids = Enum.map(all, & &1.customer_id) |> Enum.uniq()
    customer_map =
      if customer_ids != [] do
        Customer
        |> Ash.Query.filter(id in ^customer_ids)
        |> Ash.read!()
        |> Map.new(&{&1.id, &1.name})
      else
        %{}
      end

    unassigned = Enum.filter(all, &is_nil(&1.technician_id))
    active_appts = Enum.filter(all, &(&1.status == :in_progress))

    # Load checklist progress for active washes
    active =
      Enum.map(active_appts, fn appt ->
        progress = Dispatch.checklist_progress(appt.id)
        {appt, progress}
      end)

    # Subscribe to all active appointment PubSub topics
    if connected?(socket) do
      for appt <- active_appts do
        AppointmentTracker.subscribe(appt.id)
      end
    end

    assign(socket,
      all_appointments: all,
      unassigned: unassigned,
      active: active,
      customer_map: customer_map
    )
  end

  defp load_service_map do
    Ash.read!(ServiceType) |> Map.new(&{&1.id, &1.name})
  end

  defp tech_name(nil, _techs), do: "Unassigned"
  defp tech_name(tech_id, techs) do
    case Enum.find(techs, &(&1.id == tech_id)) do
      nil -> "Unknown"
      tech -> tech.name
    end
  end

  defp tech_appointments(tech_id, all) do
    Enum.filter(all, &(&1.technician_id == tech_id))
  end

  defp schedule_refresh do
    Process.send_after(self(), :refresh, @refresh_interval)
  end
end
