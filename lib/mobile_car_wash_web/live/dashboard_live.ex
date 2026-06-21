defmodule MobileCarWashWeb.DashboardLive do
  @moduledoc """
  Subscriber home. Gated to active subscribers; non-subscribers are sent
  to the plan picker. Composes subscription status, recurring wash-days,
  and upcoming washes from existing domain reads.
  """
  use MobileCarWashWeb, :live_view

  alias MobileCarWash.Billing.{Subscription, SubscriptionPlan, SubscriptionUsage}
  alias MobileCarWash.Scheduling.{RecurringSchedule, ServiceType}
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
           editing_id: nil
         )
         |> load_schedules(customer.id)}
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
      {:noreply,
       socket |> load_schedules(customer.id) |> put_flash(:info, "Schedule paused")}
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
       socket |> load_schedules(customer.id) |> put_flash(:info, "Schedule resumed")}
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
       socket |> load_schedules(customer.id) |> put_flash(:info, "Schedule removed")}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not remove schedule")}
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
              <span>{washes_remaining(@plan.basic_washes_per_month, @usage.basic_washes_used)} left</span>
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
              <span>{washes_remaining(@plan.deep_cleans_per_month, @usage.deep_cleans_used)} left</span>
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
                </div>
                <span class={["badge", if(schedule.active, do: "badge-success", else: "badge-ghost")]}>
                  {if schedule.active, do: "Active", else: "Paused"}
                </span>
              </div>

              <div class="flex gap-2 mt-2">
                <button class="btn btn-outline btn-xs" phx-click="edit_schedule" phx-value-id={schedule.id}>
                  Edit
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
                  <option value="biweekly" selected={schedule.frequency == :biweekly}>Every 2 weeks</option>
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
                <button type="button" class="btn btn-ghost btn-xs" phx-click="cancel_edit">Cancel</button>
              </div>
            </form>
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

        %{
          id: s.id,
          frequency: s.frequency,
          preferred_day: s.preferred_day,
          preferred_time: s.preferred_time,
          active: s.active,
          service_type_name: st.name,
          vehicle_label: "#{v.year || ""} #{v.make} #{v.model}" |> String.trim()
        }
      end)

    assign(socket, schedules: schedules)
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
  defp format_status(s), do: to_string(s)
end
