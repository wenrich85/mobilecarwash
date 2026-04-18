defmodule MobileCarWashWeb.RecurringScheduleManageLive do
  use MobileCarWashWeb, :live_view

  alias MobileCarWash.Scheduling.{RecurringSchedule, ServiceType}
  alias MobileCarWash.Fleet.{Vehicle, Address}

  require Ash.Query

  @impl true
  def mount(_params, _session, socket) do
    customer = socket.assigns.current_customer

    {:ok,
     socket
     |> assign(
       page_title: "Recurring Schedules",
       show_form: false
     )
     |> load_data(customer.id)}
  end

  @impl true
  def handle_event("show_form", _params, socket) do
    {:noreply, assign(socket, show_form: true)}
  end

  def handle_event("cancel_form", _params, socket) do
    {:noreply, assign(socket, show_form: false)}
  end

  def handle_event("create_schedule", %{"schedule" => params}, socket) do
    customer = socket.assigns.current_customer

    case create_schedule(customer.id, params) do
      {:ok, _schedule} ->
        {:noreply,
         socket
         |> load_data(customer.id)
         |> assign(show_form: false)
         |> put_flash(:info, "Schedule created")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not create schedule")}
    end
  end

  def handle_event("pause_schedule", %{"id" => id}, socket) do
    customer = socket.assigns.current_customer

    with {:ok, schedule} <- Ash.get(RecurringSchedule, id),
         true <- schedule.customer_id == customer.id,
         {:ok, _} <- schedule |> Ash.Changeset.for_update(:deactivate, %{}) |> Ash.update() do
      {:noreply,
       socket
       |> load_data(customer.id)
       |> put_flash(:info, "Schedule paused")}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not pause schedule")}
    end
  end

  def handle_event("resume_schedule", %{"id" => id}, socket) do
    customer = socket.assigns.current_customer

    with {:ok, schedule} <- Ash.get(RecurringSchedule, id),
         true <- schedule.customer_id == customer.id,
         {:ok, _} <- schedule |> Ash.Changeset.for_update(:activate, %{}) |> Ash.update() do
      {:noreply,
       socket
       |> load_data(customer.id)
       |> put_flash(:info, "Schedule resumed")}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not resume schedule")}
    end
  end

  def handle_event("delete_schedule", %{"id" => id}, socket) do
    customer = socket.assigns.current_customer

    with {:ok, schedule} <- Ash.get(RecurringSchedule, id),
         true <- schedule.customer_id == customer.id,
         :ok <- Ash.destroy(schedule) do
      {:noreply,
       socket
       |> load_data(customer.id)
       |> put_flash(:info, "Schedule removed")}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not remove schedule")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-lg mx-auto py-8 px-4">
      <div class="flex justify-between items-center mb-6">
        <h1 class="text-2xl font-bold">Recurring Schedules</h1>
        <button :if={!@show_form} class="btn btn-primary btn-sm" phx-click="show_form">
          Add Schedule
        </button>
      </div>

      <!-- Add Schedule Form -->
      <div :if={@show_form} class="card bg-base-100 shadow mb-6">
        <div class="card-body">
          <h3 class="font-bold mb-3">New Recurring Schedule</h3>
          <form id="schedule-form" phx-submit="create_schedule">
            <div class="form-control mb-3">
              <label class="label"><span class="label-text">Service</span></label>
              <select name="schedule[service_type_id]" class="select select-bordered w-full" required>
                <option value="">Select service...</option>
                <option :for={st <- @service_types} value={st.id}>{st.name} — ${div(st.base_price_cents, 100)}</option>
              </select>
            </div>

            <div class="form-control mb-3">
              <label class="label"><span class="label-text">Vehicle</span></label>
              <select name="schedule[vehicle_id]" class="select select-bordered w-full" required>
                <option value="">Select vehicle...</option>
                <option :for={v <- @vehicles} value={v.id}>{v.year || ""} {v.make} {v.model}</option>
              </select>
            </div>

            <div class="form-control mb-3">
              <label class="label"><span class="label-text">Address</span></label>
              <select name="schedule[address_id]" class="select select-bordered w-full" required>
                <option value="">Select address...</option>
                <option :for={a <- @addresses} value={a.id}>{a.street}, {a.city}</option>
              </select>
            </div>

            <div class="form-control mb-3">
              <label class="label"><span class="label-text">Frequency</span></label>
              <select name="schedule[frequency]" class="select select-bordered w-full" required>
                <option value="weekly">Every week</option>
                <option value="biweekly">Every 2 weeks</option>
                <option value="monthly">Monthly</option>
              </select>
            </div>

            <div class="grid grid-cols-2 gap-3 mb-3">
              <div class="form-control">
                <label class="label"><span class="label-text">Day</span></label>
                <select name="schedule[preferred_day]" class="select select-bordered w-full" required>
                  <option value="1">Monday</option>
                  <option value="2">Tuesday</option>
                  <option value="3">Wednesday</option>
                  <option value="4">Thursday</option>
                  <option value="5">Friday</option>
                  <option value="6">Saturday</option>
                </select>
              </div>

              <div class="form-control">
                <label class="label"><span class="label-text">Time</span></label>
                <input type="time" name="schedule[preferred_time]" class="input input-bordered w-full" min="08:00" max="17:00" value="10:00" required />
              </div>
            </div>

            <div class="flex gap-2 mt-4">
              <button type="submit" class="btn btn-primary flex-1">Create Schedule</button>
              <button type="button" class="btn btn-ghost" phx-click="cancel_form">Cancel</button>
            </div>
          </form>
        </div>
      </div>

      <!-- Schedule List -->
      <div :if={@schedules == [] && !@show_form} class="text-center py-12">
        <p class="text-base-content/70 mb-4">No recurring schedules yet</p>
        <p class="text-sm text-base-content/70">Set up automatic bookings so you never have to think about it</p>
      </div>

      <div :for={schedule <- @schedules} class="card bg-base-100 shadow mb-4">
        <div class="card-body">
          <div class="flex justify-between items-start">
            <div>
              <h3 class="font-bold">{schedule.service_type_name}</h3>
              <p class="text-sm text-base-content/80">
                {format_frequency(schedule.frequency)} · {format_day(schedule.preferred_day)}s at {format_time(schedule.preferred_time)}
              </p>
              <p class="text-xs text-base-content/70 mt-1">
                {schedule.vehicle_label} · {schedule.address_label}
              </p>
            </div>
            <span class={["badge", if(schedule.active, do: "badge-success", else: "badge-ghost")]}>
              {if schedule.active, do: "Active", else: "Paused"}
            </span>
          </div>

          <div class="flex gap-2 mt-3">
            <button
              :if={schedule.active}
              class="btn btn-outline btn-sm"
              phx-click="pause_schedule"
              phx-value-id={schedule.id}
            >
              Pause
            </button>
            <button
              :if={!schedule.active}
              class="btn btn-success btn-sm"
              phx-click="resume_schedule"
              phx-value-id={schedule.id}
            >
              Resume
            </button>
            <button
              class="btn btn-ghost btn-sm text-error"
              phx-click="delete_schedule"
              phx-value-id={schedule.id}
              data-confirm="Remove this recurring schedule?"
            >
              Remove
            </button>
          </div>
        </div>
      </div>

      <div class="mt-6">
        <.link navigate={~p"/appointments"} class="btn btn-ghost btn-block">
          Back to Appointments
        </.link>
      </div>
    </div>
    """
  end

  defp load_data(socket, customer_id) do
    schedules =
      RecurringSchedule
      |> Ash.Query.for_read(:for_customer, %{customer_id: customer_id})
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.read!()
      |> Enum.map(fn s ->
        st = Ash.get!(ServiceType, s.service_type_id)
        v = Ash.get!(Vehicle, s.vehicle_id)
        a = Ash.get!(Address, s.address_id)

        %{
          id: s.id,
          frequency: s.frequency,
          preferred_day: s.preferred_day,
          preferred_time: s.preferred_time,
          active: s.active,
          service_type_name: st.name,
          vehicle_label: "#{v.year || ""} #{v.make} #{v.model}" |> String.trim(),
          address_label: "#{a.street}, #{a.city}"
        }
      end)

    vehicles =
      Vehicle
      |> Ash.Query.filter(customer_id == ^customer_id)
      |> Ash.read!()

    addresses =
      Address
      |> Ash.Query.filter(customer_id == ^customer_id)
      |> Ash.read!()

    service_types =
      ServiceType
      |> Ash.Query.filter(active == true)
      |> Ash.read!()

    assign(socket,
      schedules: schedules,
      vehicles: vehicles,
      addresses: addresses,
      service_types: service_types
    )
  end

  defp create_schedule(customer_id, params) do
    time =
      case Time.from_iso8601("#{params["preferred_time"]}:00") do
        {:ok, t} -> t
        _ -> ~T[10:00:00]
      end

    RecurringSchedule
    |> Ash.Changeset.for_create(:create, %{
      frequency: String.to_existing_atom(params["frequency"]),
      preferred_day: String.to_integer(params["preferred_day"]),
      preferred_time: time
    })
    |> Ash.Changeset.force_change_attribute(:customer_id, customer_id)
    |> Ash.Changeset.force_change_attribute(:vehicle_id, params["vehicle_id"])
    |> Ash.Changeset.force_change_attribute(:address_id, params["address_id"])
    |> Ash.Changeset.force_change_attribute(:service_type_id, params["service_type_id"])
    |> Ash.create()
  end

  defp format_frequency(:weekly), do: "Every week"
  defp format_frequency(:biweekly), do: "Every 2 weeks"
  defp format_frequency(:monthly), do: "Monthly"
  defp format_frequency(f), do: to_string(f)

  defp format_day(1), do: "Monday"
  defp format_day(2), do: "Tuesday"
  defp format_day(3), do: "Wednesday"
  defp format_day(4), do: "Thursday"
  defp format_day(5), do: "Friday"
  defp format_day(6), do: "Saturday"
  defp format_day(_), do: "Unknown"

  defp format_time(time) do
    Calendar.strftime(time, "%-I:%M %p")
  end
end
