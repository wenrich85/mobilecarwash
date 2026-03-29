defmodule MobileCarWashWeb.Admin.DispatchComponents do
  @moduledoc "Function components for the dispatch dashboard."
  use Phoenix.Component

  attr :appointment, :map, required: true
  attr :customer_name, :string, required: true
  attr :service_name, :string, required: true
  attr :technicians, :list, required: true

  def appointment_card(assigns) do
    ~H"""
    <div class={["card bg-base-100 shadow-sm border-l-4",
      if(is_nil(@appointment.technician_id), do: "border-warning", else: "border-primary")
    ]}>
      <div class="card-body p-4">
        <div class="flex justify-between items-start">
          <div>
            <h4 class="font-bold">{@service_name}</h4>
            <p class="text-sm text-base-content/60">{Calendar.strftime(@appointment.scheduled_at, "%b %d, %Y · %I:%M %p")}</p>
            <p class="text-sm">{@customer_name}</p>
          </div>
          <span class={["badge badge-sm", status_badge(@appointment.status)]}>
            {format_status(@appointment.status)}
          </span>
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

        <!-- Confirm Button (for pending appointments) -->
        <button
          :if={@appointment.status == :pending}
          class="btn btn-info btn-sm btn-block mt-2"
          phx-click="confirm_appointment"
          phx-value-id={@appointment.id}
        >
          Confirm Appointment
        </button>
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
    pct = if assigns.progress.steps_total > 0,
      do: Float.round(assigns.progress.steps_done / assigns.progress.steps_total * 100, 0),
      else: 0
    assigns = assign(assigns, pct: pct)

    ~H"""
    <div class="card bg-base-100 shadow border-l-4 border-success">
      <div class="card-body p-4">
        <div class="flex justify-between items-start mb-2">
          <div>
            <span class="font-bold">{@tech_name}</span>
            <span class="text-base-content/40 mx-1">·</span>
            <span>{@service_name}</span>
            <span class="text-base-content/40 mx-1">·</span>
            <span class="text-sm">{Calendar.strftime(@appointment.scheduled_at, "%I:%M %p")}</span>
          </div>
          <span class="badge badge-warning badge-sm">In Progress</span>
        </div>
        <p class="text-sm text-base-content/60">{@customer_name}</p>

        <div class="mt-3">
          <div class="flex justify-between text-xs mb-1">
            <span :if={@progress.current_step} class="font-medium text-primary">
              {_current = @progress.current_step}
            </span>
            <span>{@progress.steps_done}/{@progress.steps_total} steps</span>
          </div>
          <progress class="progress progress-primary w-full" value={@pct} max="100" />
          <p :if={@progress.eta_minutes} class="text-xs text-base-content/50 mt-1">
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
        <div :if={@appointments == []} class="text-sm text-base-content/50">No appointments</div>
        <div class="space-y-2">
          <div :for={appt <- @appointments} class="flex items-center gap-3 text-sm py-1 border-b border-base-200 last:border-0">
            <span class="font-mono text-base-content/60 w-16">
              {Calendar.strftime(appt.scheduled_at, "%I:%M %p")}
            </span>
            <span class="flex-1">{Map.get(@service_map, appt.service_type_id, "Service")}</span>
            <span class="text-base-content/60">{Map.get(@customer_map, appt.customer_id, "Customer")}</span>
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
end
