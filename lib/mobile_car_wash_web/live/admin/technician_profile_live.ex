defmodule MobileCarWashWeb.Admin.TechnicianProfileLive do
  @moduledoc """
  Admin tech profile — everything about one technician at a glance:
  van assignment, pay rate, appointments (past/today/upcoming), performance stats.
  """
  use MobileCarWashWeb, :live_view

  alias MobileCarWash.Operations.{Technician, Van, TechEarnings}
  alias MobileCarWash.Scheduling.{Appointment, ServiceType}
  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Inventory

  require Ash.Query

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    tech = Ash.get!(Technician, id)
    vans = Van |> Ash.Query.sort(name: :asc) |> Ash.read!()
    van = if tech.van_id, do: Enum.find(vans, &(&1.id == tech.van_id))

    user_account =
      if tech.user_account_id do
        case Ash.get(Customer, tech.user_account_id, authorize?: false) do
          {:ok, u} -> u
          _ -> nil
        end
      end

    service_map = ServiceType |> Ash.read!() |> Map.new(&{&1.id, &1})
    supply_map = Inventory.list_all_supplies() |> Map.new(&{&1.id, &1})
    earnings = TechEarnings.earnings_for_period(tech, :week)
    {appointments, tab} = {load_tab(:today, tech.id, service_map), :today}
    supply_usage = Inventory.usage_for_technician(tech.id) |> Enum.take(50)

    {:ok,
     assign(socket,
       page_title: tech.name,
       technician: tech,
       van: van,
       vans: vans,
       user_account: user_account,
       service_map: service_map,
       supply_map: supply_map,
       earnings: earnings,
       appointments: appointments,
       active_tab: tab,
       editing: nil,
       pay_rate_input: nil,
       error: nil,
       supply_usage: supply_usage
     )}
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab_str}, socket) do
    tab = String.to_existing_atom(tab_str)
    appointments = load_tab(tab, socket.assigns.technician.id, socket.assigns.service_map)
    {:noreply, assign(socket, active_tab: tab, appointments: appointments)}
  end

  def handle_event("start_edit", %{"field" => field}, socket) do
    input =
      case field do
        "pay_rate" ->
          tech = socket.assigns.technician
          if tech.pay_rate_pct do
            pct = Decimal.to_float(tech.pay_rate_pct) * 100
            :erlang.float_to_binary(pct, decimals: 1)
          else
            ""
          end

        _ ->
          nil
      end

    {:noreply, assign(socket, editing: String.to_existing_atom(field), pay_rate_input: input, error: nil)}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, editing: nil, error: nil)}
  end

  def handle_event("save_van", %{"van_id" => van_id}, socket) do
    tech = socket.assigns.technician
    new_van_id = if van_id == "", do: nil, else: van_id

    tech
    |> Ash.Changeset.for_update(:update, %{van_id: new_van_id})
    |> Ash.update(authorize?: false)

    tech = Ash.get!(Technician, tech.id)
    vans = socket.assigns.vans
    van = if tech.van_id, do: Enum.find(vans, &(&1.id == tech.van_id))

    {:noreply, assign(socket, technician: tech, van: van, editing: nil)}
  end

  def handle_event("save_pay_rate", %{"pct" => pct_str}, socket) do
    case parse_pct(pct_str) do
      {:ok, pct_decimal} ->
        tech = socket.assigns.technician

        tech
        |> Ash.Changeset.for_update(:update, %{pay_rate_pct: pct_decimal})
        |> Ash.update(authorize?: false)

        tech = Ash.get!(Technician, tech.id)
        earnings = TechEarnings.earnings_for_period(tech, :week)
        {:noreply, assign(socket, technician: tech, earnings: earnings, editing: nil, error: nil)}

      {:error, msg} ->
        {:noreply, assign(socket, error: msg)}
    end
  end

  def handle_event("toggle_active", _params, socket) do
    tech = socket.assigns.technician

    tech
    |> Ash.Changeset.for_update(:update, %{active: !tech.active})
    |> Ash.update(authorize?: false)

    tech = Ash.get!(Technician, tech.id)
    {:noreply, assign(socket, technician: tech)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto py-8 px-4">

      <!-- Breadcrumb -->
      <div class="mb-6">
        <.link navigate={~p"/admin/dispatch"} class="btn btn-ghost btn-sm">
          ← Dispatch
        </.link>
      </div>

      <!-- Header -->
      <div class="card bg-base-100 shadow mb-6">
        <div class="card-body p-6">
          <div class="flex items-start justify-between flex-wrap gap-4">
            <div>
              <h1 class="text-2xl font-bold">{@technician.name}</h1>
              <p :if={@technician.phone} class="text-base-content/80 mt-1">{@technician.phone}</p>
              <p :if={@user_account} class="text-sm text-base-content/70 mt-1">
                Account: {@user_account.email}
              </p>
            </div>
            <div class="flex items-center gap-2">
              <span :if={@technician.zone} class={["badge", zone_badge(@technician.zone)]}>
                {zone_label(@technician.zone)}
              </span>
              <button
                class={["btn btn-sm", @technician.active && "btn-success" || "btn-ghost"]}
                phx-click="toggle_active"
              >
                {if @technician.active, do: "Active", else: "Inactive"}
              </button>
            </div>
          </div>
        </div>
      </div>

      <!-- Van + Pay Rate row -->
      <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mb-6">

        <!-- Van assignment -->
        <div class="card bg-base-100 shadow">
          <div class="card-body p-4">
            <h3 class="font-semibold mb-3">Van</h3>
            <div :if={@editing != :van}>
              <div :if={@van} class="flex items-center justify-between">
                <div>
                  <p class="font-medium">{@van.name}</p>
                  <p :if={@van.license_plate} class="text-sm text-base-content/70">
                    {@van.license_plate}
                  </p>
                </div>
                <button class="btn btn-ghost btn-xs" phx-click="start_edit" phx-value-field="van">
                  Change
                </button>
              </div>
              <div :if={!@van} class="flex items-center justify-between">
                <span class="text-base-content/70 text-sm">No van assigned</span>
                <button class="btn btn-primary btn-xs" phx-click="start_edit" phx-value-field="van">
                  Assign
                </button>
              </div>
            </div>
            <form :if={@editing == :van} phx-submit="save_van" class="flex flex-col gap-2">
              <select name="van_id" class="select select-bordered select-sm w-full">
                <option value="">— Unassigned —</option>
                <option
                  :for={v <- @vans}
                  value={v.id}
                  selected={@technician.van_id == v.id}
                  disabled={!v.active}
                >
                  {v.name}{if v.license_plate, do: " · #{v.license_plate}"}{if !v.active, do: " (inactive)"}
                </option>
              </select>
              <div class="flex gap-2">
                <button type="submit" class="btn btn-primary btn-sm flex-1">Save</button>
                <button type="button" class="btn btn-ghost btn-sm" phx-click="cancel_edit">Cancel</button>
              </div>
            </form>
          </div>
        </div>

        <!-- Pay rate -->
        <div class="card bg-base-100 shadow">
          <div class="card-body p-4">
            <h3 class="font-semibold mb-3">Pay Rate</h3>
            <div :if={@editing != :pay_rate}>
              <div class="flex items-center justify-between">
                <div>
                  <p :if={@technician.pay_rate_pct} class="text-2xl font-bold">
                    {format_pct(@technician.pay_rate_pct)}%
                    <span class="text-sm font-normal text-base-content/70">per wash</span>
                  </p>
                  <p :if={!@technician.pay_rate_pct} class="text-2xl font-bold">
                    ${format_dollars(@technician.pay_rate_cents || 2500)}
                    <span class="text-sm font-normal text-base-content/70">flat / wash</span>
                  </p>
                  <p :if={@technician.pay_rate_pct} class="text-sm text-base-content/70 mt-1">
                    ~${format_dollars(round((@technician.pay_rate_pct |> Decimal.to_float()) * 10000))} on a $100 wash
                  </p>
                </div>
                <button class="btn btn-ghost btn-xs" phx-click="start_edit" phx-value-field="pay_rate">
                  Edit
                </button>
              </div>
            </div>
            <form :if={@editing == :pay_rate} phx-submit="save_pay_rate" class="flex flex-col gap-2">
              <div class="flex items-center gap-2">
                <input
                  type="number"
                  name="pct"
                  class="input input-bordered input-sm w-24"
                  value={@pay_rate_input}
                  min="0"
                  max="100"
                  step="0.5"
                  placeholder="30"
                />
                <span class="text-base-content/80">% of wash price</span>
              </div>
              <p :if={@error} class="text-error text-xs">{@error}</p>
              <div class="flex gap-2">
                <button type="submit" class="btn btn-primary btn-sm flex-1">Save</button>
                <button type="button" class="btn btn-ghost btn-sm" phx-click="cancel_edit">Cancel</button>
              </div>
            </form>
          </div>
        </div>
      </div>

      <!-- Earnings stats -->
      <div class="stats shadow w-full mb-6">
        <div class="stat">
          <div class="stat-title">Washes This Week</div>
          <div class="stat-value text-primary">{@earnings.washes_count}</div>
          <div class="stat-desc">{format_date_range(@earnings.period_start, @earnings.period_end)}</div>
        </div>
        <div class="stat">
          <div class="stat-title">Earned This Week</div>
          <div class="stat-value text-success">${format_dollars(@earnings.total_cents)}</div>
          <div class="stat-desc">
            {if @earnings.pay_rate_pct,
              do: "#{format_pct(@earnings.pay_rate_pct)}% of job price",
              else: "$#{format_dollars(@earnings.rate_cents)}/wash flat"}
          </div>
        </div>
        <div class="stat">
          <div class="stat-title">Avg Duration</div>
          <div class="stat-value">
            {avg_actual_minutes(@earnings.washes)}<span class="text-lg">m</span>
          </div>
          <div class="stat-desc">actual vs scheduled</div>
        </div>
      </div>

      <!-- Appointment tabs -->
      <div class="mb-2">
        <div class="tabs tabs-bordered">
          <button
            :for={{tab, label} <- [{:past, "Past"}, {:today, "Today / Active"}, {:upcoming, "Upcoming"}]}
            class={["tab", @active_tab == tab && "tab-active"]}
            phx-click="switch_tab"
            phx-value-tab={tab}
          >
            {label}
          </button>
        </div>
      </div>

      <div class="card bg-base-100 shadow">
        <div class="card-body p-0">
          <div :if={@appointments == []} class="p-6 text-center text-base-content/70 text-sm">
            No appointments
          </div>
          <div :if={@appointments != []} class="overflow-x-auto">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>Date / Time</th>
                  <th>Service</th>
                  <th>Customer</th>
                  <th>Price</th>
                  <th :if={@active_tab == :past}>Earned</th>
                  <th :if={@active_tab == :past}>Duration</th>
                  <th>Status</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={appt <- @appointments}>
                  <td class="whitespace-nowrap text-sm">
                    {Calendar.strftime(appt.scheduled_at, "%b %d · %I:%M %p")}
                  </td>
                  <td class="text-sm">{appt.service_name}</td>
                  <td class="text-sm">{appt.customer_name}</td>
                  <td class="text-sm">${format_dollars(appt.price_cents)}</td>
                  <td :if={@active_tab == :past} class="text-sm font-semibold text-success">
                    ${format_dollars(appt.earned_cents)}
                  </td>
                  <td :if={@active_tab == :past} class="text-sm">
                    <span :if={appt.actual_minutes}>
                      {appt.actual_minutes}m
                      <span class="text-base-content/70">/ {appt.duration_minutes}m est</span>
                    </span>
                    <span :if={!appt.actual_minutes} class="text-base-content/70">
                      {appt.duration_minutes}m est
                    </span>
                  </td>
                  <td>
                    <span class={["badge badge-sm", status_badge(appt.status)]}>
                      {format_status(appt.status)}
                    </span>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>

      <!-- Supply Usage -->
      <div class="mt-8">
        <h2 class="text-lg font-bold mb-3">Supply Usage (last 50)</h2>
        <div :if={@supply_usage == []} class="text-base-content/70 text-sm">
          No supply usage recorded yet.
        </div>
        <div :if={@supply_usage != []} class="card bg-base-100 shadow">
          <div class="overflow-x-auto">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>Date</th>
                  <th>Supply</th>
                  <th>Qty Used</th>
                  <th>Van</th>
                  <th>Notes</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={rec <- @supply_usage}>
                  <td class="text-sm whitespace-nowrap">
                    {Calendar.strftime(rec.occurred_at, "%b %d, %Y")}
                  </td>
                  <td class="text-sm">
                    <% supply = Map.get(@supply_map, rec.supply_id) %>
                    {supply && supply.name || "Unknown"}
                  </td>
                  <td class="text-sm font-semibold">
                    <% supply = Map.get(@supply_map, rec.supply_id) %>
                    {format_qty(rec.quantity_used)}{supply && " #{supply.unit}"}
                  </td>
                  <td class="text-sm text-base-content/70">
                    {if rec.van_id, do: String.slice(rec.van_id, 0, 8) <> "…", else: "—"}
                  </td>
                  <td class="text-sm text-base-content/70">{rec.notes || "—"}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>

    </div>
    """
  end

  # --- Data loading ---

  defp load_tab(tab, tech_id, service_map) do
    tech = Ash.get!(Technician, tech_id)
    appointments = query_appointments(tab, tech_id)
    customer_map = load_customer_map(appointments)

    checklist_times =
      if tab == :past, do: load_checklist_times(appointments), else: %{}

    Enum.map(appointments, fn appt ->
      actual_minutes = Map.get(checklist_times, appt.id)
      wash = %{price_cents: appt.price_cents, actual_minutes: actual_minutes}

      %{
        id: appt.id,
        scheduled_at: appt.scheduled_at,
        status: appt.status,
        price_cents: appt.price_cents,
        duration_minutes: appt.duration_minutes,
        actual_minutes: actual_minutes,
        earned_cents: if(tab == :past, do: TechEarnings.wash_earnings(wash, tech), else: 0),
        service_name: (Map.get(service_map, appt.service_type_id) || %{name: "Service"}).name,
        customer_name: Map.get(customer_map, appt.customer_id, "Customer")
      }
    end)
  end

  defp load_checklist_times([]), do: %{}
  defp load_checklist_times(appointments) do
    alias MobileCarWash.Operations.{AppointmentChecklist, ChecklistItem}
    ids = Enum.map(appointments, & &1.id)

    checklists =
      AppointmentChecklist
      |> Ash.Query.filter(appointment_id in ^ids)
      |> Ash.read!()

    checklist_ids = Enum.map(checklists, & &1.id)

    if checklist_ids == [] do
      %{}
    else
      items =
        ChecklistItem
        |> Ash.Query.filter(checklist_id in ^checklist_ids and completed == true)
        |> Ash.read!()

      times_by_checklist =
        items
        |> Enum.group_by(& &1.checklist_id)
        |> Map.new(fn {cl_id, cl_items} ->
          total_secs = Enum.sum(Enum.map(cl_items, & &1.actual_seconds || 0))
          {cl_id, div(total_secs, 60)}
        end)

      Map.new(checklists, fn cl ->
        {cl.appointment_id, Map.get(times_by_checklist, cl.id, 0)}
      end)
    end
  end

  defp query_appointments(:today, tech_id) do
    today = Date.utc_today()
    {:ok, day_start} = DateTime.new(today, ~T[00:00:00])
    {:ok, day_end} = DateTime.new(Date.add(today, 1), ~T[00:00:00])

    Appointment
    |> Ash.Query.filter(
      technician_id == ^tech_id and status != :cancelled and
        scheduled_at >= ^day_start and scheduled_at < ^day_end
    )
    |> Ash.Query.sort(scheduled_at: :asc)
    |> Ash.read!()
  end

  defp query_appointments(:upcoming, tech_id) do
    now = DateTime.utc_now()

    Appointment
    |> Ash.Query.filter(
      technician_id == ^tech_id and status in [:pending, :confirmed] and
        scheduled_at > ^now
    )
    |> Ash.Query.sort(scheduled_at: :asc)
    |> Ash.Query.limit(50)
    |> Ash.read!()
  end

  defp query_appointments(:past, tech_id) do
    now = DateTime.utc_now()

    Appointment
    |> Ash.Query.filter(
      technician_id == ^tech_id and status == :completed and scheduled_at < ^now
    )
    |> Ash.Query.sort(scheduled_at: :desc)
    |> Ash.Query.limit(50)
    |> Ash.read!()
  end

  defp load_customer_map([]), do: %{}
  defp load_customer_map(appointments) do
    ids = appointments |> Enum.map(& &1.customer_id) |> Enum.uniq()
    Customer |> Ash.Query.filter(id in ^ids) |> Ash.read!(authorize?: false) |> Map.new(&{&1.id, &1.name})
  end

  # --- Formatting helpers ---

  defp format_dollars(cents) when is_integer(cents) do
    dollars = div(cents, 100)
    remainder = rem(cents, 100)
    "#{dollars}.#{String.pad_leading("#{remainder}", 2, "0")}"
  end
  defp format_dollars(_), do: "0.00"

  defp format_pct(nil), do: "—"
  defp format_pct(decimal) do
    pct = Decimal.to_float(decimal) * 100
    if trunc(pct) == pct, do: "#{trunc(pct)}", else: :erlang.float_to_binary(pct, decimals: 1)
  end

  defp format_date_range(start_date, end_date) do
    "#{Calendar.strftime(start_date, "%b %d")} – #{Calendar.strftime(end_date, "%b %d")}"
  end

  defp format_status(:pending), do: "Pending"
  defp format_status(:confirmed), do: "Confirmed"
  defp format_status(:in_progress), do: "Active"
  defp format_status(:completed), do: "Completed"
  defp format_status(:cancelled), do: "Cancelled"
  defp format_status(s), do: to_string(s)

  defp status_badge(:pending), do: "badge-ghost"
  defp status_badge(:confirmed), do: "badge-info"
  defp status_badge(:in_progress), do: "badge-warning"
  defp status_badge(:completed), do: "badge-success"
  defp status_badge(:cancelled), do: "badge-error"
  defp status_badge(_), do: "badge-ghost"

  defp zone_badge(:nw), do: "badge-info"
  defp zone_badge(:ne), do: "badge-success"
  defp zone_badge(:sw), do: "badge-warning"
  defp zone_badge(:se), do: "badge-error"
  defp zone_badge(_), do: "badge-ghost"

  defp zone_label(:nw), do: "NW"
  defp zone_label(:ne), do: "NE"
  defp zone_label(:sw), do: "SW"
  defp zone_label(:se), do: "SE"
  defp zone_label(_), do: "Floater"

  defp avg_actual_minutes(washes) do
    with_actual = Enum.filter(washes, & &1.actual_minutes)
    if with_actual == [] do
      "—"
    else
      avg = Enum.sum(Enum.map(with_actual, & &1.actual_minutes)) / length(with_actual)
      "#{trunc(avg)}"
    end
  end

  defp format_qty(nil), do: "0"
  defp format_qty(%Decimal{} = d) do
    f = Decimal.to_float(d)
    if trunc(f) == f, do: "#{trunc(f)}", else: "#{Float.round(f, 2)}"
  end
  defp format_qty(n), do: to_string(n)

  defp parse_pct(str) do
    str = String.trim(str)
    case Float.parse(str) do
      {val, ""} when val >= 0 and val <= 100 ->
        {:ok, Decimal.from_float(val / 100)}
      {_, ""} ->
        {:error, "Must be between 0 and 100"}
      _ ->
        {:error, "Enter a number (e.g. 30 for 30%)"}
    end
  end
end
