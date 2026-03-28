defmodule MobileCarWashWeb.LandingLive do
  use MobileCarWashWeb, :live_view

  import MobileCarWashWeb.Live.Helpers.EventTracker

  alias MobileCarWash.Scheduling.ServiceType
  alias MobileCarWash.Billing.SubscriptionPlan

  require Ash.Query

  @impl true
  def mount(_params, _session, socket) do
    services =
      ServiceType
      |> Ash.Query.filter(active == true)
      |> Ash.read!()
      |> Enum.sort_by(& &1.base_price_cents)

    plans =
      SubscriptionPlan
      |> Ash.Query.filter(active == true)
      |> Ash.read!()
      |> Enum.sort_by(& &1.price_cents)

    socket =
      socket
      |> assign_session_id()
      |> assign(services: services, plans: plans, page_title: "Mobile Car Wash — We Come to You")

    if connected?(socket) do
      track_event(socket, "page.viewed", %{"path" => "/", "page" => "landing"})
    end

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <!-- Hero Section -->
    <section class="hero min-h-[60vh] bg-base-200">
      <div class="hero-content text-center">
        <div class="max-w-2xl">
          <h1 class="text-5xl font-bold">Professional Car Wash at Your Door</h1>
          <p class="py-6 text-lg">
            Skip the drive. We bring the full car wash experience to your home, office, or anywhere you park.
            Veteran-owned. Satisfaction guaranteed.
          </p>
          <a href="#services" class="btn btn-primary btn-lg">View Services</a>
        </div>
      </div>
    </section>

    <!-- Services Section -->
    <section id="services" class="py-16 px-4">
      <div class="max-w-6xl mx-auto">
        <h2 class="text-3xl font-bold text-center mb-12">Our Services</h2>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-8 max-w-4xl mx-auto">
          <div :for={service <- @services} class="card bg-base-100 shadow-xl">
            <div class="card-body">
              <h3 class="card-title text-2xl">{service.name}</h3>
              <p class="text-base-content/70">{service.description}</p>

              <div class="flex items-baseline gap-2 mt-4">
                <span class="text-sm text-base-content/50">starting at</span>
                <span class="text-4xl font-bold">${div(service.base_price_cents, 100)}</span>
              </div>
              <p class="text-xs text-base-content/40">Price varies by vehicle type</p>

              <div class="badge badge-outline mt-2">
                {service.duration_minutes} minutes
              </div>

              <div class="card-actions justify-end mt-6">
                <.link
                  navigate={~p"/book?service=#{service.slug}"}
                  class="btn btn-primary btn-block"
                >
                  Book Now
                </.link>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>

    <!-- How It Works -->
    <section class="py-16 px-4 bg-base-200">
      <div class="max-w-4xl mx-auto">
        <h2 class="text-3xl font-bold text-center mb-12">How It Works</h2>

        <div class="grid grid-cols-1 md:grid-cols-3 gap-8">
          <div class="text-center">
            <div class="text-4xl mb-4">1</div>
            <h3 class="text-xl font-bold mb-2">Choose Your Service</h3>
            <p class="text-base-content/70">Pick a basic wash or deep clean that fits your needs.</p>
          </div>
          <div class="text-center">
            <div class="text-4xl mb-4">2</div>
            <h3 class="text-xl font-bold mb-2">Pick a Time</h3>
            <p class="text-base-content/70">Select a date and time that works for your schedule.</p>
          </div>
          <div class="text-center">
            <div class="text-4xl mb-4">3</div>
            <h3 class="text-xl font-bold mb-2">We Come to You</h3>
            <p class="text-base-content/70">Relax while we wash your car right where it's parked.</p>
          </div>
        </div>
      </div>
    </section>

    <!-- Subscription Plans -->
    <section id="plans" class="py-16 px-4">
      <div class="max-w-6xl mx-auto">
        <h2 class="text-3xl font-bold text-center mb-4">Monthly Plans</h2>
        <p class="text-center text-base-content/70 mb-12">Save with a subscription — cancel anytime.</p>

        <div class="grid grid-cols-1 md:grid-cols-3 gap-8">
          <div :for={plan <- @plans} class={[
            "card bg-base-100 shadow-xl",
            plan.slug == "standard" && "border-2 border-primary"
          ]}>
            <div class="card-body">
              <div :if={plan.slug == "standard"} class="badge badge-primary mb-2">Most Popular</div>
              <h3 class="card-title text-2xl">{plan.name}</h3>

              <div class="flex items-baseline gap-1 mt-4">
                <span class="text-4xl font-bold">${div(plan.price_cents, 100)}</span>
                <span class="text-base-content/50">/month</span>
              </div>

              <ul class="mt-6 space-y-2">
                <li :if={plan.basic_washes_per_month > 0} class="flex items-center gap-2">
                  <span class="text-success">✓</span>
                  {plan.basic_washes_per_month} basic washes/month
                </li>
                <li :if={plan.deep_cleans_per_month > 0} class="flex items-center gap-2">
                  <span class="text-success">✓</span>
                  {plan.deep_cleans_per_month} deep clean included
                </li>
                <li :if={plan.deep_clean_discount_percent > 0} class="flex items-center gap-2">
                  <span class="text-success">✓</span>
                  {plan.deep_clean_discount_percent}% off deep cleans
                </li>
              </ul>

              <div class="card-actions justify-end mt-6">
                <button class="btn btn-outline btn-block" disabled>
                  Coming Soon
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>

    <!-- Veteran Badge -->
    <section class="py-12 px-4 bg-base-200">
      <div class="max-w-2xl mx-auto text-center">
        <p class="text-lg font-semibold">
          Proudly veteran-owned and operated
        </p>
        <p class="text-base-content/70 mt-2">
          100% disabled veteran-owned small business serving the local community.
        </p>
      </div>
    </section>
    """
  end
end
