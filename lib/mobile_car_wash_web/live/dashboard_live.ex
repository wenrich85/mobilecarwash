defmodule MobileCarWashWeb.DashboardLive do
  @moduledoc """
  Subscriber home. Gated to active subscribers; non-subscribers are sent
  to the plan picker. Composes subscription status, recurring wash-days,
  and upcoming washes from existing domain reads.
  """
  use MobileCarWashWeb, :live_view

  alias MobileCarWash.Billing.{Pricing, Subscription, SubscriptionPlan, SubscriptionUsage}

  alias MobileCarWash.Scheduling.{
    AddOn,
    Appointment,
    AppointmentAddOn,
    AppointmentServices,
    RecurringSchedule,
    ServiceType
  }

  alias MobileCarWash.Fleet.Vehicle

  require Ash.Query

  @impl true
  def mount(_params, _session, socket) do
    customer = socket.assigns.current_customer

    case load_subscription(customer.id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "A subscription is required to access your dashboard.")
         |> redirect(to: ~p"/subscribe")}

      {subscription, plan, usage} ->
        {:ok,
         socket
         |> assign(
           page_title: "Your Dashboard",
           subscription: subscription,
           plan: plan,
           usage: usage,
           editing_id: nil,
           managing_addons_id: nil,
           adding_services_id: nil,
           all_add_ons:
             AddOn
             |> Ash.Query.filter(active == true)
             |> Ash.Query.sort(sort_order: :asc)
             |> Ash.read!()
         )
         |> load_schedules(customer.id)
         |> load_upcoming(customer.id)}
    end
  end

  @impl true
  def handle_event("edit_schedule", %{"id" => id}, socket) do
    {:noreply, assign(socket, editing_id: id)}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, editing_id: nil)}
  end

  def handle_event("save_preferences", %{"schedule_id" => id, "schedule" => params}, socket) do
    customer = socket.assigns.current_customer

    attrs = %{
      frequency: String.to_existing_atom(params["frequency"]),
      preferred_day: String.to_integer(params["preferred_day"]),
      preferred_time: parse_time(params["preferred_time"])
    }

    with {:ok, schedule} <- Ash.get(RecurringSchedule, id),
         true <- schedule.customer_id == customer.id,
         {:ok, _} <-
           schedule |> Ash.Changeset.for_update(:update_preferences, attrs) |> Ash.update() do
      {:noreply,
       socket
       |> assign(editing_id: nil)
       |> load_schedules(customer.id)
       |> put_flash(:info, "Schedule updated")}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not update schedule")}
    end
  end

  def handle_event("pause_schedule", %{"id" => id}, socket) do
    customer = socket.assigns.current_customer

    with {:ok, schedule} <- Ash.get(RecurringSchedule, id),
         true <- schedule.customer_id == customer.id,
         {:ok, _} <- schedule |> Ash.Changeset.for_update(:deactivate, %{}) |> Ash.update() do
      {:noreply, socket |> load_schedules(customer.id) |> put_flash(:info, "Schedule paused")}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not pause schedule")}
    end
  end

  def handle_event("resume_schedule", %{"id" => id}, socket) do
    customer = socket.assigns.current_customer

    with {:ok, schedule} <- Ash.get(RecurringSchedule, id),
         true <- schedule.customer_id == customer.id,
         {:ok, _} <- schedule |> Ash.Changeset.for_update(:activate, %{}) |> Ash.update() do
      {:noreply, socket |> load_schedules(customer.id) |> put_flash(:info, "Schedule resumed")}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not resume schedule")}
    end
  end

  def handle_event("delete_schedule", %{"id" => id}, socket) do
    customer = socket.assigns.current_customer

    with {:ok, schedule} <- Ash.get(RecurringSchedule, id),
         true <- schedule.customer_id == customer.id,
         :ok <- Ash.destroy(schedule) do
      {:noreply, socket |> load_schedules(customer.id) |> put_flash(:info, "Schedule removed")}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not remove schedule")}
    end
  end

  def handle_event("manage_addons", %{"id" => id}, socket) do
    {:noreply, assign(socket, managing_addons_id: id)}
  end

  def handle_event("cancel_addons", _params, socket) do
    {:noreply, assign(socket, managing_addons_id: nil)}
  end

  def handle_event("save_addons", %{"schedule_id" => id} = params, socket) do
    customer = socket.assigns.current_customer
    add_on_ids = Map.get(params, "add_on_ids", [])

    with {:ok, schedule} <- Ash.get(RecurringSchedule, id),
         true <- schedule.customer_id == customer.id do
      :ok = AppointmentServices.replace_schedule_add_ons(id, add_on_ids)

      {:noreply,
       socket
       |> assign(managing_addons_id: nil)
       |> load_schedules(customer.id)
       |> put_flash(:info, "Add-ons updated")}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not update add-ons")}
    end
  end

  def handle_event("manage_appt_addons", %{"id" => id}, socket) do
    {:noreply, assign(socket, adding_services_id: id)}
  end

  def handle_event("cancel_appt_addons", _params, socket) do
    {:noreply, assign(socket, adding_services_id: nil)}
  end

  def handle_event("add_services", %{"appointment_id" => id} = params, socket) do
    customer = socket.assigns.current_customer
    add_on_ids = Map.get(params, "add_on_ids", [])

    with {:ok, appt} <- Ash.get(Appointment, id),
         true <- appt.customer_id == customer.id do
      case AppointmentServices.request_add_services(appt, add_on_ids) do
        {:ok, :charged} ->
          {:noreply,
           socket
           |> assign(adding_services_id: nil)
           |> load_upcoming(customer.id)
           |> put_flash(:info, "Services added")}

        {:ok, checkout_url} when is_binary(checkout_url) ->
          {:noreply, redirect(socket, external: checkout_url)}

        {:error, :not_editable} ->
          {:noreply, put_flash(socket, :error, "This wash can no longer be modified")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not add services")}
      end
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not add services")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto py-8 px-4 space-y-6">
      <h1 class="text-2xl font-bold">Your Dashboard</h1>
      
    <!-- Panel A: Subscription summary -->
      <div class="card bg-base-100 shadow">
        <div class="card-body">
          <div class="flex justify-between items-start">
            <div>
              <h2 class="card-title">{@plan.name}</h2>
              <p class="text-2xl font-bold text-primary mt-1">${div(@plan.price_cents, 100)}/mo</p>
            </div>
            <span class={["badge badge-lg", status_badge(@subscription.status)]}>
              {format_status(@subscription.status)}
            </span>
          </div>

          <div :if={@subscription.current_period_end} class="mt-2 text-sm text-base-content/80">
            Current period ends {Calendar.strftime(@subscription.current_period_end, "%b %d, %Y")}
          </div>

          <div :if={@plan.basic_washes_per_month > 0} class="mt-4">
            <div class="flex justify-between text-sm mb-1">
              <span>Basic Washes</span>
              <span>
                {washes_remaining(@plan.basic_washes_per_month, @usage.basic_washes_used)} left
              </span>
            </div>
            <progress
              class="progress progress-primary w-full"
              value={@usage.basic_washes_used}
              max={@plan.basic_washes_per_month}
            />
          </div>

          <div :if={@plan.deep_cleans_per_month > 0} class="mt-4">
            <div class="flex justify-between text-sm mb-1">
              <span>Deep Cleans</span>
              <span>
                {washes_remaining(@plan.deep_cleans_per_month, @usage.deep_cleans_used)} left
              </span>
            </div>
            <progress
              class="progress progress-secondary w-full"
              value={@usage.deep_cleans_used}
              max={@plan.deep_cleans_per_month}
            />
          </div>

          <div class="mt-4">
            <.link navigate={~p"/account/subscription"} class="btn btn-outline btn-sm btn-block">
              Manage Subscription &amp; Billing
            </.link>
          </div>
        </div>
      </div>
      
    <!-- Panel B: Recurring wash-days -->
      <div class="card bg-base-100 shadow">
        <div class="card-body">
          <div class="flex justify-between items-center mb-2">
            <h2 class="card-title">Recurring Wash-Days</h2>
            <.link navigate={~p"/account/recurring"} class="btn btn-ghost btn-sm">Add</.link>
          </div>

          <p :if={@schedules == []} class="text-base-content/70 py-4">
            No recurring wash-days yet.
            <.link navigate={~p"/account/recurring"} class="link link-primary">Set one up</.link>
            so washes book themselves.
          </p>

          <div :for={schedule <- @schedules} class="border-t border-base-200 py-3 first:border-t-0">
            <div :if={@editing_id != schedule.id}>
              <div class="flex justify-between items-start">
                <div>
                  <p class="font-semibold">{schedule.service_type_name}</p>
                  <p class="text-sm text-base-content/80">
                    {format_frequency(schedule.frequency)} · {format_day(schedule.preferred_day)}s at {format_time(
                      schedule.preferred_time
                    )}
                  </p>
                  <p class="text-xs text-base-content/70">{schedule.vehicle_label}</p>
                  <p :if={schedule.add_ons_per_wash_cents > 0} class="text-xs text-base-content/70">
                    + ${div(schedule.add_ons_per_wash_cents, 100)} add-ons per wash
                  </p>
                </div>
                <span class={["badge", if(schedule.active, do: "badge-success", else: "badge-ghost")]}>
                  {if schedule.active, do: "Active", else: "Paused"}
                </span>
              </div>

              <div class="flex gap-2 mt-2">
                <button
                  class="btn btn-outline btn-xs"
                  phx-click="edit_schedule"
                  phx-value-id={schedule.id}
                >
                  Edit
                </button>
                <button
                  class="btn btn-outline btn-xs"
                  phx-click="manage_addons"
                  phx-value-id={schedule.id}
                >
                  Manage add-ons
                </button>
                <button
                  :if={schedule.active}
                  class="btn btn-outline btn-xs"
                  phx-click="pause_schedule"
                  phx-value-id={schedule.id}
                >
                  Pause
                </button>
                <button
                  :if={!schedule.active}
                  class="btn btn-success btn-xs"
                  phx-click="resume_schedule"
                  phx-value-id={schedule.id}
                >
                  Resume
                </button>
                <button
                  class="btn btn-ghost btn-xs text-error"
                  phx-click="delete_schedule"
                  phx-value-id={schedule.id}
                  data-confirm="Remove this recurring wash-day?"
                >
                  Remove
                </button>
              </div>
            </div>

            <form
              :if={@editing_id == schedule.id}
              id={"edit-schedule-#{schedule.id}"}
              phx-submit="save_preferences"
            >
              <input type="hidden" name="schedule_id" value={schedule.id} />
              <div class="grid grid-cols-3 gap-2">
                <select name="schedule[frequency]" class="select select-bordered select-sm">
                  <option value="weekly" selected={schedule.frequency == :weekly}>Every week</option>
                  <option value="biweekly" selected={schedule.frequency == :biweekly}>
                    Every 2 weeks
                  </option>
                  <option value="monthly" selected={schedule.frequency == :monthly}>Monthly</option>
                </select>
                <select name="schedule[preferred_day]" class="select select-bordered select-sm">
                  <option :for={d <- 1..6} value={d} selected={schedule.preferred_day == d}>
                    {format_day(d)}
                  </option>
                </select>
                <input
                  type="time"
                  name="schedule[preferred_time]"
                  class="input input-bordered input-sm"
                  min="08:00"
                  max="17:00"
                  value={Calendar.strftime(schedule.preferred_time, "%H:%M")}
                />
              </div>
              <div class="flex gap-2 mt-2">
                <button type="submit" class="btn btn-primary btn-xs">Save</button>
                <button type="button" class="btn btn-ghost btn-xs" phx-click="cancel_edit">
                  Cancel
                </button>
              </div>
            </form>

            <form
              :if={@managing_addons_id == schedule.id}
              id={"manage-addons-#{schedule.id}"}
              phx-submit="save_addons"
            >
              <input type="hidden" name="schedule_id" value={schedule.id} />
              <p class="text-sm font-medium mb-1">Add-ons (charged each future wash)</p>
              <label :for={a <- @all_add_ons} class="flex items-center gap-2 py-1">
                <input
                  type="checkbox"
                  name="add_on_ids[]"
                  value={a.id}
                  checked={a.id in schedule.add_on_ids}
                  class="checkbox checkbox-sm"
                />
                <span class="text-sm">{a.name} — ${div(a.price_cents, 100)}</span>
              </label>
              <div class="flex gap-2 mt-2">
                <button type="submit" class="btn btn-primary btn-xs">Save add-ons</button>
                <button type="button" class="btn btn-ghost btn-xs" phx-click="cancel_addons">
                  Cancel
                </button>
              </div>
            </form>
          </div>
        </div>
      </div>
      
    <!-- Panel C: Upcoming washes (read-only) -->
      <div class="card bg-base-100 shadow">
        <div class="card-body">
          <h2 class="card-title mb-2">Upcoming Washes</h2>

          <p :if={@upcoming == []} class="text-base-content/70 py-4">
            No upcoming washes. Your recurring wash-days will book automatically, or <.link
              navigate={~p"/book"}
              class="link link-primary"
            >book one now</.link>.
          </p>

          <div :for={appt <- @upcoming} class="border-t border-base-200 py-3 first:border-t-0">
            <div class="flex justify-between items-start">
              <div>
                <p class="font-semibold">{appt.service_type_name}</p>
                <p class="text-sm text-base-content/80">
                  {Calendar.strftime(appt.scheduled_at, "%a %b %-d, %-I:%M %p")}
                </p>
                <p class="text-xs text-base-content/70">
                  {appt.vehicle_label}
                  <span :if={appt.add_on_count > 0}>· {appt.add_on_count} add-on(s)</span>
                </p>
              </div>
              <div class="text-right">
                <p class="font-semibold">${div(appt.price_cents, 100)}</p>
                <span class="badge badge-ghost badge-sm">{format_status(appt.status)}</span>
              </div>
            </div>

            <div class="mt-2">
              <button
                :if={appt.editable && @adding_services_id != appt.id}
                class="btn btn-outline btn-xs"
                phx-click="manage_appt_addons"
                phx-value-id={appt.id}
              >
                Add services
              </button>

              <p :if={!appt.editable} class="text-xs text-base-content/60 italic">
                Too late to modify
              </p>

              <form
                :if={appt.editable && @adding_services_id == appt.id}
                id={"add-services-#{appt.id}"}
                phx-submit="add_services"
              >
                <input type="hidden" name="appointment_id" value={appt.id} />
                <p class="text-sm font-medium mb-1">Add services (charged now)</p>
                <label :for={a <- @all_add_ons} class="flex items-center gap-2 py-1">
                  <input
                    type="checkbox"
                    name="add_on_ids[]"
                    value={a.id}
                    class="checkbox checkbox-sm"
                  />
                  <span class="text-sm">{a.name} — ${div(a.price_cents, 100)}</span>
                </label>
                <div class="flex gap-2 mt-2">
                  <button type="submit" class="btn btn-primary btn-xs">Add &amp; pay</button>
                  <button type="button" class="btn btn-ghost btn-xs" phx-click="cancel_appt_addons">
                    Cancel
                  </button>
                </div>
              </form>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # --- data loading ---

  defp load_schedules(socket, customer_id) do
    schedules =
      RecurringSchedule
      |> Ash.Query.for_read(:for_customer, %{customer_id: customer_id})
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.read!()
      |> Enum.map(fn s ->
        st = Ash.get!(ServiceType, s.service_type_id)
        v = Ash.get!(Vehicle, s.vehicle_id)

        add_on_ids = AppointmentServices.schedule_add_on_ids(s.id)
        add_ons = AppointmentServices.schedule_add_ons(s.id)
        per_wash = Pricing.addons_total_cents(add_ons, v.size)

        %{
          id: s.id,
          frequency: s.frequency,
          preferred_day: s.preferred_day,
          preferred_time: s.preferred_time,
          active: s.active,
          service_type_name: st.name,
          vehicle_label: "#{v.year || ""} #{v.make} #{v.model}" |> String.trim(),
          add_on_ids: add_on_ids,
          add_ons_per_wash_cents: per_wash
        }
      end)

    assign(socket, schedules: schedules)
  end

  defp load_upcoming(socket, customer_id) do
    upcoming =
      Appointment
      |> Ash.Query.for_read(:upcoming, %{customer_id: customer_id})
      |> Ash.Query.sort(scheduled_at: :asc)
      |> Ash.read!()
      |> Enum.map(fn a ->
        st = Ash.get!(ServiceType, a.service_type_id)
        v = Ash.get!(Vehicle, a.vehicle_id)

        add_on_count =
          AppointmentAddOn
          |> Ash.Query.filter(appointment_id == ^a.id)
          |> Ash.read!()
          |> length()

        %{
          id: a.id,
          scheduled_at: a.scheduled_at,
          status: a.status,
          price_cents: a.price_cents,
          service_type_name: st.name,
          vehicle_label: "#{v.year || ""} #{v.make} #{v.model}" |> String.trim(),
          add_on_count: add_on_count,
          editable: AppointmentServices.editable?(a)
        }
      end)

    assign(socket, upcoming: upcoming)
  end

  defp load_subscription(customer_id) do
    subscription =
      Subscription
      |> Ash.Query.for_read(:active_for_customer, %{customer_id: customer_id})
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.read!()
      |> List.first()

    case subscription do
      nil ->
        nil

      sub ->
        plan = Ash.get!(SubscriptionPlan, sub.plan_id)
        today = Date.utc_today()

        usage =
          SubscriptionUsage
          |> Ash.Query.filter(
            subscription_id == ^sub.id and
              period_start <= ^today and
              period_end >= ^today
          )
          |> Ash.read!()
          |> List.first()

        usage = usage || %{basic_washes_used: 0, deep_cleans_used: 0}
        {sub, plan, usage}
    end
  end

  # --- formatting helpers ---

  defp parse_time(value) do
    case Time.from_iso8601("#{value}:00") do
      {:ok, t} -> t
      _ -> ~T[10:00:00]
    end
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
  defp format_day(7), do: "Sunday"
  defp format_day(_), do: "Unknown"

  defp format_time(time), do: Calendar.strftime(time, "%-I:%M %p")

  defp washes_remaining(allowance, used), do: max(allowance - used, 0)

  defp status_badge(:active), do: "badge-success"
  defp status_badge(:paused), do: "badge-warning"
  defp status_badge(:past_due), do: "badge-error"
  defp status_badge(_), do: "badge-ghost"

  defp format_status(:active), do: "Active"
  defp format_status(:paused), do: "Paused"
  defp format_status(:past_due), do: "Past Due"
  defp format_status(:pending), do: "Pending"
  defp format_status(:confirmed), do: "Confirmed"
  defp format_status(s), do: to_string(s)
end
