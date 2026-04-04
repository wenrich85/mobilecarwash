defmodule MobileCarWashWeb.Admin.DispatchLive do
  @moduledoc """
  Admin dispatch dashboard — the daily operations command center.
  Shows all appointments with filters for date, status, and technician.
  """
  use MobileCarWashWeb, :live_view

  import MobileCarWashWeb.Admin.DispatchComponents

  alias MobileCarWash.Scheduling.{Dispatch, AppointmentTracker, Appointment}
  alias MobileCarWash.Operations.Technician
  alias MobileCarWash.Scheduling.ServiceType
  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Fleet.Address
  alias MobileCarWash.Zones

  require Ash.Query

  @refresh_interval :timer.seconds(30)

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      schedule_refresh()
      AppointmentTracker.subscribe_to_new_appointments()
      AppointmentTracker.subscribe_to_tech_requests()
    end

    technicians = Ash.read!(Technician) |> Enum.filter(& &1.active)

    tech_users =
      Customer
      |> Ash.Query.filter(role in [:technician, :admin])
      |> Ash.read!(authorize?: false)

    socket =
      socket
      |> assign(
        page_title: "Dispatch Center",
        technicians: technicians,
        tech_users: tech_users,
        # Filters — default: no date filter, pending status, all techs
        filter_date: nil,
        filter_status: "pending",
        filter_tech: nil,
        filter_zone: nil,
        filter_requested: false,
        show_manage_techs: false,
        service_map: load_service_map(),
        customer_map: %{},
        address_map: %{},
        vehicle_map: %{},
        tech_requests: %{},
        subscribed_appointment_ids: MapSet.new()
      )
      |> load_appointments()

    {:ok, socket}
  end

  # === Event Handlers ===

  @impl true
  def handle_event("request_map_pins", _params, socket) do
    {:noreply, push_event(socket, "update_map_pins", %{pins: socket.assigns.map_pins})}
  end

  def handle_event("filter", params, socket) do
    filter_date =
      case params["date"] do
        "" -> nil
        nil -> socket.assigns.filter_date
        d -> case Date.from_iso8601(d) do
          {:ok, date} -> date
          _ -> socket.assigns.filter_date
        end
      end

    filter_status = params["status"] || socket.assigns.filter_status
    filter_status = if filter_status == "", do: nil, else: filter_status

    filter_tech = params["tech"] || socket.assigns.filter_tech
    filter_tech = if filter_tech == "", do: nil, else: filter_tech

    filter_zone = params["zone"] || socket.assigns.filter_zone
    filter_zone = if filter_zone == "", do: nil, else: filter_zone

    filter_requested = params["requested"] == "true"

    {:noreply,
     socket
     |> assign(filter_date: filter_date, filter_status: filter_status, filter_tech: filter_tech, filter_zone: filter_zone, filter_requested: filter_requested)
     |> load_appointments()}
  end

  def handle_event("clear_filters", _params, socket) do
    {:noreply,
     socket
     |> assign(filter_date: nil, filter_status: "pending", filter_tech: nil, filter_zone: nil, filter_requested: false)
     |> load_appointments()}
  end

  def handle_event("assign_tech_zone", %{"tech-id" => tech_id, "zone" => zone_str}, socket) do
    zone = if zone_str == "", do: nil, else: zone_str

    import Ecto.Query
    MobileCarWash.Repo.update_all(
      from(t in "technicians", where: t.id == type(^Ecto.UUID.dump!(tech_id), :binary_id)),
      set: [zone: zone]
    )

    technicians = Ash.read!(Technician) |> Enum.filter(& &1.active)
    {:noreply, assign(socket, technicians: technicians)}
  end

  def handle_event("assign_tech", %{"appointment-id" => appt_id, "technician_id" => ""}, socket) do
    Dispatch.unassign_technician(appt_id)
    {:noreply, load_appointments(socket)}
  end

  def handle_event("assign_tech", %{"appointment-id" => appt_id, "technician_id" => tech_id}, socket) do
    Dispatch.assign_technician(appt_id, tech_id)
    {:noreply, load_appointments(socket)}
  end

  def handle_event("confirm_appointment", %{"id" => id}, socket) do
    case Ash.get(Appointment, id) do
      {:ok, appt} ->
        case appt |> Ash.Changeset.for_update(:confirm, %{}) |> Ash.update() do
          {:ok, confirmed} ->
            AppointmentTracker.broadcast_assignment_changed(id)
            AppointmentTracker.broadcast_assigned_to_tech(id, confirmed.technician_id)
            {:noreply, socket |> load_appointments() |> put_flash(:info, "Appointment confirmed")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Could not confirm appointment")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Appointment not found")}
    end
  end

  def handle_event("toggle_manage_techs", _params, socket) do
    {:noreply, assign(socket, show_manage_techs: !socket.assigns.show_manage_techs)}
  end

  def handle_event("link_tech_account", %{"tech-id" => tech_id, "user_id" => user_id}, socket) do
    import Ecto.Query
    uid = if user_id == "", do: nil, else: Ecto.UUID.dump!(user_id)

    MobileCarWash.Repo.update_all(
      from(t in "technicians", where: t.id == type(^tech_id, :binary_id)),
      set: [user_account_id: uid]
    )

    technicians = Ash.read!(Technician) |> Enum.filter(& &1.active)
    {:noreply, socket |> assign(technicians: technicians) |> put_flash(:info, "Account linked")}
  end

  def handle_event("update_tech_rate", %{"tech-id" => tech_id, "rate" => rate_str}, socket) do
    case Integer.parse(rate_str) do
      {rate_dollars, _} ->
        import Ecto.Query
        MobileCarWash.Repo.update_all(
          from(t in "technicians", where: t.id == type(^tech_id, :binary_id)),
          set: [pay_rate_cents: rate_dollars * 100]
        )
        technicians = Ash.read!(Technician) |> Enum.filter(& &1.active)
        {:noreply, socket |> assign(technicians: technicians) |> put_flash(:info, "Rate updated")}

      _ ->
        {:noreply, put_flash(socket, :error, "Invalid rate")}
    end
  end

  def handle_event("add_technician", %{"name" => name, "phone" => phone}, socket) do
    case Technician |> Ash.Changeset.for_create(:create, %{name: name, phone: phone}) |> Ash.create() do
      {:ok, _} ->
        technicians = Ash.read!(Technician) |> Enum.filter(& &1.active)
        {:noreply, socket |> assign(technicians: technicians) |> put_flash(:info, "Technician added")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not add technician")}
    end
  end

  @impl true
  def handle_info(:refresh, socket) do
    schedule_refresh()
    {:noreply, load_appointments(socket)}
  end

  # Step progress — update the active panel in-memory, no DB query
  def handle_info({:appointment_update, %{event: :step_update, appointment_id: id} = data}, socket) do
    active =
      Enum.map(socket.assigns.active, fn {appt, progress} ->
        if appt.id == id do
          {appt, %{progress |
            steps_done: data[:steps_done] || progress.steps_done,
            steps_total: data[:steps_total] || progress.steps_total,
            current_step: data[:current_step] || progress.current_step,
            eta_minutes: data[:eta_minutes]
          }}
        else
          {appt, progress}
        end
      end)

    {:noreply, assign(socket, active: active)}
  end

  # Status changes — targeted reload of just the affected appointment
  def handle_info({:appointment_update, %{appointment_id: id}}, socket) do
    {:noreply, reload_one_appointment(socket, id)}
  end

  def handle_info({:new_appointment, _id}, socket) do
    {:noreply, load_appointments(socket)}
  end

  def handle_info({:tech_request, request}, socket) do
    tech_name = request.technician_name

    appt_info =
      case Ash.get(Appointment, request.appointment_id) do
        {:ok, appt} ->
          service = Map.get(socket.assigns.service_map, appt.service_type_id, "Service")
          time = Calendar.strftime(appt.scheduled_at, "%b %d · %I:%M %p")
          "#{service} on #{time}"
        _ ->
          "an appointment"
      end

    # Track which appointments have been requested and by whom
    tech_requests = Map.put(socket.assigns.tech_requests, request.appointment_id, %{
      technician_id: request.technician_id,
      technician_name: tech_name
    })

    {:noreply,
     socket
     |> assign(tech_requests: tech_requests)
     |> put_flash(:info, "#{tech_name} is requesting #{appt_info}")
     |> load_appointments()}
  end

  # === Render ===

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-full mx-auto py-8 px-4 bg-base-200 min-h-screen">
      <!-- Header -->
      <div class="max-w-7xl mx-auto mb-6">
        <div class="flex justify-between items-center">
          <div>
            <h1 class="text-3xl font-bold">Dispatch Center</h1>
            <p class="text-base-content/60">Kanban-style appointment management</p>
          </div>
          <.link navigate={~p"/admin/metrics"} class="btn btn-outline btn-sm">Dashboard</.link>
        </div>
      </div>

      <!-- Filters -->
      <div class="max-w-7xl mx-auto mb-6">
        <form phx-change="filter" class="flex flex-wrap gap-2 items-end bg-base-100 p-4 rounded-lg shadow-sm">
          <div class="form-control">
            <label class="label label-text text-xs">Date</label>
            <input
              type="date"
              name="date"
              class="input input-bordered input-sm"
              value={@filter_date && Date.to_string(@filter_date)}
            />
          </div>

          <div class="form-control">
            <label class="label label-text text-xs">Technician</label>
            <select name="tech" class="select select-bordered select-sm">
              <option value="" selected={is_nil(@filter_tech)}>All Techs</option>
              <option value="unassigned" selected={@filter_tech == "unassigned"}>Unassigned</option>
              <option
                :for={tech <- @technicians}
                value={tech.id}
                selected={@filter_tech == tech.id}
              >
                {tech.name}
              </option>
            </select>
          </div>

          <div class="form-control">
            <label class="label label-text text-xs">Zone</label>
            <select name="zone" class="select select-bordered select-sm">
              <option value="" selected={is_nil(@filter_zone)}>All Zones</option>
              <option :for={z <- Zones.all()} value={z} selected={@filter_zone == to_string(z)}>
                {Zones.short_label(z)}
              </option>
            </select>
          </div>

          <div class="form-control">
            <label class="label cursor-pointer gap-2 justify-start">
              <input
                type="checkbox"
                name="requested"
                value="true"
                checked={@filter_requested}
                class="checkbox checkbox-sm checkbox-primary"
              />
              <span class="label-text text-sm">
                Requested
                <span :if={map_size(@tech_requests) > 0} class="badge badge-warning badge-xs ml-1">{map_size(@tech_requests)}</span>
              </span>
            </label>
          </div>

          <button type="button" class="btn btn-ghost btn-sm" phx-click="clear_filters">Clear</button>
        </form>
      </div>

      <!-- Map -->
      <div class="max-w-7xl mx-auto mb-8 bg-base-100 p-4 rounded-lg shadow">
        <h2 class="text-lg font-bold mb-3">Map</h2>
        <div
          id="dispatch-map"
          phx-hook="DispatchMap"
          phx-update="ignore"
          class="w-full h-80 rounded-lg border border-base-300 z-0"
        />
      </div>

      <!-- Active Washes (always show if any) -->
      <div :if={@active != []} class="max-w-7xl mx-auto mb-8">
        <h2 class="text-lg font-bold mb-4 flex items-center gap-2">
          <span class="badge badge-success badge-lg">{length(@active)}</span>
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

      <!-- Kanban Board -->
      <div class="min-h-screen">
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 max-w-7xl mx-auto pb-8">
          <!-- PENDING COLUMN -->
          <.kanban_column
            title="Pending"
            status={:pending}
            appointments={filter_appointments_by_status(@all_appointments, :pending, @filter_date, @filter_tech, @filter_zone, @address_map)}
            count={length(filter_appointments_by_status(@all_appointments, :pending, @filter_date, @filter_tech, @filter_zone, @address_map))}
            badge_color="badge-warning"
            technicians={@technicians}
            customer_map={@customer_map}
            service_map={@service_map}
            address_map={@address_map}
            vehicle_map={@vehicle_map}
            tech_requests={@tech_requests}
          />

          <!-- CONFIRMED COLUMN -->
          <.kanban_column
            title="Confirmed"
            status={:confirmed}
            appointments={filter_appointments_by_status(@all_appointments, :confirmed, @filter_date, @filter_tech, @filter_zone, @address_map)}
            count={length(filter_appointments_by_status(@all_appointments, :confirmed, @filter_date, @filter_tech, @filter_zone, @address_map))}
            badge_color="badge-info"
            technicians={@technicians}
            customer_map={@customer_map}
            service_map={@service_map}
            address_map={@address_map}
            vehicle_map={@vehicle_map}
            tech_requests={@tech_requests}
          />

          <!-- IN PROGRESS COLUMN -->
          <.kanban_column
            title="In Progress"
            status={:in_progress}
            appointments={filter_appointments_by_status(@all_appointments, :in_progress, @filter_date, @filter_tech, @filter_zone, @address_map)}
            count={length(filter_appointments_by_status(@all_appointments, :in_progress, @filter_date, @filter_tech, @filter_zone, @address_map))}
            badge_color="badge-success"
            technicians={@technicians}
            customer_map={@customer_map}
            service_map={@service_map}
            address_map={@address_map}
            vehicle_map={@vehicle_map}
            tech_requests={@tech_requests}
          />

          <!-- COMPLETED COLUMN -->
          <.kanban_column
            title="Completed"
            status={:completed}
            appointments={filter_appointments_by_status(@all_appointments, :completed, @filter_date, @filter_tech, @filter_zone, @address_map)}
            count={length(filter_appointments_by_status(@all_appointments, :completed, @filter_date, @filter_tech, @filter_zone, @address_map))}
            badge_color="badge-ghost"
            technicians={@technicians}
            customer_map={@customer_map}
            service_map={@service_map}
            address_map={@address_map}
            vehicle_map={@vehicle_map}
            tech_requests={@tech_requests}
          />
        </div>
      </div>

      <!-- Manage Technicians -->
      <div class="mb-8">
        <button class="btn btn-ghost btn-sm mb-4" phx-click="toggle_manage_techs">
          {if @show_manage_techs, do: "Hide", else: "Manage"} Technicians
        </button>

        <div :if={@show_manage_techs}>
          <div class="card bg-base-100 shadow mb-4">
            <div class="card-body p-4">
              <h3 class="font-bold mb-2">Add Technician</h3>
              <form phx-submit="add_technician" class="flex gap-2 items-end">
                <div class="form-control flex-1">
                  <label class="label label-text text-xs">Name</label>
                  <input type="text" name="name" class="input input-bordered input-sm" required placeholder="Tech name" />
                </div>
                <div class="form-control flex-1">
                  <label class="label label-text text-xs">Phone</label>
                  <input type="text" name="phone" class="input input-bordered input-sm" placeholder="555-0000" />
                </div>
                <button type="submit" class="btn btn-primary btn-sm">Add</button>
              </form>
            </div>
          </div>

          <div class="overflow-x-auto">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>Name</th>
                  <th>Zone</th>
                  <th>Linked Account</th>
                  <th>Pay Rate</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={tech <- @technicians}>
                  <td class="font-semibold">
                    <.link navigate={~p"/admin/technicians/#{tech.id}"} class="link link-hover">
                      {tech.name}
                    </.link>
                  </td>
                  <td>
                    <select
                      class="select select-bordered select-xs"
                      phx-change="assign_tech_zone"
                      phx-value-tech-id={tech.id}
                      name="zone"
                    >
                      <option value="" selected={is_nil(tech.zone)}>Floater</option>
                      <option :for={z <- Zones.all()} value={z} selected={tech.zone == z}>
                        {Zones.short_label(z)}
                      </option>
                    </select>
                  </td>
                  <td>
                    <select
                      class="select select-bordered select-xs w-full max-w-xs"
                      phx-change="link_tech_account"
                      phx-value-tech-id={tech.id}
                      name="user_id"
                    >
                      <option value="">— No account —</option>
                      <option
                        :for={u <- @tech_users}
                        value={u.id}
                        selected={tech.user_account_id == u.id}
                      >
                        {u.name} ({u.email})
                      </option>
                    </select>
                  </td>
                  <td>
                    <form phx-submit="update_tech_rate" phx-value-tech-id={tech.id} class="flex gap-1 items-center">
                      <span class="text-xs">$</span>
                      <input
                        type="number"
                        name="rate"
                        class="input input-bordered input-xs w-20"
                        value={div(tech.pay_rate_cents || 2500, 100)}
                        min="0"
                      />
                      <button type="submit" class="btn btn-ghost btn-xs">Save</button>
                    </form>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # === Private ===

  defp load_appointments(socket) do
    # Build query based on filters — always load all non-cancelled appointments
    # so each kanban column can display its own status independently.
    query =
      Appointment
      |> Ash.Query.sort(scheduled_at: :asc)
      |> Ash.Query.filter(status != :cancelled)

    # Date filter
    query =
      case socket.assigns.filter_date do
        nil -> query
        date ->
          {:ok, day_start} = DateTime.new(date, ~T[00:00:00])
          {:ok, day_end} = DateTime.new(Date.add(date, 1), ~T[00:00:00])
          Ash.Query.filter(query, scheduled_at >= ^day_start and scheduled_at < ^day_end)
      end

    # Tech filter
    query =
      case socket.assigns.filter_tech do
        nil -> query
        "unassigned" -> Ash.Query.filter(query, is_nil(technician_id))
        tech_id -> Ash.Query.filter(query, technician_id == ^tech_id)
      end

    all = Ash.read!(query)

    # Load customer names
    customer_ids = Enum.map(all, & &1.customer_id) |> Enum.uniq()
    customer_map =
      if customer_ids != [] do
        Customer |> Ash.Query.filter(id in ^customer_ids) |> Ash.read!(authorize?: false) |> Map.new(&{&1.id, &1.name})
      else
        %{}
      end

    # Load address data (for zone badges)
    address_ids = Enum.map(all, & &1.address_id) |> Enum.uniq()
    address_map =
      if address_ids != [] do
        Address |> Ash.Query.filter(id in ^address_ids) |> Ash.read!() |> Map.new(&{&1.id, &1})
      else
        %{}
      end

    # Load vehicle data (for map pin icons)
    vehicle_ids = Enum.map(all, & &1.vehicle_id) |> Enum.uniq()
    vehicle_map =
      if vehicle_ids != [] do
        MobileCarWash.Fleet.Vehicle |> Ash.Query.filter(id in ^vehicle_ids) |> Ash.read!() |> Map.new(&{&1.id, &1})
      else
        %{}
      end

    # Zone filter (applied in memory — small daily count)
    filtered =
      case socket.assigns.filter_zone do
        nil -> all
        zone_str ->
          zone = String.to_existing_atom(zone_str)
          Enum.filter(all, fn appt ->
            addr = Map.get(address_map, appt.address_id)
            addr && addr.zone == zone
          end)
      end

    # Requested filter — show only appointments a tech has requested
    filtered =
      if socket.assigns.filter_requested do
        Enum.filter(filtered, fn appt ->
          Map.has_key?(socket.assigns.tech_requests, appt.id)
        end)
      else
        filtered
      end

    # Active washes (always show regardless of filters)
    active_appts = Appointment |> Ash.Query.filter(status == :in_progress) |> Ash.read!()
    active =
      Enum.map(active_appts, fn appt ->
        {appt, Dispatch.checklist_progress(appt.id)}
      end)

    # Subscribe to ALL loaded appointment topics so any status change updates immediately.
    # Track already-subscribed IDs to avoid redundant subscribe calls.
    socket =
      if connected?(socket) do
        already = socket.assigns.subscribed_appointment_ids
        new_ids = all |> Enum.map(& &1.id) |> MapSet.new()
        to_subscribe = MapSet.difference(new_ids, already)
        for id <- to_subscribe, do: AppointmentTracker.subscribe(id)
        assign(socket, subscribed_appointment_ids: MapSet.union(already, to_subscribe))
      else
        socket
      end

    # Build map pin data for filtered appointments
    map_pins =
      filtered
      |> Enum.map(fn appt ->
        addr = Map.get(address_map, appt.address_id)
        coords = if addr, do: Zones.coordinates_for_address(addr), else: nil

        case coords do
          {lat, lng} ->
            vehicle = Map.get(vehicle_map, appt.vehicle_id)
            %{
              lat: lat,
              lng: lng,
              status: to_string(appt.status),
              vehicle_type: vehicle && to_string(vehicle.size) || "car",
              service: Map.get(socket.assigns.service_map, appt.service_type_id, "Service"),
              customer: Map.get(customer_map, appt.customer_id, "Customer"),
              time: Calendar.strftime(appt.scheduled_at, "%b %d · %I:%M %p"),
              zone: addr && to_string(addr.zone),
              zone_label: addr && addr.zone && Zones.short_label(addr.zone)
            }

          _ ->
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    socket =
      assign(socket,
        all_appointments: all,
        filtered_appointments: filtered,
        active: active,
        customer_map: customer_map,
        address_map: address_map,
        vehicle_map: vehicle_map,
        map_pins: map_pins
      )

    # Push pin data to the map hook on filter changes
    # (initial load handled by request_map_pins from the hook)
    if connected?(socket) do
      push_event(socket, "update_map_pins", %{pins: map_pins})
    else
      socket
    end
  end

  # Reload a single appointment and update all relevant assigns in-place.
  defp reload_one_appointment(socket, appointment_id) do
    case Ash.get(Appointment, appointment_id) do
      {:ok, updated} ->
        all = Enum.map(socket.assigns.all_appointments, fn a ->
          if a.id == updated.id, do: updated, else: a
        end)

        # Re-derive active list from updated all_appointments
        active_appts = Enum.filter(all, &(&1.status == :in_progress))
        active =
          Enum.map(active_appts, fn appt ->
            existing = Enum.find(socket.assigns.active, fn {a, _} -> a.id == appt.id end)
            if existing, do: existing, else: {appt, Dispatch.checklist_progress(appt.id)}
          end)

        # Subscribe to the appointment topic if newly loaded (e.g., just confirmed)
        socket =
          if connected?(socket) && !MapSet.member?(socket.assigns.subscribed_appointment_ids, appointment_id) do
            AppointmentTracker.subscribe(appointment_id)
            assign(socket, subscribed_appointment_ids: MapSet.put(socket.assigns.subscribed_appointment_ids, appointment_id))
          else
            socket
          end

        assign(socket, all_appointments: all, active: active)

      _ ->
        socket
    end
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

  defp schedule_refresh do
    Process.send_after(self(), :refresh, @refresh_interval)
  end

  defp filter_appointments_by_status(appointments, status, filter_date, filter_tech, filter_zone, address_map) do
    appointments
    |> Enum.filter(fn appt ->
      # Status filter
      appt.status == status &&
      # Date filter
      (is_nil(filter_date) || date_matches(appt.scheduled_at, filter_date)) &&
      # Technician filter
      (is_nil(filter_tech) || (filter_tech == "unassigned" && is_nil(appt.technician_id)) || appt.technician_id == filter_tech) &&
      # Zone filter
      (is_nil(filter_zone) || zone_matches(appt, filter_zone, address_map))
    end)
  end

  defp date_matches(scheduled_at, filter_date) do
    {:ok, day_start} = DateTime.new(filter_date, ~T[00:00:00])
    {:ok, day_end} = DateTime.new(Date.add(filter_date, 1), ~T[00:00:00])
    DateTime.compare(scheduled_at, day_start) in [:gt, :eq] && DateTime.compare(scheduled_at, day_end) == :lt
  end

  defp zone_matches(appointment, filter_zone, address_map) do
    zone = String.to_existing_atom(filter_zone)
    case Map.get(address_map, appointment.address_id) do
      %{zone: appt_zone} -> appt_zone == zone
      _ -> false
    end
  end
end
