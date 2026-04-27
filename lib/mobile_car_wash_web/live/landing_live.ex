defmodule MobileCarWashWeb.LandingLive do
  use MobileCarWashWeb, :live_view

  import MobileCarWashWeb.MarketingComponents
  import MobileCarWashWeb.Live.Helpers.EventTracker

  alias MobileCarWash.Scheduling.ServiceType

  require Ash.Query

  @impl true
  def mount(_params, _session, socket) do
    services =
      ServiceType
      |> Ash.Query.filter(active == true)
      |> Ash.read!()
      |> Enum.sort_by(& &1.base_price_cents)

    socket =
      socket
      |> assign_session_id()
      |> assign(
        services: services,
        page_title: "Driveway Detail Co — Mobile Detailing",
        meta_description:
          "Professional mobile car wash and auto detailing that comes to you. Veteran-owned in Texas. Basic wash from $50, deep clean & detail from $200. Monthly plans available. Book online in 2 minutes.",
        meta_keywords:
          "mobile car wash, mobile auto detailing, car wash at home, mobile car wash near me, driveway detailing, veteran owned car wash, Texas mobile detailing, car detail service, monthly car wash plan, on-site car wash",
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

  @impl true
  def render(assigns) do
    assigns = assign(assigns, local_business_json: local_business_schema(assigns.services))

    basic = Enum.find(assigns.services, fn s -> s.slug == "basic_wash" end)

    premium =
      Enum.find(assigns.services, fn s -> s.slug == "deep_clean_detail" end) ||
        Enum.find(assigns.services, fn s -> s.slug == "premium" end)

    assigns = assign(assigns, basic: basic, premium: premium)

    ~H"""
    <%!-- Schema.org JSON-LD for Google rich results --%>
    <script type="application/ld+json" nonce={@csp_nonce}>
      <%= Phoenix.HTML.raw(@local_business_json) %>
    </script>

    <div>
      <%!-- =================== TOP NAV =================== --%>
      <%!-- TODO: spec called for a "Sign in" link here. Add when /sign-in route exists (phase-2). --%>
      <nav class="bg-base-100 border-b border-base-300">
        <div class="max-w-7xl mx-auto px-4 py-3 flex items-center justify-between">
          <a href="/" class="flex items-center">
            <img src={~p"/images/logo_light_v2.svg"} alt="Driveway Detail Co" class="h-8" />
          </a>
          <div class="flex items-center gap-4">
            <.link navigate={~p"/book"} class="btn btn-primary btn-sm">
              Book a wash
            </.link>
          </div>
        </div>
      </nav>

      <%!-- =================== HERO =================== --%>
      <.hero
        headline="Your car, washed where you parked it."
        subhead="Book in 30 seconds. We come to you. Pay when it's done."
        trust_badge="SAN ANTONIO · LICENSED & INSURED"
      >
        <:primary_cta>
          <.link navigate={~p"/book"} class="btn btn-primary">
            Book my first wash
          </.link>
        </:primary_cta>
        <:secondary_cta>
          <a href="#pricing" class="btn btn-ghost">See pricing</a>
        </:secondary_cta>
      </.hero>

      <%!-- =================== HOW IT WORKS =================== --%>
      <section class="bg-base-100 py-12 px-4">
        <div class="max-w-6xl mx-auto">
          <div class="text-center mb-8">
            <div class="text-xs font-semibold uppercase tracking-wide text-base-content/60 mb-1">
              HOW IT WORKS
            </div>
            <h2 class="text-2xl font-bold text-base-content tracking-tight">
              Three steps. No hose hookup.
            </h2>
          </div>
          <.feature_grid columns={3}>
            <:item number="1" title="Book online">
              Pick a service, pick a time, enter your address. 30 seconds.
            </:item>
            <:item number="2" title="We come to you">
              SMS update with our 15-minute arrival window. Self-contained van — no hose, no power needed.
            </:item>
            <:item number="3" title="Pay when done">
              No deposit. Card charged after the job. Photos before and after for your records.
            </:item>
          </.feature_grid>
        </div>
      </section>

      <%!-- =================== PRICING =================== --%>
      <section id="pricing" class="bg-base-200 py-12 px-4">
        <div class="max-w-4xl mx-auto">
          <div class="text-center mb-8">
            <div class="text-xs font-semibold uppercase tracking-wide text-base-content/60 mb-1">
              PRICING
            </div>
            <h2 class="text-2xl font-bold text-base-content tracking-tight">
              Two tiers. No hidden fees.
            </h2>
          </div>
          <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <.service_tier_card
              :if={@basic}
              name="Basic Wash"
              price="$50"
              duration="~45 min"
              features={[
                "Exterior hand wash",
                "Wheels & tires",
                "Window streak-free finish",
                "Quick interior vacuum"
              ]}
            >
              <:cta>
                <.link navigate={~p"/book?service=#{@basic.slug}"} class="btn btn-outline w-full">
                  Book Basic
                </.link>
              </:cta>
            </.service_tier_card>

            <.service_tier_card
              :if={@premium}
              name="Premium"
              price="$199.99"
              duration="~3 hours"
              highlighted={true}
              features={[
                "Everything in Basic",
                "Full interior wipe-down",
                "Shampoo carpets & seats",
                "Leather treatment",
                "Tire shine + wax coat",
                "Engine bay detail"
              ]}
            >
              <:cta>
                <.link navigate={~p"/book?service=#{@premium.slug}"} class="btn btn-primary w-full">
                  Book Premium
                </.link>
              </:cta>
            </.service_tier_card>
          </div>
        </div>
      </section>

      <%!-- =================== TECH SECTION =================== --%>
      <.tech_section
        headline="We tell you exactly when we'll arrive."
        subhead="Most mobile washes give you a 4-hour window. We give you 15 minutes — and SMS the moment we're 5 minutes out."
        bullets={[
          "→ 15-minute arrival windows, not \"morning\" or \"afternoon\"",
          "→ Live SMS updates as your tech approaches",
          "→ Photos of your car before and after every wash"
        ]}
      >
        <:preview>
          <div class="bg-slate-800 border border-slate-700 rounded-lg p-4 font-mono text-xs text-slate-300 space-y-3">
            <div>
              <div class="text-slate-500 mb-1">Driveway · 9:42 AM</div>
              <div class="text-cyan-400">Driveway:</div>
              <div>Hi Maria — Jordan is 8 minutes away. He'll text again when he's pulling up. 🚐</div>
            </div>
            <div>
              <div class="text-slate-500 mb-1">Driveway · 9:50 AM</div>
              <div class="text-cyan-400">Driveway:</div>
              <div>Pulling into your driveway now. Wash should take about 45 min.</div>
            </div>
          </div>
        </:preview>
      </.tech_section>

      <%!-- =================== TESTIMONIALS =================== --%>
      <section class="bg-base-200 py-12 px-4">
        <div class="max-w-6xl mx-auto">
          <div class="text-center mb-8">
            <h2 class="text-2xl font-bold text-base-content tracking-tight">
              What customers say
            </h2>
          </div>
          <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            <%!-- COPY: TBD - replace with real customer quote pre-launch --%>
            <.testimonial
              quote="Showed up exactly on time and my car looked brand new. Worth every penny."
              name="Maria G."
              vehicle="2023 Tesla Model 3"
            />
            <%!-- COPY: TBD - replace with real customer quote pre-launch --%>
            <.testimonial
              quote="I work from home and didn't even have to stop my Zoom call. They just did their thing in the driveway."
              name="Marcus T."
              vehicle="2021 Toyota 4Runner"
            />
            <%!-- COPY: TBD - replace with real customer quote pre-launch --%>
            <.testimonial
              quote="The detail job on my truck was unreal. Carpets I'd written off look new again."
              name="Brittany R."
              vehicle="2018 Ford F-150"
            />
          </div>
        </div>
      </section>

      <%!-- =================== FINAL CTA =================== --%>
      <.cta_band
        headline="Ready for a clean car without the trip?"
        subhead="First wash, no commitment. Book in 30 seconds."
      >
        <:cta>
          <.link navigate={~p"/book"} class="btn btn-primary">
            Book my first wash →
          </.link>
        </:cta>
      </.cta_band>

      <%!-- =================== FOOTER =================== --%>
      <%!-- TODO: spec called for "Terms" and "Sign in" links here. Add when /terms and /sign-in routes exist. --%>
      <footer class="bg-base-200 border-t border-base-300 py-6 px-4">
        <div class="max-w-7xl mx-auto flex flex-col sm:flex-row items-center justify-between gap-3 text-xs text-base-content/60">
          <div>© 2026 Driveway Detail Co. LLC · San Antonio, TX · Veteran-owned</div>
          <div class="flex items-center gap-4">
            <a href={~p"/privacy"} class="hover:text-base-content">Privacy</a>
          </div>
        </div>
      </footer>
    </div>
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
      "image" => "https://drivewaydetailcosa.com/images/og-share-v2.png",
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
