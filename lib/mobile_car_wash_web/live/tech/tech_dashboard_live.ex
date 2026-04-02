defmodule MobileCarWashWeb.TechDashboardLive do
  @moduledoc """
  Technician's daily dashboard — shows today's assigned appointments
  with links to start checklists. Mobile-first design.
  """
  use MobileCarWashWeb, :live_view

  alias MobileCarWash.Scheduling.{Appointment, AppointmentTracker, ServiceType, Dispatch}
  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Fleet.{Address, Vehicle}
  alias MobileCarWash.Operations.TechEarnings
  alias MobileCarWash.Zones

  require Ash.Query

  @impl true
  def mount(_params, _session, socket) do
    tech_user = socket.assigns.current_customer

    # Find technician record linked to this user account (or fall back to name match)
    technicians = Ash.read!(MobileCarWash.Operations.Technician)
    tech_record =
      Enum.find(technicians, fn t -> t.user_account_id == tech_user.id end) ||
      Enum.find(technicians, fn t -> t.name == tech_user.name end)

    is_admin = tech_user.role == :admin

    today = Date.utc_today()
    tomorrow = Date.add(today, 1)

    # Admins see all appointments; techs see only their own
    {todays, tomorrows} =
      if tech_record do
        {load_appointments(today, tech_record.id), load_appointments(tomorrow, tech_record.id)}
      else
        # Admin without a tech record — show all appointments
        all_today = Dispatch.appointments_for_date(today)
        all_tomorrow = Dispatch.appointments_for_date(tomorrow)
        {all_today, all_tomorrow}
      end

    all_today = Dispatch.appointments_for_date(today)
    all_tomorrow = Dispatch.appointments_for_date(tomorrow)
    unassigned = Enum.filter(all_today ++ all_tomorrow, &is_nil(&1.technician_id))

    # Load earnings summary (only if linked to a tech record)
    earnings_tab = :week
    earnings_ref = Date.utc_today()
    earnings = if tech_record, do: TechEarnings.earnings_for_period(tech_record, earnings_tab, earnings_ref), else: nil

    all_appts = todays ++ tomorrows
    service_map = Ash.read!(ServiceType) |> Map.new(&{&1.id, &1})
    customer_map = load_customer_map(all_appts)
    address_map = load_address_map(all_appts)
    vehicle_map = load_vehicle_map(all_appts)
    map_pins = build_map_pins(todays, service_map, customer_map, address_map, vehicle_map)
    map_view = :today

    # Load unassigned appointments in tech's zone
    zone_appointments = load_zone_appointments(tech_record, address_map, service_map)

    socket =
      assign(socket,
        page_title: "My Schedule",
        tech_user: tech_user,
        tech_record: tech_record,
        todays_appointments: todays,
        tomorrows_appointments: tomorrows,
        unassigned_count: length(unassigned),
        is_admin: is_admin,
        earnings: earnings,
        earnings_tab: earnings_tab,
        earnings_ref: earnings_ref,
        service_map: service_map,
        customer_map: customer_map,
        address_map: address_map,
        vehicle_map: vehicle_map,
        map_pins: map_pins,
        map_view: map_view,
        zone_appointments: zone_appointments,
        requested_ids: MapSet.new(),
        requested_appts: []
      )

    # Subscribe to new appointment broadcasts
    if connected?(socket) do
      AppointmentTracker.subscribe_to_new_appointments()
    end

    {:ok, socket}
  end

  @impl true
  def handle_info({:new_appointment, _id}, socket) do
    {:noreply, reload_appointments(socket)}
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("earnings_tab", %{"period" => period}, socket) do
    tab = String.to_existing_atom(period)
    ref = Date.utc_today()
    {:noreply, load_earnings(socket, tab, ref)}
  end

  def handle_event("earnings_prev", _params, socket) do
    ref = TechEarnings.shift_period(socket.assigns.earnings_tab, socket.assigns.earnings_ref, :prev)
    {:noreply, load_earnings(socket, socket.assigns.earnings_tab, ref)}
  end

  def handle_event("earnings_next", _params, socket) do
    ref = TechEarnings.shift_period(socket.assigns.earnings_tab, socket.assigns.earnings_ref, :next)
    {:noreply, load_earnings(socket, socket.assigns.earnings_tab, ref)}
  end

  def handle_event("earnings_today", _params, socket) do
    {:noreply, load_earnings(socket, socket.assigns.earnings_tab, Date.utc_today())}
  end

  def handle_event("request_map_pins", _params, socket) do
    {:noreply, push_event(socket, "update_map_pins", %{pins: socket.assigns.map_pins})}
  end

  def handle_event("map_view", %{"view" => view}, socket) do
    map_view = String.to_existing_atom(view)

    appts =
      case map_view do
        :today ->
          socket.assigns.todays_appointments

        :all ->
          # Load all appointments assigned to this tech
          if socket.assigns.tech_record do
            Appointment
            |> Ash.Query.filter(
              technician_id == ^socket.assigns.tech_record.id and
                status != :cancelled
            )
            |> Ash.Query.sort(scheduled_at: :asc)
            |> Ash.read!()
          else
            socket.assigns.todays_appointments ++ socket.assigns.tomorrows_appointments
          end
      end

    # Load any missing addresses/vehicles
    new_addr_ids = Enum.map(appts, & &1.address_id) |> Enum.uniq()
    address_map =
      if new_addr_ids != [] do
        MobileCarWash.Fleet.Address |> Ash.Query.filter(id in ^new_addr_ids) |> Ash.read!() |> Map.new(&{&1.id, &1})
      else
        %{}
      end

    new_veh_ids = Enum.map(appts, & &1.vehicle_id) |> Enum.uniq()
    vehicle_map =
      if new_veh_ids != [] do
        MobileCarWash.Fleet.Vehicle |> Ash.Query.filter(id in ^new_veh_ids) |> Ash.read!() |> Map.new(&{&1.id, &1})
      else
        %{}
      end

    new_cust_ids = Enum.map(appts, & &1.customer_id) |> Enum.uniq()
    customer_map =
      if new_cust_ids != [] do
        Customer |> Ash.Query.filter(id in ^new_cust_ids) |> Ash.read!() |> Map.new(&{&1.id, &1.name})
      else
        %{}
      end

    pins = build_map_pins(appts, socket.assigns.service_map, customer_map, address_map, vehicle_map)

    socket =
      socket
      |> assign(map_view: map_view, map_pins: pins)
      |> push_event("update_map_pins", %{pins: pins})

    {:noreply, socket}
  end

  def handle_event("request_appointment", %{"id" => appointment_id}, socket) do
    tech = socket.assigns.tech_record

    if tech do
      # Notify dispatch via PubSub
      AppointmentTracker.broadcast_tech_request(appointment_id, tech.id, tech.name)

      # Move from zone_appointments to requested list
      requested_appt = Enum.find(socket.assigns.zone_appointments, &(&1.id == appointment_id))
      zone_appointments = Enum.reject(socket.assigns.zone_appointments, &(&1.id == appointment_id))
      requested_ids = MapSet.put(socket.assigns.requested_ids, appointment_id)
      requested_appts = socket.assigns.requested_appts ++ (if requested_appt, do: [requested_appt], else: [])

      {:noreply,
       socket
       |> assign(zone_appointments: zone_appointments, requested_ids: requested_ids, requested_appts: requested_appts)
       |> put_flash(:info, "Request sent to dispatch!")}
    else
      {:noreply, put_flash(socket, :error, "No technician record linked")}
    end
  end

  def handle_event("start_wash", %{"id" => appointment_id}, socket) do
    alias MobileCarWash.Scheduling.WashOrchestrator

    case WashOrchestrator.start_wash(appointment_id) do
      {:ok, checklist} ->
        {:noreply, push_navigate(socket, to: ~p"/tech/checklist/#{checklist.id}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not start wash: #{inspect(reason)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-lg mx-auto py-6 px-4">
      <div class="mb-6">
        <h1 class="text-2xl font-bold">My Schedule</h1>
        <p class="text-base-content/60">Welcome, {@tech_user.name}</p>
      </div>

      <div :if={!@tech_record && !@is_admin} class="alert alert-warning mb-6">
        <span>Your account isn't linked to a technician record yet. Contact your manager.</span>
      </div>

      <div :if={!@tech_record && @is_admin} class="alert alert-info mb-6">
        <span>Viewing as admin — showing all appointments. Link your account to a technician in
          <.link navigate={~p"/admin/dispatch"} class="link font-semibold">Dispatch</.link>
          to see personal schedule.
        </span>
      </div>

      <div :if={@unassigned_count > 0} class="alert alert-info mb-6">
        <span>{@unassigned_count} unassigned appointment(s) — check with dispatch.</span>
      </div>

      <!-- Map -->
      <div class="mb-8">
        <div class="flex justify-between items-center mb-3">
          <h2 class="text-lg font-bold">{if @map_view == :today, do: "Today's Route", else: "All Appointments"}</h2>
          <div class="tabs tabs-boxed tabs-sm">
            <button class={["tab", @map_view == :today && "tab-active"]} phx-click="map_view" phx-value-view="today">Today</button>
            <button class={["tab", @map_view == :all && "tab-active"]} phx-click="map_view" phx-value-view="all">All</button>
          </div>
        </div>
        <div
          id="tech-map"
          phx-hook="DispatchMap"
          phx-update="ignore"
          class="w-full h-64 rounded-lg shadow border border-base-300 z-0"
        />
        <div class="flex gap-3 mt-2 text-xs text-base-content/50">
          <span class="flex items-center gap-1"><span class="w-3 h-3 rounded-full bg-[#ADB5BD] inline-block"></span> Pending</span>
          <span class="flex items-center gap-1"><span class="w-3 h-3 rounded-full bg-[#3A7CA5] inline-block"></span> Confirmed</span>
          <span class="flex items-center gap-1"><span class="w-3 h-3 rounded-full bg-[#E6A817] inline-block"></span> In Progress</span>
          <span class="flex items-center gap-1"><span class="w-3 h-3 rounded-full bg-[#2A9D6F] inline-block"></span> Completed</span>
        </div>
      </div>

      <!-- Today -->
      <div class="mb-8">
        <h2 class="text-lg font-bold mb-3">Today</h2>
        <div :if={@todays_appointments == []} class="text-base-content/50 text-sm">
          No appointments today
        </div>
        <div class="space-y-3">
          <.appointment_row
            :for={appt <- @todays_appointments}
            appointment={appt}
            service={Map.get(@service_map, appt.service_type_id)}
            customer_name={Map.get(@customer_map, appt.customer_id, "Customer")}
            address={Map.get(@address_map, appt.address_id)}
            vehicle={Map.get(@vehicle_map, appt.vehicle_id)}
          />

        </div>
      </div>

      <!-- Tomorrow -->
      <div class="mb-8">
        <h2 class="text-lg font-bold mb-3">Tomorrow</h2>
        <div :if={@tomorrows_appointments == []} class="text-base-content/50 text-sm">
          No appointments tomorrow
        </div>
        <div class="space-y-3">
          <.appointment_row
            :for={appt <- @tomorrows_appointments}
            appointment={appt}
            service={Map.get(@service_map, appt.service_type_id)}
            customer_name={Map.get(@customer_map, appt.customer_id, "Customer")}
            address={Map.get(@address_map, appt.address_id)}
            vehicle={Map.get(@vehicle_map, appt.vehicle_id)}
          />
        </div>
      </div>

      <!-- Requested — awaiting dispatch approval -->
      <div :if={@requested_appts != []} class="mb-8">
        <h2 class="text-lg font-bold mb-3">
          Requested
          <span class="badge badge-sm badge-ghost ml-2">{length(@requested_appts)}</span>
        </h2>
        <div class="space-y-3">
          <div
            :for={ra <- @requested_appts}
            class="card shadow-sm border border-dashed border-base-300 opacity-60"
          >
            <div class="card-body p-4">
              <div class="flex justify-between items-start">
                <div>
                  <div class="flex items-center gap-2">
                    <span class="font-bold">{ra.service_name}</span>
                    <span :if={ra.zone} class={["badge badge-xs", Zones.badge_class(ra.zone)]}>
                      {Zones.short_label(ra.zone)}
                    </span>
                  </div>
                  <p class="text-sm text-base-content/50">{Calendar.strftime(ra.scheduled_at, "%b %d · %I:%M %p")}</p>
                  <p class="text-xs text-base-content/40">{ra.address_street}, {ra.address_city}</p>
                </div>
                <span class="badge badge-ghost badge-sm">Awaiting approval</span>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Available Appointments -->
      <div :if={@tech_record && @zone_appointments != []} class="mb-8">
        <h2 class="text-lg font-bold mb-3">
          {if @tech_record.zone, do: "Available in Your Zone", else: "Available Appointments"}
          <span :if={@tech_record.zone} class={["badge badge-sm ml-2", Zones.badge_class(@tech_record.zone)]}>
            {Zones.short_label(@tech_record.zone)}
          </span>
        </h2>
        <p class="text-sm text-base-content/50 mb-3">Unassigned appointments. Tap to request.</p>
        <div class="space-y-3">
          <div :for={za <- @zone_appointments} class="card bg-base-100 shadow-sm border-l-4 border-warning">
            <div class="card-body p-4">
              <div class="flex justify-between items-start">
                <div>
                  <div class="flex items-center gap-2">
                    <span class="font-bold">{za.service_name}</span>
                    <span :if={za.zone} class={["badge badge-xs", Zones.badge_class(za.zone)]}>
                      {Zones.short_label(za.zone)}
                    </span>
                  </div>
                  <p class="text-sm text-base-content/60">{Calendar.strftime(za.scheduled_at, "%b %d · %I:%M %p")}</p>
                  <p class="text-xs text-base-content/40">{za.address_street}, {za.address_city}</p>
                </div>
                <button
                  class="btn btn-primary btn-sm"
                  phx-click="request_appointment"
                  phx-value-id={za.id}
                >
                  Request
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Earnings -->
      <div :if={@tech_record} class="mb-8">
        <h2 class="text-lg font-bold mb-3">Earnings</h2>

        <!-- Period Tabs -->
        <div class="tabs tabs-boxed mb-4">
          <button
            :for={tab <- [{:day, "Day"}, {:week, "Week"}, {:month, "Month"}, {:year, "Year"}]}
            class={["tab", @earnings_tab == elem(tab, 0) && "tab-active"]}
            phx-click="earnings_tab"
            phx-value-period={elem(tab, 0)}
          >
            {elem(tab, 1)}
          </button>
        </div>

        <!-- Period Navigation -->
        <div :if={@earnings} class="flex items-center justify-between mb-4">
          <button class="btn btn-ghost btn-sm" phx-click="earnings_prev">
            &larr; Prev
          </button>
          <div class="text-center">
            <span class="font-semibold text-sm">
              {format_period_label(@earnings_tab, @earnings.period_start, @earnings.period_end)}
            </span>
            <button
              :if={@earnings_ref != Date.utc_today()}
              class="btn btn-ghost btn-xs ml-2"
              phx-click="earnings_today"
            >
              Today
            </button>
          </div>
          <button
            class="btn btn-ghost btn-sm"
            phx-click="earnings_next"
            disabled={Date.compare(@earnings.period_end, Date.utc_today()) != :lt}
          >
            Next &rarr;
          </button>
        </div>

        <!-- Summary Card -->
        <div :if={@earnings} class="card bg-base-100 shadow mb-4">
          <div class="card-body p-4">
            <div class="flex justify-between items-start">
              <div>
                <p class="text-3xl font-bold text-success">${format_dollars(@earnings.total_cents)}</p>
                <p class="text-sm text-base-content/60">
                  {@earnings.washes_count} wash{if @earnings.washes_count != 1, do: "es"} @ ${format_dollars(@earnings.rate_cents)}/wash
                </p>
              </div>
              <div class="text-right">
                <span class="badge badge-outline">Rate: ${format_dollars(@earnings.rate_cents)}</span>
              </div>
            </div>
          </div>
        </div>

        <!-- Wash List for Period -->
        <div :if={@earnings && @earnings.washes != []} class="overflow-x-auto">
          <table class="table table-sm">
            <thead>
              <tr>
                <th>Date</th>
                <th>Service</th>
                <th>Customer</th>
                <th>Time</th>
                <th>Earned</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={wash <- @earnings.washes}>
                <td class="text-sm">{Calendar.strftime(wash.date, "%b %d")}</td>
                <td class="text-sm">{wash.service_name}</td>
                <td class="text-sm">{wash.customer_name}</td>
                <td class="text-sm">
                  <span :if={wash.actual_minutes}>{wash.actual_minutes}m</span>
                  <span :if={!wash.actual_minutes}>{wash.duration_minutes}m est</span>
                </td>
                <td class="text-sm font-semibold text-success">
                  ${format_dollars(@earnings.rate_cents)}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <div :if={@earnings && @earnings.washes == []} class="text-base-content/50 text-sm">
          No completed washes for this period
        </div>
      </div>
    </div>
    """
  end

  defp load_earnings(socket, tab, ref) do
    earnings = if socket.assigns.tech_record,
      do: TechEarnings.earnings_for_period(socket.assigns.tech_record, tab, ref),
      else: nil

    assign(socket, earnings_tab: tab, earnings_ref: ref, earnings: earnings)
  end

  defp format_dollars(cents) when is_integer(cents) do
    dollars = div(cents, 100)
    remainder = rem(cents, 100)
    "#{dollars}.#{String.pad_leading("#{remainder}", 2, "0")}"
  end

  defp format_dollars(_), do: "0.00"

  defp format_period_label(:day, date, _), do: Calendar.strftime(date, "%A, %B %d")
  defp format_period_label(:week, start_date, end_date),
    do: "#{Calendar.strftime(start_date, "%b %d")} – #{Calendar.strftime(end_date, "%b %d")}"
  defp format_period_label(:month, date, _), do: Calendar.strftime(date, "%B %Y")
  defp format_period_label(:year, date, _), do: "#{date.year}"

  defp appointment_row(assigns) do
    # Check for existing checklist
    progress = Dispatch.checklist_progress(assigns.appointment.id)
    assigns = assign(assigns, progress: progress)

    ~H"""
    <div class="card bg-base-100 shadow-sm">
      <div class="card-body p-4">
        <div class="flex justify-between items-start">
          <div>
            <span class="font-bold">{@service && @service.name}</span>
            <p class="text-sm">{Calendar.strftime(@appointment.scheduled_at, "%I:%M %p")}</p>
            <p class="text-sm text-base-content/60">{@customer_name}</p>
            <p :if={@vehicle} class="text-xs text-base-content/50">{vehicle_label(@vehicle)}</p>
            <p :if={@address} class="text-xs text-base-content/40">{@address.street}, {@address.city}</p>
          </div>
          <span class={["badge badge-sm", status_class(@appointment.status)]}>
            {format_status(@appointment.status)}
          </span>
        </div>

        <!-- Progress if checklist exists -->
        <div :if={@progress.steps_total > 0} class="mt-2">
          <progress
            class="progress progress-primary w-full"
            value={@progress.steps_done}
            max={@progress.steps_total}
          />
          <span class="text-xs text-base-content/50">{@progress.steps_done}/{@progress.steps_total} steps</span>
        </div>

        <!-- Action buttons -->
        <div class="mt-3">
          <!-- Start Wash: for confirmed appointments without a checklist -->
          <button
            :if={@progress.steps_total == 0 and @appointment.status == :confirmed}
            class="btn btn-warning btn-sm btn-block"
            phx-click="start_wash"
            phx-value-id={@appointment.id}
          >
            Start Wash
          </button>

          <!-- Continue/Start Checklist: when checklist already exists -->
          <.link
            :if={@progress.steps_total > 0}
            navigate={~p"/tech/checklist/#{get_checklist_id(@appointment.id)}"}
            class="btn btn-primary btn-sm btn-block"
          >
            {if @progress.steps_done > 0, do: "Continue Checklist", else: "Start Checklist"}
          </.link>

          <span :if={@appointment.status == :pending} class="text-xs text-base-content/50">
            Awaiting confirmation
          </span>
        </div>
      </div>
    </div>
    """
  end

  defp load_appointments(date, technician_id) do
    {:ok, day_start} = DateTime.new(date, ~T[00:00:00])
    {:ok, day_end} = DateTime.new(Date.add(date, 1), ~T[00:00:00])

    Appointment
    |> Ash.Query.filter(
      scheduled_at >= ^day_start and scheduled_at < ^day_end and
        technician_id == ^technician_id and status != :cancelled
    )
    |> Ash.Query.sort(scheduled_at: :asc)
    |> Ash.read!()
  end

  defp load_customer_map(appointments) do
    ids = Enum.map(appointments, & &1.customer_id) |> Enum.uniq()
    if ids == [], do: %{}, else:
      Customer |> Ash.Query.filter(id in ^ids) |> Ash.read!() |> Map.new(&{&1.id, &1.name})
  end

  defp load_address_map(appointments) do
    ids = Enum.map(appointments, & &1.address_id) |> Enum.uniq()
    if ids == [], do: %{}, else:
      Address |> Ash.Query.filter(id in ^ids) |> Ash.read!() |> Map.new(&{&1.id, &1})
  end

  defp load_zone_appointments(nil, _address_map, _service_map), do: []

  defp load_zone_appointments(tech_record, _existing_address_map, service_map) do
    # Fetch unassigned pending/confirmed appointments
    unassigned =
      Appointment
      |> Ash.Query.filter(is_nil(technician_id) and status in [:pending, :confirmed])
      |> Ash.Query.sort(scheduled_at: :asc)
      |> Ash.read!()

    # Load their addresses to check zone
    addr_ids = Enum.map(unassigned, & &1.address_id) |> Enum.uniq()
    addr_map =
      if addr_ids != [] do
        Address |> Ash.Query.filter(id in ^addr_ids) |> Ash.read!() |> Map.new(&{&1.id, &1})
      else
        %{}
      end

    # Filter to tech's zone (floaters with no zone see ALL unassigned)
    filtered =
      if tech_record.zone do
        Enum.filter(unassigned, fn appt ->
          addr = Map.get(addr_map, appt.address_id)
          addr && addr.zone == tech_record.zone
        end)
      else
        unassigned
      end

    Enum.map(filtered, fn appt ->
      addr = Map.get(addr_map, appt.address_id)
      svc = Map.get(service_map, appt.service_type_id)
      %{
        id: appt.id,
        scheduled_at: appt.scheduled_at,
        service_name: svc && svc.name || "Service",
        address_street: addr && addr.street || "",
        address_city: addr && addr.city || "",
        zone: addr && addr.zone
      }
    end)
  end

  defp load_vehicle_map(appointments) do
    ids = Enum.map(appointments, & &1.vehicle_id) |> Enum.uniq()
    if ids == [], do: %{}, else:
      Vehicle |> Ash.Query.filter(id in ^ids) |> Ash.read!() |> Map.new(&{&1.id, &1})
  end

  defp build_map_pins(appointments, service_map, customer_map, address_map, vehicle_map) do
    appointments
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
            vehicle_type: (vehicle && to_string(vehicle.size)) || "car",
            service: Map.get(service_map, appt.service_type_id, %{name: "Service"}).name,
            customer: Map.get(customer_map, appt.customer_id, "Customer"),
            time: Calendar.strftime(appt.scheduled_at, "%I:%M %p"),
            zone: addr && to_string(addr.zone),
            zone_label: addr && addr.zone && Zones.short_label(addr.zone)
          }

        _ ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp reload_appointments(socket) do
    tech_record = socket.assigns.tech_record

    today = Date.utc_today()
    tomorrow = Date.add(today, 1)

    # Reload appointments for tech
    {todays, tomorrows} =
      if tech_record do
        {load_appointments(today, tech_record.id), load_appointments(tomorrow, tech_record.id)}
      else
        # Admin without a tech record — show all appointments
        all_today = Dispatch.appointments_for_date(today)
        all_tomorrow = Dispatch.appointments_for_date(tomorrow)
        {all_today, all_tomorrow}
      end

    all_today = Dispatch.appointments_for_date(today)
    all_tomorrow = Dispatch.appointments_for_date(tomorrow)
    unassigned = Enum.filter(all_today ++ all_tomorrow, &is_nil(&1.technician_id))

    # Reload maps
    all_appts = todays ++ tomorrows
    service_map = socket.assigns.service_map
    customer_map = load_customer_map(all_appts)
    address_map = load_address_map(all_appts)
    vehicle_map = load_vehicle_map(all_appts)
    map_pins = build_map_pins(todays, service_map, customer_map, address_map, vehicle_map)

    # Reload zone appointments
    zone_appointments = load_zone_appointments(tech_record, address_map, service_map)

    assign(socket,
      todays_appointments: todays,
      tomorrows_appointments: tomorrows,
      unassigned_count: length(unassigned),
      customer_map: customer_map,
      address_map: address_map,
      vehicle_map: vehicle_map,
      map_pins: map_pins,
      zone_appointments: zone_appointments
    )
  end

  defp get_checklist_id(appointment_id) do
    case MobileCarWash.Operations.AppointmentChecklist
         |> Ash.Query.filter(appointment_id == ^appointment_id)
         |> Ash.read!() do
      [cl | _] -> cl.id
      [] -> "none"
    end
  end

  defp status_class(:pending), do: "badge-ghost"
  defp status_class(:confirmed), do: "badge-info"
  defp status_class(:in_progress), do: "badge-warning"
  defp status_class(:completed), do: "badge-success"
  defp status_class(_), do: "badge-ghost"

  defp vehicle_label(%{make: make, model: model, size: size}) do
    type = case size do
      :car -> "Car"
      :suv_van -> "SUV/Van"
      :pickup -> "Pickup"
      _ -> ""
    end
    [make, model, type] |> Enum.reject(&(is_nil(&1) or &1 == "")) |> Enum.join(" · ")
  end
  defp vehicle_label(_), do: nil

  defp format_status(:pending), do: "Pending"
  defp format_status(:confirmed), do: "Confirmed"
  defp format_status(:in_progress), do: "Active"
  defp format_status(:completed), do: "Done"
  defp format_status(s), do: to_string(s)
end
