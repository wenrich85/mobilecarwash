defmodule MobileCarWashWeb.Admin.DispatchComponents do
  @moduledoc "Function components for the dispatch dashboard."
  use Phoenix.Component

  import MobileCarWashWeb.CoreComponents, only: [icon: 1]

  attr :metrics, :map, required: true
  attr :filter_date, :any, default: nil

  def command_bar(assigns) do
    assigns = assign(assigns, :display_date, display_date(assigns.filter_date))

    ~H"""
    <section id="dispatch-command-bar" class="rounded-lg border border-base-300 bg-base-100 shadow-sm">
      <div class="flex flex-col gap-4 p-5 lg:flex-row lg:items-center lg:justify-between">
        <div>
          <p class="text-xs font-bold uppercase tracking-widest text-primary">Today / Live Ops</p>
          <h1 class="text-3xl font-black text-base-content md:text-4xl">Dispatch Center</h1>
          <p class="text-sm text-base-content/70">
            Live service monitoring and assignment control for {@display_date}
          </p>
        </div>
        <div class="flex flex-wrap gap-2">
          <span class="badge badge-info gap-1 px-3 py-3">
            <.icon name="hero-signal" class="size-4" /> Live
          </span>
          <span class="badge badge-success px-3 py-3">{@metrics.on_duty} on duty</span>
          <span class={[
            "badge px-3 py-3",
            if(@metrics.exceptions > 0, do: "badge-warning", else: "badge-ghost")
          ]}>
            {@metrics.exceptions} need action
          </span>
          <MobileCarWashWeb.Layouts.theme_toggle />
        </div>
      </div>
    </section>
    """
  end

  attr :metrics, :map, required: true

  def metric_cards(assigns) do
    ~H"""
    <section id="dispatch-metrics" class="grid grid-cols-2 gap-3 lg:grid-cols-4">
      <.metric_card label="In progress" value={@metrics.in_progress} tone="bg-sky-500 text-white" />
      <.metric_card
        label="Ready to assign"
        value={@metrics.ready_to_assign}
        tone="bg-blue-50 text-blue-700 dark:bg-blue-950 dark:text-blue-200"
      />
      <.metric_card
        label="Completed"
        value={@metrics.completed}
        tone="bg-emerald-50 text-emerald-700 dark:bg-emerald-950 dark:text-emerald-200"
      />
      <.metric_card
        label="Exceptions"
        value={@metrics.exceptions}
        tone="bg-orange-50 text-orange-700 dark:bg-orange-950 dark:text-orange-200"
      />
    </section>
    """
  end

  attr :label, :string, required: true
  attr :value, :integer, required: true
  attr :tone, :string, required: true

  defp metric_card(assigns) do
    ~H"""
    <div class={[
      "rounded-lg border border-base-300 p-4 shadow-sm transition hover:-translate-y-0.5",
      @tone
    ]}>
      <p class="text-xs font-bold uppercase tracking-widest opacity-75">{@label}</p>
      <p class="mt-2 text-4xl font-black">{@value}</p>
    </div>
    """
  end

  attr :exceptions, :list, required: true
  attr :customer_map, :map, required: true
  attr :service_map, :map, required: true
  attr :appointments_by_id, :map, required: true

  def exception_panel(assigns) do
    ~H"""
    <section
      id="dispatch-exceptions"
      class="rounded-lg border border-base-300 bg-base-100 p-4 shadow-sm"
    >
      <div class="mb-3 flex items-center justify-between">
        <h2 class="text-lg font-black">Needs Action</h2>
        <span class="badge badge-warning">{length(@exceptions)}</span>
      </div>
      <div :if={@exceptions == []} class="rounded-lg bg-base-200 p-4 text-sm text-base-content/70">
        No dispatch exceptions right now.
      </div>
      <div class="space-y-3">
        <div
          :for={item <- @exceptions}
          id={"dispatch-exception-#{item.appointment_id}-#{item.kind}"}
          class="rounded-lg border border-warning/30 bg-warning/10 p-3"
        >
          <% appt = Map.get(@appointments_by_id, item.appointment_id) %>
          <p class="text-sm font-bold">{item.reason}</p>
          <p class="text-xs text-base-content/70">
            {appt && Map.get(@service_map, appt.service_type_id, "Service")} · {Map.get(
              @customer_map,
              item.customer_id,
              "Customer"
            )}
          </p>
          <p class="mt-2 text-xs font-semibold text-warning">{item.action}</p>
        </div>
      </div>
    </section>
    """
  end

  attr :appointments, :list, required: true
  attr :customer_map, :map, required: true
  attr :service_map, :map, required: true
  attr :technicians, :list, required: true
  attr :address_map, :map, required: true
  attr :vehicle_map, :map, required: true
  attr :tech_requests, :map, required: true
  attr :flagged_customer_ids, :any, required: true

  def assignment_queue(assigns) do
    ~H"""
    <section
      id="dispatch-assignment-queue"
      class="rounded-lg border border-base-300 bg-base-100 p-4 shadow-sm"
    >
      <div class="mb-4 flex items-center justify-between">
        <h2 class="text-xl font-black">Assignment Queue</h2>
        <span class="badge badge-info">{length(@appointments)}</span>
      </div>
      <div :if={@appointments == []} class="rounded-lg bg-base-200 p-4 text-sm text-base-content/70">
        No jobs waiting for assignment.
      </div>
      <div class="grid gap-3">
        <.appointment_card
          :for={appt <- @appointments}
          appointment={appt}
          customer_name={Map.get(@customer_map, appt.customer_id, "Customer")}
          service_name={Map.get(@service_map, appt.service_type_id, "Service")}
          technicians={@technicians}
          address_zone={get_address_zone(appt, @address_map)}
          vehicle={Map.get(@vehicle_map, appt.vehicle_id)}
          requested_by={Map.get(@tech_requests, appt.id)}
          booking_flagged?={MapSet.member?(@flagged_customer_ids, appt.customer_id)}
        />
      </div>
    </section>
    """
  end

  attr :workloads, :list, required: true

  def technician_workload_rail(assigns) do
    ~H"""
    <section
      id="dispatch-technician-workload"
      class="rounded-lg border border-base-300 bg-base-100 p-4 shadow-sm"
    >
      <h2 class="mb-4 text-lg font-black">Technician Workload</h2>
      <div class="space-y-3">
        <div
          :for={tech <- @workloads}
          id={"dispatch-tech-workload-#{tech.id}"}
          class="rounded-lg border border-base-300 bg-base-200/60 p-3"
        >
          <div class="flex items-center justify-between gap-3">
            <div>
              <p class="font-bold">{tech.name}</p>
              <% activity = workload_activity_text(tech.current) %>
              <p :if={activity} class="text-xs font-medium text-primary">{activity}</p>
              <p class="text-xs text-base-content/70">
                {duty_status_label(tech.status)} · {tech.assigned_count} assigned
              </p>
            </div>
            <span class={["badge badge-sm", workload_badge(tech.pressure)]}>{tech.pressure}</span>
          </div>
        </div>
      </div>
    </section>
    """
  end

  attr :appointment, :map, required: true
  attr :customer_name, :string, required: true
  attr :service_name, :string, required: true
  attr :technicians, :list, required: true
  attr :address_zone, :atom, default: nil
  attr :requested_by, :map, default: nil
  attr :vehicle, :map, default: nil
  attr :booking_flagged?, :boolean, default: false

  def appointment_card(assigns) do
    ~H"""
    <div class={[
      "card bg-base-100 shadow-sm border-l-4",
      cond do
        @booking_flagged? -> "border-error"
        @requested_by -> "border-info"
        is_nil(@appointment.technician_id) -> "border-warning"
        true -> "border-primary"
      end
    ]}>
      <div
        :if={@booking_flagged?}
        class="booking-flag flex items-center gap-1 text-xs bg-error/10 text-error rounded px-2 py-1"
      >
        <span class="hero-exclamation-triangle-micro size-3 shrink-0"></span>
        <span class="font-semibold">Booking flag — check customer record</span>
      </div>
      <div class="card-body p-4">
        <!-- Tech request banner -->
        <div
          :if={@requested_by}
          class="flex items-center gap-2 text-xs bg-info/10 text-info rounded px-2 py-1 mb-2 -mt-1"
        >
          <span class="font-semibold">{@requested_by.technician_name}</span>
          <span>requested this appointment</span>
        </div>

        <div class="flex justify-between items-start">
          <div>
            <h4 class="font-bold">{@service_name}</h4>
            <p class="text-sm text-base-content/80">
              {Calendar.strftime(@appointment.scheduled_at, "%b %d, %Y · %I:%M %p")}
            </p>
            <p class="text-sm">{@customer_name}</p>
            <p :if={@vehicle} class="text-xs text-base-content/70">
              {vehicle_label(@vehicle)}
            </p>
          </div>
          <div class="flex gap-1">
            <span
              :if={@address_zone}
              class={["badge badge-sm", MobileCarWash.Zones.badge_class(@address_zone)]}
            >
              {MobileCarWash.Zones.short_label(@address_zone)}
            </span>
            <span class={["badge badge-sm", status_badge(@appointment.status)]}>
              {format_status(@appointment.status)}
            </span>
          </div>
        </div>
        
    <!-- Assign Technician -->
        <form phx-change="assign_tech" class="mt-2">
          <input type="hidden" name="appointment-id" value={@appointment.id} />
          <select
            class="select select-bordered select-sm w-full"
            name="technician_id"
          >
            <option value="">— Assign Technician —</option>
            <option
              :for={tech <- @technicians}
              value={tech.id}
              selected={@appointment.technician_id == tech.id}
            >
              {tech.name}
            </option>
          </select>
        </form>
        
    <!-- Confirm Button (for pending appointments with assigned tech) -->
        <button
          :if={@appointment.status == :pending && @appointment.technician_id}
          class="btn btn-info btn-sm btn-block mt-2"
          phx-click="confirm_appointment"
          phx-value-id={@appointment.id}
        >
          Confirm Appointment
        </button>
        <p
          :if={@appointment.status == :pending && is_nil(@appointment.technician_id)}
          class="text-xs text-warning mt-2 text-center"
        >
          Assign a technician to confirm
        </p>
      </div>
    </div>
    """
  end

  attr :appointment, :map, required: true
  attr :customer_name, :string, required: true
  attr :service_name, :string, required: true
  attr :tech_name, :string, required: true
  attr :progress, :map, required: true

  def active_wash_card(assigns) do
    pct =
      if assigns.progress.steps_total > 0,
        do: Float.round(assigns.progress.steps_done / assigns.progress.steps_total * 100, 0),
        else: 0

    assigns = assign(assigns, pct: pct)

    ~H"""
    <div class="card bg-base-100 shadow border-l-4 border-success">
      <div class="card-body p-4">
        <div class="flex justify-between items-start mb-2">
          <div>
            <span class="font-bold">{@tech_name}</span>
            <span class="text-base-content/70 mx-1">·</span>
            <span>{@service_name}</span>
            <span class="text-base-content/70 mx-1">·</span>
            <span class="text-sm">{Calendar.strftime(@appointment.scheduled_at, "%I:%M %p")}</span>
          </div>
          <span class="badge badge-warning badge-sm">In Progress</span>
        </div>
        <p class="text-sm text-base-content/80">{@customer_name}</p>

        <div class="mt-3">
          <div class="flex justify-between text-xs mb-1">
            <span :if={@progress.current_step} class="font-medium text-primary">
              {_current = @progress.current_step}
            </span>
            <span>{@progress.steps_done}/{@progress.steps_total} steps</span>
          </div>
          <progress class="progress progress-primary w-full" value={@pct} max="100" />
          <p :if={@progress.eta_minutes} class="text-xs text-base-content/70 mt-1">
            ETA: ~{@progress.eta_minutes} min remaining
          </p>
        </div>
      </div>
    </div>
    """
  end

  attr :tech_name, :string, required: true
  attr :appointments, :list, required: true
  attr :service_map, :map, required: true
  attr :customer_map, :map, required: true

  def technician_schedule(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow mb-4">
      <div class="card-body p-4">
        <h3 class="font-bold text-lg mb-3">{@tech_name}</h3>
        <div :if={@appointments == []} class="text-sm text-base-content/70">No appointments</div>
        <div class="space-y-2">
          <div
            :for={appt <- @appointments}
            class="flex items-center gap-3 text-sm py-1 border-b border-base-200 last:border-0"
          >
            <span class="font-mono text-base-content/80 w-16">
              {Calendar.strftime(appt.scheduled_at, "%I:%M %p")}
            </span>
            <span class="flex-1">{Map.get(@service_map, appt.service_type_id, "Service")}</span>
            <span class="text-base-content/80">
              {Map.get(@customer_map, appt.customer_id, "Customer")}
            </span>
            <span class={["badge badge-xs", status_badge(appt.status)]}>
              {format_status(appt.status)}
            </span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp status_badge(:pending), do: "badge-ghost"
  defp status_badge(:confirmed), do: "badge-info"
  defp status_badge(:in_progress), do: "badge-warning"
  defp status_badge(:completed), do: "badge-success"
  defp status_badge(:cancelled), do: "badge-error"
  defp status_badge(_), do: "badge-ghost"

  defp format_status(:pending), do: "Pending"
  defp format_status(:confirmed), do: "Confirmed"
  defp format_status(:in_progress), do: "Active"
  defp format_status(:completed), do: "Done"
  defp format_status(:cancelled), do: "Cancelled"
  defp format_status(s), do: to_string(s)

  attr :title, :string, required: true
  attr :status, :atom, required: true
  attr :appointments, :list, required: true
  attr :count, :integer, required: true
  attr :badge_color, :string, required: true
  attr :technicians, :list, required: true
  attr :customer_map, :map, required: true
  attr :service_map, :map, required: true
  attr :address_map, :map, required: true
  attr :vehicle_map, :map, required: true
  attr :tech_requests, :map, required: true
  attr :flagged_customer_ids, :any, default: nil

  def kanban_column(assigns) do
    assigns =
      assign_new(assigns, :flagged_customer_ids, fn -> MapSet.new() end)

    ~H"""
    <div class="bg-base-100 rounded-lg shadow-sm p-4 flex flex-col h-full">
      <!-- Column Header -->
      <div class="flex items-center justify-between gap-2 mb-4">
        <h3 class="font-bold text-lg">{@title}</h3>
        <span class={["badge", @badge_color]}>{@count}</span>
      </div>
      
    <!-- Appointments List -->
      <div class="space-y-3 flex-1 overflow-y-auto">
        <div :if={@appointments == []} class="text-sm text-base-content/70 text-center py-8">
          No appointments
        </div>
        <.appointment_card
          :for={appt <- @appointments}
          appointment={appt}
          customer_name={Map.get(@customer_map, appt.customer_id, "Customer")}
          service_name={Map.get(@service_map, appt.service_type_id, "Service")}
          technicians={@technicians}
          address_zone={get_address_zone(appt, @address_map)}
          vehicle={Map.get(@vehicle_map, appt.vehicle_id)}
          requested_by={Map.get(@tech_requests, appt.id)}
          booking_flagged?={MapSet.member?(@flagged_customer_ids, appt.customer_id)}
        />
      </div>
    </div>
    """
  end

  defp get_address_zone(appointment, address_map) do
    case Map.get(address_map, appointment.address_id) do
      %{zone: zone} -> zone
      _ -> nil
    end
  end

  defp display_date(nil), do: "all scheduled jobs"
  defp display_date(%Date{} = date), do: Calendar.strftime(date, "%b %d, %Y")

  defp duty_status_label(:available), do: "Available"
  defp duty_status_label(:on_break), do: "On break"
  defp duty_status_label(:off_duty), do: "Off duty"
  defp duty_status_label(status), do: format_status(status)

  defp workload_activity_text(nil), do: nil

  defp workload_activity_text(%{status: status, customer_name: name, scheduled_at: at}) do
    time = Calendar.strftime(at, "%-I:%M %p")

    case status do
      :en_route -> "En route to #{name} · #{time}"
      :on_site -> "On site with #{name}"
      :in_progress -> "Washing #{name}'s car"
      _ -> nil
    end
  end

  defp workload_activity_text(_), do: nil

  defp workload_badge(:high), do: "badge-warning"
  defp workload_badge(:medium), do: "badge-info"
  defp workload_badge(_), do: "badge-ghost"

  defp vehicle_label(%{make: make, model: model, size: size}) do
    type =
      case size do
        :car -> "Car"
        :suv_van -> "SUV/Van"
        :pickup -> "Pickup"
        _ -> ""
      end

    parts = [make, model, type] |> Enum.reject(&(is_nil(&1) or &1 == ""))
    Enum.join(parts, " · ")
  end

  defp vehicle_label(_), do: nil
end
