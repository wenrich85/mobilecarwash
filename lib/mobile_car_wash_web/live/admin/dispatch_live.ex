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

    # Load technician-role users for linking dropdown
    tech_users =
      Customer
      |> Ash.Query.filter(role in [:technician, :admin])
      |> Ash.read!()

    socket =
      socket
      |> assign(
        page_title: "Dispatch Center",
        technicians: technicians,
        tech_users: tech_users,
        selected_date: date,
        show_manage_techs: false,
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
    {:noreply, socket |> assign(technicians: technicians) |> put_flash(:info, "Technician account updated")}
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
        {:noreply, socket |> assign(technicians: technicians) |> put_flash(:info, "Pay rate updated")}

      _ ->
        {:noreply, put_flash(socket, :error, "Invalid rate")}
    end
  end

  def handle_event("add_technician", %{"name" => name, "phone" => phone}, socket) do
    case Technician |> Ash.Changeset.for_create(:create, %{name: name, phone: phone}) |> Ash.create() do
      {:ok, _tech} ->
        technicians = Ash.read!(Technician) |> Enum.filter(& &1.active)
        {:noreply, socket |> assign(technicians: technicians) |> put_flash(:info, "Technician #{name} added")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not add technician")}
    end
  end

  def handle_event("change_date", %{"date" => date_str}, socket) do
    case Date.from_iso8601(date_str) do
      {:ok, date} ->
        {:noreply, socket |> assign(selected_date: date) |> load_appointments()}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("confirm_appointment", %{"id" => id}, socket) do
    case Ash.get(MobileCarWash.Scheduling.Appointment, id) do
      {:ok, appt} ->
        case appt |> Ash.Changeset.for_update(:confirm, %{}) |> Ash.update() do
          {:ok, _} ->
            {:noreply, socket |> load_appointments() |> put_flash(:info, "Appointment confirmed")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Could not confirm appointment")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Appointment not found")}
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

      <!-- Pending / Needs Action -->
      <div :if={@needs_action != []} class="mb-8">
        <h2 class="text-lg font-bold mb-4 flex items-center gap-2">
          <span class="badge badge-warning">{length(@needs_action)}</span>
          Needs Action
          <span class="text-sm font-normal text-base-content/50">(pending or unassigned)</span>
        </h2>
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          <.appointment_card
            :for={appt <- @needs_action}
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

      <!-- Manage Technicians -->
      <div class="mb-8">
        <button class="btn btn-ghost btn-sm mb-4" phx-click="toggle_manage_techs">
          {if @show_manage_techs, do: "Hide", else: "Manage"} Technicians
        </button>

        <div :if={@show_manage_techs}>
          <!-- Add New Technician -->
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

          <!-- Existing Technicians -->
          <div class="overflow-x-auto">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>Name</th>
                  <th>Linked Account</th>
                  <th>Pay Rate</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={tech <- @technicians}>
                  <td class="font-semibold">{tech.name}</td>
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
    needs_action = Enum.filter(all, fn appt ->
      appt.status == :pending or is_nil(appt.technician_id)
    end)
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
      needs_action: needs_action,
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
