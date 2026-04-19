defmodule MobileCarWashWeb.Router do
  use MobileCarWashWeb, :router
  use AshAuthentication.Phoenix.Router

  @ws_connect if Application.compile_env(:mobile_car_wash, :dev_routes), do: "ws://localhost:*", else: ""

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {MobileCarWashWeb.Layouts, :root}
    plug :protect_from_forgery
    plug MobileCarWashWeb.Plugs.CspNonce
    plug :put_security_headers
    plug :load_from_session
  end

  # Nonce + 'strict-dynamic' replaces host allowlists in script-src so
  # scripts loaded by trusted (nonce-tagged) code inherit trust — fixes
  # Lighthouse's "Weak CSP" host-allowlist bypass warning while still
  # permitting GTM, which is now loaded dynamically by ga-init.js.
  defp put_security_headers(conn, _opts) do
    nonce = conn.assigns.csp_nonce

    csp =
      [
        "default-src 'self'",
        "script-src 'self' 'nonce-#{nonce}' 'strict-dynamic' https: http:",
        "style-src 'self' 'unsafe-inline' https://unpkg.com",
        "img-src 'self' data: https: http://*.tile.openstreetmap.org https://*.tile.openstreetmap.org https://*.basemaps.cartocdn.com https://tiles.stadiamaps.com",
        "font-src 'self'",
        "connect-src 'self' wss: #{@ws_connect} https://www.google-analytics.com https://analytics.google.com",
        "frame-ancestors 'none'",
        "base-uri 'self'",
        "form-action 'self'",
        "object-src 'none'"
      ]
      |> Enum.join("; ")

    conn
    |> put_resp_header("content-security-policy", csp)
    |> put_resp_header("x-content-type-options", "nosniff")
    |> put_resp_header("x-xss-protection", "1; mode=block")
    |> put_resp_header("referrer-policy", "strict-origin-when-cross-origin")
    |> put_resp_header("permissions-policy", "geolocation=(), microphone=(), camera=()")
    |> put_resp_header("cross-origin-opener-policy", "same-origin")
    |> put_hsts_header()
  end

  # Add HSTS header in production only (evaluated at compile time — Mix not available in releases)
  @is_prod Application.compile_env(:mobile_car_wash, :env, :prod) == :prod

  defp put_hsts_header(conn) do
    if @is_prod do
      put_resp_header(
        conn,
        "strict-transport-security",
        "max-age=63072000; includeSubDomains; preload"
      )
    else
      conn
    end
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :load_from_bearer
  end

  pipeline :rate_limited_auth do
    plug MobileCarWashWeb.Plugs.RateLimit,
      max: 10,
      period: 60_000,
      message: "Too many sign-in attempts. Please wait a moment."
  end

  pipeline :stripe_webhook do
    plug :accepts, ["json"]
    plug MobileCarWashWeb.Plugs.RawBody
  end

  # Stripe webhooks — must be before browser pipeline (no CSRF)
  scope "/webhooks", MobileCarWashWeb do
    pipe_through :stripe_webhook

    post "/stripe", StripeWebhookController, :handle
  end

  # Public routes — landing page, booking, auth
  scope "/", MobileCarWashWeb do
    pipe_through :browser

    # LiveView pages with optional auth
    live_session :public,
      on_mount: [
        MobileCarWashWeb.AssignCspNonce,
        {MobileCarWashWeb.LiveAuth, :maybe_load_customer}
      ] do
      live "/", LandingLive
      live "/book", BookingLive
      live "/book/success", BookingSuccessLive
      live "/book/cancel", BookingCancelLive
      live "/subscribe", SubscriptionLive
      live "/subscribe/success", SubscriptionSuccessLive
      live "/subscribe/cancel", SubscriptionCancelLive
      live "/style-guide", Admin.StyleGuideLive
      live "/privacy", PrivacyLive
    end

    # Authentication routes — rate-limited via on_mount hook
    sign_in_route(
      auth_routes_prefix: "/auth",
      overrides: [MobileCarWashWeb.AuthOverrides, AshAuthentication.Phoenix.Overrides.Default],
      on_mount: [
        MobileCarWashWeb.AssignCspNonce,
        {MobileCarWashWeb.SignInRateLimit, :limit_sign_in}
      ]
    )
    sign_out_route AuthController
    auth_routes(AuthController, MobileCarWash.Accounts.Customer, auth_routes_prefix: "/auth")
  end

  # Customer routes — any authenticated user
  scope "/", MobileCarWashWeb do
    pipe_through :browser

    live_session :authenticated,
      on_mount: [
        MobileCarWashWeb.AssignCspNonce,
        {MobileCarWashWeb.LiveAuth, :require_customer},
        {MobileCarWashWeb.TrackPresence, :track}
      ] do
      live "/appointments", AppointmentsLive
      live "/appointments/:id/status", AppointmentStatusLive
      live "/account/subscription", SubscriptionManageLive
      live "/account/recurring", RecurringScheduleManageLive
    end

    # Photo serving — requires auth, controller checks appointment ownership
    get "/photos/appointments/:appointment_id/:filename", PhotoController, :show
  end

  # Technician routes — technician or admin role
  scope "/tech", MobileCarWashWeb do
    pipe_through :browser

    live_session :technician,
      on_mount: [
        MobileCarWashWeb.AssignCspNonce,
        {MobileCarWashWeb.LiveAuth, :require_technician},
        {MobileCarWashWeb.TrackPresence, :track}
      ] do
      live "/", TechDashboardLive
      live "/checklist/:id", ChecklistLive
    end
  end

  # Admin routes — owner-only metrics dashboard
  scope "/admin", MobileCarWashWeb.Admin do
    pipe_through :browser

    live_session :admin,
      on_mount: [
        MobileCarWashWeb.AssignCspNonce,
        {MobileCarWashWeb.AdminAuth, :require_admin},
        {MobileCarWashWeb.TrackPresence, :track}
      ] do
      live "/", DashboardLive
      live "/metrics", MetricsLive
      live "/events", EventsLive
      live "/formation", FormationLive
      live "/org-chart", OrgChartLive
      live "/procedures", ProceduresLive
      live "/dispatch", DispatchLive
      live "/technicians", TechniciansLive
      live "/technicians/:id", TechnicianProfileLive
      live "/settings", SettingsLive
      live "/cash-flow", CashFlowLive
      live "/vans", VansLive
      live "/supplies", SuppliesLive
      live "/blocks", BlocksLive
      live "/schedule-templates", ScheduleTemplatesLive
    end
  end

  # API v1 — mobile apps + programmatic clients
  scope "/api/v1", MobileCarWashWeb.Api.V1 do
    pipe_through :api

    post "/auth/register", AuthController, :register
    post "/auth/sign_in", AuthController, :sign_in
    post "/auth/sign_out", AuthController, :sign_out

    # Public catalog
    get "/services", CatalogController, :services
    get "/subscription_plans", CatalogController, :subscription_plans

    # Customer resources (auth required — enforced in controllers)
    get "/vehicles", VehiclesController, :index
    post "/vehicles", VehiclesController, :create
    get "/addresses", AddressesController, :index
    post "/addresses", AddressesController, :create

    # Booking flow
    get "/blocks", BlocksController, :index
    post "/bookings", BookingsController, :create

    # Appointments (read for everyone; customer-initiated cancel via DELETE)
    get "/appointments", AppointmentsController, :index
    get "/appointments/:id", AppointmentsController, :show
    delete "/appointments/:id", AppointmentsController, :delete

    # Subscriptions
    get "/subscriptions", SubscriptionsController, :index
    post "/subscriptions/:id/pause", SubscriptionsController, :pause
    post "/subscriptions/:id/resume", SubscriptionsController, :resume
    post "/subscriptions/:id/cancel", SubscriptionsController, :cancel

    # Push notification device tokens (iOS + Android)
    post "/device_tokens", DeviceTokensController, :create
    delete "/device_tokens/:id", DeviceTokensController, :delete

    # Per-channel opt-in preferences (SMS + push; email uses unsubscribe links)
    get "/notification_preferences", NotificationPreferencesController, :show
    patch "/notification_preferences", NotificationPreferencesController, :update

    # Tech-facing API — role-gated to :technician / :admin inside each
    # controller via the RequireTechAuth plug.
    get "/tech/me", TechController, :me
    patch "/tech/me/status", TechController, :update_status
    get "/tech/appointments", TechAppointmentsController, :index
    post "/tech/appointments/:id/depart", TechAppointmentsController, :depart
    post "/tech/appointments/:id/arrive", TechAppointmentsController, :arrive
    post "/tech/appointments/:id/start", TechAppointmentsController, :start
    post "/tech/appointments/:id/complete", TechAppointmentsController, :complete
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:mobile_car_wash, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: MobileCarWashWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

end
