defmodule MobileCarWashWeb.SubscriptionLive do
  @moduledoc """
  Multi-step subscription signup wizard driven by SubscriptionStateMachine.
  Steps: select_plan → auth → review → checkout (Stripe redirect).
  """
  use MobileCarWashWeb, :live_view

  alias MobileCarWash.Billing.{SubscriptionPlan, SubscriptionStateMachine, StripeClient}

  require Ash.Query

  @impl true
  def mount(_params, _session, socket) do
    plans =
      SubscriptionPlan
      |> Ash.Query.filter(active == true)
      |> Ash.read!()
      |> Enum.sort_by(& &1.price_cents)

    customer = socket.assigns[:current_customer]

    if connected?(socket), do: MobileCarWash.CatalogBroadcaster.subscribe()

    {:ok,
     assign(socket,
       page_title: "Monthly Detailing Plans",
       meta_description: "Save with a monthly car wash subscription. Plans from $90/mo include basic washes and deep clean discounts. Cancel anytime. Veteran-owned.",
       meta_keywords: "car wash subscription, monthly car wash plan, car wash membership, auto detailing subscription, unlimited car wash, car wash savings plan",
       canonical_path: "/subscribe",
       plans: plans,
       current_step: :select_plan,
       selected_plan: nil,
       current_customer: customer,
       checkout_error: nil
     )}
  end

  @impl true
  def handle_info(:plans_updated, socket) do
    plans =
      SubscriptionPlan
      |> Ash.Query.filter(active == true)
      |> Ash.read!()
      |> Enum.sort_by(& &1.price_cents)

    {:noreply, assign(socket, plans: plans)}
  end

  def handle_info(:services_updated, socket), do: {:noreply, socket}

  @impl true
  def handle_params(params, _uri, socket) do
    socket =
      case {params, socket.assigns.current_step} do
        {%{"plan" => slug}, :select_plan} ->
          case Enum.find(socket.assigns.plans, &(&1.slug == slug)) do
            nil -> socket
            plan -> assign(socket, selected_plan: plan)
          end

        _ ->
          socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("select_plan", %{"slug" => slug}, socket) do
    plan = Enum.find(socket.assigns.plans, &(&1.slug == slug))
    {:noreply, assign(socket, selected_plan: plan)}
  end

  def handle_event("next_step", _params, socket) do
    ctx = build_context(socket.assigns)

    case SubscriptionStateMachine.transition(:forward, socket.assigns.current_step, ctx) do
      {:ok, next_step} ->
        {:noreply, assign(socket, current_step: next_step)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Cannot continue: #{reason}")}
    end
  end

  def handle_event("prev_step", _params, socket) do
    ctx = build_context(socket.assigns)

    case SubscriptionStateMachine.transition(:back, socket.assigns.current_step, ctx) do
      {:ok, prev_step} ->
        {:noreply, assign(socket, current_step: prev_step)}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_event("confirm_subscription", _params, socket) do
    plan = socket.assigns.selected_plan
    customer = socket.assigns.current_customer

    case StripeClient.create_subscription_checkout(
           plan,
           to_string(customer.email),
           customer.stripe_customer_id
         ) do
      {:ok, session} ->
        {:noreply, redirect(socket, external: session.url)}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(checkout_error: "Could not start checkout. Please try again.")
         |> put_flash(:error, "Payment setup failed. Please try again.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto py-8 px-4">
      <h1 class="text-3xl font-bold mb-2">Subscribe</h1>

      <!-- Step Indicator -->
      <div class="flex gap-2 mb-8">
        <div
          :for={{step, label} <- [{:select_plan, "Plan"}, {:auth, "Account"}, {:review, "Review"}]}
          class={[
            "badge badge-lg",
            cond do
              step == @current_step -> "badge-primary"
              step_index(step) < step_index(@current_step) -> "badge-success"
              true -> "badge-ghost"
            end
          ]}
        >
          {label}
        </div>
      </div>

      <!-- Step 1: Select Plan -->
      <div :if={@current_step == :select_plan}>
        <h2 class="text-xl font-bold mb-6">Choose Your Plan</h2>
        <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
          <div
            :for={plan <- @plans}
            class={[
              "card bg-base-100 shadow-md cursor-pointer transition-all duration-200 hover:shadow-lg hover:-translate-y-1",
              @selected_plan && @selected_plan.id == plan.id && "ring-2 ring-primary border-primary",
              plan.slug == "standard" && !(@selected_plan && @selected_plan.id == plan.id) && "border-2 border-primary md:scale-105 shadow-lg"
            ]}
            phx-click="select_plan"
            phx-value-slug={plan.slug}
          >
            <div class="card-body">
              <div :if={plan.slug == "standard"} class="badge badge-primary mb-2">Most Popular</div>
              <h3 class="card-title text-xl">{plan.name}</h3>
              <div class="flex items-baseline gap-1 mt-3">
                <span class="text-3xl font-bold">${div(plan.price_cents, 100)}</span>
                <span class="text-base-content/50">/month</span>
              </div>
              <ul class="mt-4 space-y-2 text-sm">
                <li :if={plan.basic_washes_per_month > 0} class="flex items-center gap-2">
                  <span class="text-success font-bold">&#10003;</span>
                  {plan.basic_washes_per_month} basic washes/month
                </li>
                <li :if={plan.deep_cleans_per_month > 0} class="flex items-center gap-2">
                  <span class="text-success font-bold">&#10003;</span>
                  {plan.deep_cleans_per_month} deep clean included
                </li>
                <li :if={plan.deep_clean_discount_percent > 0} class="flex items-center gap-2">
                  <span class="text-success font-bold">&#10003;</span>
                  {plan.deep_clean_discount_percent}% off deep cleans
                </li>
              </ul>
            </div>
          </div>
        </div>

        <div class="mt-8 text-right">
          <button
            :if={@selected_plan}
            class="btn btn-primary"
            phx-click="next_step"
          >
            Continue
          </button>
        </div>
      </div>

      <!-- Step 2: Auth (only shown if not logged in) -->
      <div :if={@current_step == :auth}>
        <h2 class="text-xl font-bold mb-4">Sign In to Subscribe</h2>
        <p class="text-base-content/60 mb-6">
          A subscription requires an account. Sign in or create one to continue.
        </p>

        <div class="card bg-base-100 shadow max-w-md">
          <div class="card-body">
            <.link navigate={~p"/sign-in"} class="btn btn-primary btn-block mb-3">
              Sign In
            </.link>
            <p class="text-center text-sm text-base-content/50">
              Don't have an account? Use the sign-in page to register.
            </p>
          </div>
        </div>

        <div class="mt-6">
          <button class="btn btn-ghost btn-sm" phx-click="prev_step">Back</button>
        </div>
      </div>

      <!-- Step 3: Review -->
      <div :if={@current_step == :review && @selected_plan}>
        <h2 class="text-xl font-bold mb-6">Review Your Subscription</h2>

        <div class="card bg-base-100 shadow mb-6">
          <div class="card-body">
            <h3 class="card-title">{@selected_plan.name} Plan</h3>
            <div class="flex items-baseline gap-1 mt-2">
              <span class="text-3xl font-bold">${div(@selected_plan.price_cents, 100)}</span>
              <span class="text-base-content/50">/month</span>
            </div>

            <div class="divider"></div>

            <ul class="space-y-2">
              <li :if={@selected_plan.basic_washes_per_month > 0}>
                {@selected_plan.basic_washes_per_month} basic washes per month
              </li>
              <li :if={@selected_plan.deep_cleans_per_month > 0}>
                {@selected_plan.deep_cleans_per_month} deep clean included
              </li>
              <li :if={@selected_plan.deep_clean_discount_percent > 0}>
                {@selected_plan.deep_clean_discount_percent}% off additional deep cleans
              </li>
            </ul>

            <div class="divider"></div>

            <p class="text-sm text-base-content/60">
              Cancel anytime. You'll be redirected to Stripe for secure payment setup.
            </p>

            <div :if={@checkout_error} class="alert alert-error mt-4">
              <span>{@checkout_error}</span>
            </div>
          </div>
        </div>

        <div class="flex justify-between">
          <button class="btn btn-ghost" phx-click="prev_step">Back</button>
          <button class="btn btn-primary btn-lg" phx-click="confirm_subscription">
            Subscribe Now
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp build_context(assigns) do
    %{
      selected_plan: assigns[:selected_plan],
      current_customer: assigns[:current_customer]
    }
  end

  defp step_index(:select_plan), do: 0
  defp step_index(:auth), do: 1
  defp step_index(:review), do: 2
  defp step_index(:checkout), do: 3
end
