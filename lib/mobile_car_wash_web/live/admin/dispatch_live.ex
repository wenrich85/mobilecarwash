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

  require Ash.Query

  @refresh_interval :timer.seconds(30)

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: schedule_refresh()

    technicians = Ash.read!(Technician) |> Enum.filter(& &1.active)

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
        # Filters — default: no date filter, pending status, all techs
        filter_date: nil,
        filter_status: "pending",
        filter_tech: nil,
        show_manage_techs: false,
        service_map: load_service_map(),
        customer_map: %{}
      )
      |> load_appointments()

    {:ok, socket}
  end

  # === Event Handlers ===

  @impl true
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

    {:noreply,
     socket
     |> assign(filter_date: filter_date, filter_status: filter_status, filter_tech: filter_tech)
     |> load_appointments()}
  end

  def handle_event("clear_filters", _params, socket) do
    {:noreply,
     socket
     |> assign(filter_date: nil, filter_status: "pending", filter_tech: nil)
     |> load_appointments()}
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
          {:ok, _} ->
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

  def handle_info({:appointment_update, _data}, socket) do
    {:noreply, load_appointments(socket)}
  end

  # === Render ===

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto py-8 px-4">
      <!-- Header -->
      <div class="flex justify-between items-center mb-6">
        <div>
          <h1 class="text-3xl font-bold">Dispatch Center</h1>
          <p class="text-base-content/60">{length(@filtered_appointments)} appointments</p>
        </div>
        <.link navigate={~p"/admin/metrics"} class="btn btn-outline btn-sm">Dashboard</.link>
      </div>

      <!-- Filters -->
      <form phx-change="filter" class="flex flex-wrap gap-3 mb-6 items-end">
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
          <label class="label label-text text-xs">Status</label>
          <select name="status" class="select select-bordered select-sm">
            <option value="" selected={is_nil(@filter_status)}>All Statuses</option>
            <option value="pending" selected={@filter_status == "pending"}>Pending</option>
            <option value="confirmed" selected={@filter_status == "confirmed"}>Confirmed</option>
            <option value="in_progress" selected={@filter_status == "in_progress"}>In Progress</option>
            <option value="completed" selected={@filter_status == "completed"}>Completed</option>
          </select>
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

        <button type="button" class="btn btn-ghost btn-sm" phx-click="clear_filters">Clear</button>
      </form>

      <!-- Active Washes (always show if any) -->
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

      <!-- Filtered Appointments -->
      <div class="mb-8">
        <h2 class="text-lg font-bold mb-4">
          Appointments
        </h2>

        <div :if={@filtered_appointments == []} class="text-center py-8 text-base-content/50">
          No appointments match your filters
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          <.appointment_card
            :for={appt <- @filtered_appointments}
            appointment={appt}
            customer_name={Map.get(@customer_map, appt.customer_id, "Customer")}
            service_name={Map.get(@service_map, appt.service_type_id, "Service")}
            technicians={@technicians}
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

  # === Private ===

  defp load_appointments(socket) do
    # Build query based on filters
    query = Appointment |> Ash.Query.sort(scheduled_at: :asc)

    # Status filter
    query =
      case socket.assigns.filter_status do
        nil -> Ash.Query.filter(query, status != :cancelled)
        status_str ->
          status = String.to_existing_atom(status_str)
          Ash.Query.filter(query, status == ^status)
      end

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
        Customer |> Ash.Query.filter(id in ^customer_ids) |> Ash.read!() |> Map.new(&{&1.id, &1.name})
      else
        %{}
      end

    # Active washes (always show regardless of filters)
    active_appts = Ash.read!(Appointment, action: :active)
    active =
      Enum.map(active_appts, fn appt ->
        {appt, Dispatch.checklist_progress(appt.id)}
      end)

    # Subscribe to active PubSub
    if connected?(socket) do
      for appt <- active_appts do
        AppointmentTracker.subscribe(appt.id)
      end
    end

    assign(socket,
      all_appointments: all,
      filtered_appointments: all,
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

  defp schedule_refresh do
    Process.send_after(self(), :refresh, @refresh_interval)
  end
end
