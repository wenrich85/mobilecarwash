defmodule MobileCarWashWeb.SubscriptionManageLive do
  @moduledoc """
  Customer subscription management page.
  Shows current plan, usage, period, and actions (pause/resume/cancel).
  """
  use MobileCarWashWeb, :live_view

  alias MobileCarWash.Billing.{Subscription, SubscriptionUsage, StripeClient}

  require Ash.Query

  @impl true
  def mount(_params, _session, socket) do
    customer = socket.assigns.current_customer
    {subscription, plan, usage} = load_subscription(customer.id)

    {:ok,
     assign(socket,
       page_title: "My Plan",
       subscription: subscription,
       plan: plan,
       usage: usage,
       show_cancel_confirm: false
     )}
  end

  @impl true
  def handle_event("pause", _params, socket) do
    case socket.assigns.subscription |> Ash.Changeset.for_update(:pause, %{}) |> Ash.update() do
      {:ok, sub} ->
        {:noreply,
         socket
         |> assign(subscription: sub)
         |> put_flash(:info, "Subscription paused")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not pause subscription")}
    end
  end

  def handle_event("resume", _params, socket) do
    case socket.assigns.subscription |> Ash.Changeset.for_update(:resume, %{}) |> Ash.update() do
      {:ok, sub} ->
        {:noreply,
         socket
         |> assign(subscription: sub)
         |> put_flash(:info, "Subscription resumed")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not resume subscription")}
    end
  end

  def handle_event("show_cancel", _params, socket) do
    {:noreply, assign(socket, show_cancel_confirm: true)}
  end

  def handle_event("dismiss_cancel", _params, socket) do
    {:noreply, assign(socket, show_cancel_confirm: false)}
  end

  def handle_event("confirm_cancel", _params, socket) do
    case socket.assigns.subscription |> Ash.Changeset.for_update(:cancel, %{}) |> Ash.update() do
      {:ok, sub} ->
        {:noreply,
         socket
         |> assign(subscription: sub, show_cancel_confirm: false)
         |> put_flash(:info, "Subscription cancelled. You can resubscribe anytime.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not cancel subscription")}
    end
  end

  def handle_event("manage_payment", _params, socket) do
    customer = socket.assigns.current_customer
    base_url = Application.get_env(:mobile_car_wash, :base_url, "http://localhost:4000")

    case customer.stripe_customer_id do
      nil ->
        {:noreply, put_flash(socket, :error, "No payment method on file")}

      stripe_id ->
        case StripeClient.create_billing_portal_session(stripe_id, "#{base_url}/account/subscription") do
          {:ok, session} ->
            {:noreply, redirect(socket, external: session.url)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Could not open payment settings")}
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-lg mx-auto py-8 px-4">
      <h1 class="text-2xl font-bold mb-6">My Plan</h1>

      <!-- No Subscription -->
      <div :if={is_nil(@subscription)} class="text-center py-12">
        <p class="text-base-content/50 mb-4">You don't have an active subscription</p>
        <.link navigate={~p"/subscribe"} class="btn btn-primary">
          View Plans
        </.link>
      </div>

      <!-- Active Subscription -->
      <div :if={@subscription}>
        <!-- Plan Card -->
        <div class="card bg-base-100 shadow mb-6">
          <div class="card-body">
            <div class="flex justify-between items-start">
              <div>
                <h2 class="card-title">{@plan.name} Plan</h2>
                <p class="text-2xl font-bold text-primary mt-1">${div(@plan.price_cents, 100)}/mo</p>
              </div>
              <span class={["badge badge-lg", status_badge(@subscription.status)]}>
                {format_status(@subscription.status)}
              </span>
            </div>

            <!-- Period -->
            <div class="mt-4 text-sm text-base-content/60">
              <span :if={@subscription.current_period_start && @subscription.current_period_end}>
                Current period: {Calendar.strftime(@subscription.current_period_start, "%b %d")} –
                {Calendar.strftime(@subscription.current_period_end, "%b %d, %Y")}
              </span>
            </div>
          </div>
        </div>

        <!-- Usage Card -->
        <div :if={@usage} class="card bg-base-100 shadow mb-6">
          <div class="card-body">
            <h3 class="font-bold mb-3">This Period's Usage</h3>

            <div :if={@plan.basic_washes_per_month > 0} class="mb-4">
              <div class="flex justify-between text-sm mb-1">
                <span>Basic Washes</span>
                <span>{@usage.basic_washes_used}/{@plan.basic_washes_per_month}</span>
              </div>
              <progress
                class="progress progress-primary w-full"
                value={@usage.basic_washes_used}
                max={@plan.basic_washes_per_month}
              />
            </div>

            <div :if={@plan.deep_cleans_per_month > 0} class="mb-4">
              <div class="flex justify-between text-sm mb-1">
                <span>Deep Cleans</span>
                <span>{@usage.deep_cleans_used}/{@plan.deep_cleans_per_month}</span>
              </div>
              <progress
                class="progress progress-secondary w-full"
                value={@usage.deep_cleans_used}
                max={@plan.deep_cleans_per_month}
              />
            </div>

            <div :if={@plan.deep_clean_discount_percent > 0} class="text-sm text-base-content/60">
              {@plan.deep_clean_discount_percent}% off additional deep cleans
            </div>
          </div>
        </div>

        <!-- Actions -->
        <div class="space-y-3">
          <.link navigate={~p"/book"} class="btn btn-primary btn-block">
            Book a Wash
          </.link>

          <button
            :if={@subscription.status == :active}
            class="btn btn-outline btn-block"
            phx-click="pause"
          >
            Pause Subscription
          </button>

          <button
            :if={@subscription.status == :paused}
            class="btn btn-success btn-block"
            phx-click="resume"
          >
            Resume Subscription
          </button>

          <button
            :if={@subscription.stripe_subscription_id}
            class="btn btn-outline btn-block"
            phx-click="manage_payment"
          >
            Manage Payment Method
          </button>

          <button
            :if={@subscription.status in [:active, :paused]}
            class="btn btn-ghost btn-block text-error"
            phx-click="show_cancel"
          >
            Cancel Subscription
          </button>
        </div>

        <!-- Cancel Confirmation -->
        <div :if={@show_cancel_confirm} class="modal modal-open">
          <div class="modal-box">
            <h3 class="font-bold text-lg">Cancel Subscription?</h3>
            <p class="py-4">
              Are you sure? You'll lose access to your plan benefits at the end of the current period.
              You can always resubscribe later.
            </p>
            <div class="modal-action">
              <button class="btn btn-ghost" phx-click="dismiss_cancel">Keep Plan</button>
              <button class="btn btn-error" phx-click="confirm_cancel">Yes, Cancel</button>
            </div>
          </div>
          <div class="modal-backdrop" phx-click="dismiss_cancel"></div>
        </div>
      </div>
    </div>
    """
  end

  defp load_subscription(customer_id) do
    subscription =
      Subscription
      |> Ash.Query.filter(customer_id == ^customer_id and status in [:active, :paused, :past_due])
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.read!()
      |> List.first()

    case subscription do
      nil ->
        {nil, nil, nil}

      sub ->
        plan = Ash.get!(MobileCarWash.Billing.SubscriptionPlan, sub.plan_id)
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

        # Fallback usage if none exists yet
        usage = usage || %{basic_washes_used: 0, deep_cleans_used: 0}

        {sub, plan, usage}
    end
  end

  defp status_badge(:active), do: "badge-success"
  defp status_badge(:paused), do: "badge-warning"
  defp status_badge(:past_due), do: "badge-error"
  defp status_badge(:cancelled), do: "badge-ghost"
  defp status_badge(_), do: "badge-ghost"

  defp format_status(:active), do: "Active"
  defp format_status(:paused), do: "Paused"
  defp format_status(:past_due), do: "Past Due"
  defp format_status(:cancelled), do: "Cancelled"
  defp format_status(s), do: to_string(s)
end
