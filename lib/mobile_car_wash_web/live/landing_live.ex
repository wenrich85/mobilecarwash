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
      |> assign(
        services: services,
        plans: plans,
        page_title: "Driveway Detail Co — Mobile Detailing",
        meta_description: "Professional mobile car wash and auto detailing that comes to you. Veteran-owned in Texas. Basic wash from $50, deep clean & detail from $200. Monthly plans available. Book online in 2 minutes.",
        meta_keywords: "mobile car wash, mobile auto detailing, car wash at home, mobile car wash near me, driveway detailing, veteran owned car wash, Texas mobile detailing, car detail service, monthly car wash plan, on-site car wash",
        canonical_path: "/"
      )

    if connected?(socket) do
      track_event(socket, "page.viewed", %{"path" => "/", "page" => "landing"})
      MobileCarWash.CatalogBroadcaster.subscribe()
    end

    {:ok, socket}
  end

  @impl true
  def handle_info(:services_updated, socket) do
    services =
      ServiceType
      |> Ash.Query.filter(active == true)
      |> Ash.read!()
      |> Enum.sort_by(& &1.base_price_cents)

    {:noreply, assign(socket, services: services)}
  end

  def handle_info(:plans_updated, socket) do
    plans =
      SubscriptionPlan
      |> Ash.Query.filter(active == true)
      |> Ash.read!()
      |> Enum.sort_by(& &1.price_cents)

    {:noreply, assign(socket, plans: plans)}
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, local_business_json: local_business_schema(assigns.services))

    ~H"""
    <!-- Structured Data for Google -->
    <script type="application/ld+json" nonce={@csp_nonce}>
      <%= Phoenix.HTML.raw(@local_business_json) %>
    </script>

    <!-- Hero Section — Navy gradient with Steel Blue accent -->
    <section class="hero min-h-[70vh] bg-gradient-to-br from-primary-800 via-primary-700 to-tertiary-700 text-white relative overflow-hidden">
      <!-- Decorative circles -->
      <div class="absolute top-[-5rem] right-[-5rem] w-64 h-64 bg-tertiary-400/10 rounded-full"></div>
      <div class="absolute bottom-[-3rem] left-[-3rem] w-48 h-48 bg-tertiary-400/10 rounded-full"></div>

      <div class="hero-content text-center relative z-10">
        <div class="max-w-2xl">
          <img src="/images/logo_dark.svg" alt="Driveway Detail Co" width="288" height="48" fetchpriority="high" decoding="async" class="h-12 w-auto mx-auto mb-6" />
          <h1 class="text-5xl font-bold leading-tight">Professional Detailing <br />at Your Door</h1>
          <p class="text-tertiary-200 font-medium tracking-wide uppercase text-sm mt-4">Veteran-Owned &amp; Operated</p>
          <p class="py-6 text-lg text-primary-200">
            Skip the drive. We bring the full detailing experience to your home, office, or anywhere you park.
          </p>
          <div class="flex gap-4 justify-center">
            <a href="#services" class="btn btn-lg bg-tertiary-400 hover:bg-tertiary-500 text-white border-none">See Services</a>
            <a href="#plans" class="btn btn-lg btn-outline border-white/40 text-white hover:bg-white/10 hover:border-white/60">View Plans</a>
          </div>
        </div>
      </div>
    </section>

    <!-- Services Section -->
    <section id="services" class="py-20 px-4 bg-base-200">
      <div class="max-w-6xl mx-auto">
        <h2 class="text-3xl font-bold text-center mb-3">Our Services</h2>
        <p class="text-center text-base-content/80 mb-12">Professional results, wherever you park.</p>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-8 max-w-4xl mx-auto">
          <div :for={service <- @services} class="card bg-base-100 shadow-lg hover:shadow-xl hover:-translate-y-1 transition-all duration-200">
            <div class="card-body">
              <h3 class="card-title text-2xl">{service.name}</h3>
              <p class="text-base-content/70">{service.description}</p>

              <div class="flex items-baseline gap-2 mt-4">
                <span class="text-sm text-base-content/70">starting at</span>
                <span class="text-4xl font-bold">${div(service.base_price_cents, 100)}</span>
              </div>
              <p class="text-xs text-base-content/70">Price varies by vehicle type</p>

              <div class="badge badge-info badge-outline mt-2">
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
    <section class="py-20 px-4 bg-base-100">
      <div class="max-w-4xl mx-auto">
        <h2 class="text-3xl font-bold text-center mb-12">How It Works</h2>

        <div class="grid grid-cols-1 md:grid-cols-3 gap-8">
          <div :for={{num, title, desc} <- [
            {"1", "Choose Your Service", "Pick a basic wash or deep clean that fits your needs."},
            {"2", "Pick a Time", "Select a date and time that works for your schedule."},
            {"3", "We Come to You", "Relax while we wash your car right where it's parked."}
          ]} class="text-center">
            <div class="w-14 h-14 rounded-full bg-primary text-primary-content text-xl font-bold flex items-center justify-center mx-auto mb-4 shadow-md">
              {num}
            </div>
            <h3 class="text-xl font-bold mb-2">{title}</h3>
            <p class="text-base-content/70">{desc}</p>
          </div>
        </div>
      </div>
    </section>

    <!-- Subscription Plans -->
    <section id="plans" class="py-20 px-4 bg-base-200">
      <div class="max-w-6xl mx-auto">
        <h2 class="text-3xl font-bold text-center mb-3">Monthly Plans</h2>
        <p class="text-center text-base-content/80 mb-12">Save with a subscription — cancel anytime.</p>

        <div class="grid grid-cols-1 md:grid-cols-3 gap-8">
          <div :for={plan <- @plans} class={[
            "card bg-base-100 shadow-lg hover:shadow-xl hover:-translate-y-1 transition-all duration-200",
            plan.slug == "standard" && "border-2 border-primary md:scale-105 shadow-xl"
          ]}>
            <div class="card-body">
              <div :if={plan.slug == "standard"} class="badge badge-primary mb-2">Most Popular</div>
              <h3 class="card-title text-2xl">{plan.name}</h3>

              <div class="flex items-baseline gap-1 mt-4">
                <span class="text-4xl font-bold">${div(plan.price_cents, 100)}</span>
                <span class="text-base-content/70">/month</span>
              </div>

              <ul class="mt-6 space-y-3">
                <li :if={plan.basic_washes_per_month > 0} class="flex items-center gap-2">
                  <span class="w-5 h-5 rounded-full bg-success/20 text-success flex items-center justify-center text-xs font-bold">&#10003;</span>
                  <span>{plan.basic_washes_per_month} basic washes/month</span>
                </li>
                <li :if={plan.deep_cleans_per_month > 0} class="flex items-center gap-2">
                  <span class="w-5 h-5 rounded-full bg-success/20 text-success flex items-center justify-center text-xs font-bold">&#10003;</span>
                  <span>{plan.deep_cleans_per_month} deep clean included</span>
                </li>
                <li :if={plan.deep_clean_discount_percent > 0} class="flex items-center gap-2">
                  <span class="w-5 h-5 rounded-full bg-success/20 text-success flex items-center justify-center text-xs font-bold">&#10003;</span>
                  <span>{plan.deep_clean_discount_percent}% off deep cleans</span>
                </li>
              </ul>

              <div class="card-actions justify-end mt-6">
                <.link navigate={~p"/subscribe?plan=#{plan.slug}"} class="btn btn-primary btn-block">
                  Subscribe
                </.link>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>

    <!-- Veteran Badge -->
    <section class="py-16 px-4 bg-primary-700 text-white">
      <div class="max-w-2xl mx-auto text-center">
        <img src="/images/logo_dark.svg" alt="Driveway Detail Co" width="240" height="40" loading="lazy" decoding="async" class="h-10 w-auto mx-auto mb-4 opacity-80" />
        <p class="text-xl font-semibold">
          Proudly veteran-owned and operated
        </p>
        <p class="text-primary-200 mt-2">
          100% disabled veteran-owned small business serving the local community.
        </p>
      </div>
    </section>

    <footer class="py-8 px-4 bg-base-200 text-base-content/70 text-sm">
      <div class="max-w-4xl mx-auto flex flex-col sm:flex-row items-center justify-between gap-3">
        <div>&copy; {Date.utc_today().year} Driveway Detail Co. All rights reserved.</div>
        <nav class="flex gap-4">
          <.link href="/privacy" class="hover:underline">Privacy Policy</.link>
          <a href="mailto:hello@drivewaydetailcosa.com" class="hover:underline">Contact</a>
        </nav>
      </div>
    </footer>
    """
  end

  # Build the full AutoWash/LocalBusiness JSON-LD block as a JSON
  # string. Dynamic `hasOfferCatalog.itemListElement` is populated
  # from the live ServiceType list so new services appear in rich
  # snippets without a code deploy.
  defp local_business_schema(services) do
    offers =
      Enum.map(services, fn s ->
        %{
          "@type" => "Offer",
          "name" => s.name,
          "price" => :erlang.float_to_binary(s.base_price_cents / 100, decimals: 2),
          "priceCurrency" => "USD",
          "category" => "Car Detailing"
        }
      end)

    %{
      "@context" => "https://schema.org",
      "@type" => "AutoWash",
      "name" => "Driveway Detail Co",
      "description" =>
        "Professional mobile car wash and auto detailing. We come to your home or office. Veteran-owned in San Antonio, TX.",
      "url" => "https://drivewaydetailcosa.com",
      "image" => "https://drivewaydetailcosa.com/images/og-share.png",
      "telephone" => "+1-512-555-0100",
      "priceRange" => "$50-$200",
      "address" => %{
        "@type" => "PostalAddress",
        "addressLocality" => "San Antonio",
        "addressRegion" => "TX",
        "addressCountry" => "US"
      },
      "geo" => %{
        "@type" => "GeoCoordinates",
        "latitude" => 29.4241,
        "longitude" => -98.4936
      },
      "areaServed" => %{
        "@type" => "City",
        "name" => "San Antonio",
        "containedInPlace" => %{"@type" => "AdministrativeArea", "name" => "Texas"}
      },
      "serviceType" => [
        "Mobile Car Wash",
        "Auto Detailing",
        "Mobile Detailing",
        "Car Detail"
      ],
      "knowsAbout" => ["Car Washing", "Auto Detailing", "Mobile Services"],
      "paymentAccepted" => "Credit Card",
      "currenciesAccepted" => "USD",
      "openingHours" => "Mo-Sa 08:00-18:00",
      "hasOfferCatalog" => %{
        "@type" => "OfferCatalog",
        "name" => "Detailing Services",
        "itemListElement" => offers
      }
    }
    |> Jason.encode!()
  end
end
