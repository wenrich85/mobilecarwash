defmodule MobileCarWashWeb.DashboardLive do
  @moduledoc """
  Subscriber home. Gated to active subscribers; non-subscribers are sent
  to the plan picker. Composes subscription status, recurring wash-days,
  and upcoming washes from existing domain reads.
  """
  use MobileCarWashWeb, :live_view

  alias MobileCarWash.Billing.{Subscription, SubscriptionPlan, SubscriptionUsage}

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
         assign(socket,
           page_title: "Your Dashboard",
           subscription: subscription,
           plan: plan,
           usage: usage
         )}
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
    </div>
    """
  end

  # --- data loading ---

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
