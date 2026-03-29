defmodule MobileCarWashWeb.TechDashboardLive do
  @moduledoc """
  Technician's daily dashboard — shows today's assigned appointments
  with links to start checklists. Mobile-first design.
  """
  use MobileCarWashWeb, :live_view

  alias MobileCarWash.Scheduling.{Appointment, ServiceType, Dispatch}
  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Operations.TechEarnings

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
    earnings = if tech_record, do: TechEarnings.earnings_summary(tech_record), else: nil
    wash_history = if tech_record, do: TechEarnings.all_completed_washes(tech_record.id), else: []

    {:ok,
     assign(socket,
       page_title: "My Schedule",
       tech_user: tech_user,
       tech_record: tech_record,
       todays_appointments: todays,
       tomorrows_appointments: tomorrows,
       unassigned_count: length(unassigned),
       is_admin: is_admin,
       earnings: earnings,
       wash_history: wash_history,
       service_map: Ash.read!(ServiceType) |> Map.new(&{&1.id, &1}),
       customer_map: load_customer_map(todays ++ tomorrows),
       address_map: load_address_map(todays ++ tomorrows)
     )}
  end

  @impl true
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
          />
        </div>
      </div>

      <!-- Earnings Summary -->
      <div :if={@earnings} class="mb-8">
        <h2 class="text-lg font-bold mb-3">Earnings</h2>
        <div class="card bg-base-100 shadow">
          <div class="card-body p-4">
            <div class="flex justify-between items-start">
              <div>
                <p class="text-sm text-base-content/60">
                  {Calendar.strftime(@earnings.period_start, "%b %d")} – {Calendar.strftime(@earnings.period_end, "%b %d")}
                </p>
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
      </div>

      <!-- Wash History -->
      <div class="mb-8">
        <h2 class="text-lg font-bold mb-3">Completed Washes</h2>
        <div :if={@wash_history == []} class="text-base-content/50 text-sm">
          No completed washes yet
        </div>
        <div :if={@wash_history != []} class="overflow-x-auto">
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
              <tr :for={wash <- @wash_history}>
                <td class="text-sm">{Calendar.strftime(wash.date, "%b %d")}</td>
                <td class="text-sm">{wash.service_name}</td>
                <td class="text-sm">{wash.customer_name}</td>
                <td class="text-sm">
                  <span :if={wash.actual_minutes}>{wash.actual_minutes}m</span>
                  <span :if={!wash.actual_minutes}>{wash.duration_minutes}m est</span>
                </td>
                <td class="text-sm font-semibold text-success">
                  ${format_dollars(@earnings && @earnings.rate_cents || 2500)}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end

  defp format_dollars(cents) when is_integer(cents) do
    dollars = div(cents, 100)
    remainder = rem(cents, 100)
    "#{dollars}.#{String.pad_leading("#{remainder}", 2, "0")}"
  end

  defp format_dollars(_), do: "0.00"

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
      MobileCarWash.Fleet.Address |> Ash.Query.filter(id in ^ids) |> Ash.read!() |> Map.new(&{&1.id, &1})
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

  defp format_status(:pending), do: "Pending"
  defp format_status(:confirmed), do: "Confirmed"
  defp format_status(:in_progress), do: "Active"
  defp format_status(:completed), do: "Done"
  defp format_status(s), do: to_string(s)
end
