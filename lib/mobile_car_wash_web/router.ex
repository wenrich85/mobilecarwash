defmodule MobileCarWashWeb.Router do
  use MobileCarWashWeb, :router
  use AshAuthentication.Phoenix.Router

  @ws_connect if Application.compile_env(:mobile_car_wash, :dev_routes), do: "ws://localhost:*", else: ""
  @csp_policy [
    "default-src 'self'",
    "script-src 'self' https://www.googletagmanager.com https://www.google-analytics.com https://unpkg.com",
    "style-src 'self' 'unsafe-inline' https://unpkg.com",
    "img-src 'self' data: https: http://*.tile.openstreetmap.org https://*.tile.openstreetmap.org https://*.basemaps.cartocdn.com https://tiles.stadiamaps.com",
    "font-src 'self'",
    "connect-src 'self' wss: #{@ws_connect} https://www.google-analytics.com https://analytics.google.com",
    "frame-ancestors 'none'"
  ] |> Enum.join("; ")

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {MobileCarWashWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers, %{
      "content-security-policy" => @csp_policy
    }
    plug :load_from_session
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
    live_session :public, on_mount: {MobileCarWashWeb.LiveAuth, :maybe_load_customer} do
      live "/", LandingLive
      live "/book", BookingLive
      live "/book/success", BookingSuccessLive
      live "/book/cancel", BookingCancelLive
      live "/subscribe", SubscriptionLive
      live "/subscribe/success", SubscriptionSuccessLive
      live "/subscribe/cancel", SubscriptionCancelLive
      live "/style-guide", Admin.StyleGuideLive
      live "/sign-in", Auth.SignInLive
    end

    # Authentication routes
    sign_in_route(
      auth_routes_prefix: "/auth",
      overrides: [MobileCarWashWeb.AuthOverrides, AshAuthentication.Phoenix.Overrides.Default]
    )
    sign_out_route AuthController

    # Manual auth callback route (rate-limited)
    scope "/auth" do
      pipe_through :rate_limited_auth
      get "/customer/password/sign_in_with_token", AuthController, :sign_in_with_token
    end
  end

  # Customer routes — any authenticated user
  scope "/", MobileCarWashWeb do
    pipe_through :browser

    live_session :authenticated, on_mount: {MobileCarWashWeb.LiveAuth, :require_customer} do
      live "/appointments", AppointmentsLive
      live "/appointments/:id/status", AppointmentStatusLive
      live "/account/subscription", SubscriptionManageLive
    end
  end

  # Technician routes — technician or admin role
  scope "/tech", MobileCarWashWeb do
    pipe_through :browser

    live_session :technician, on_mount: {MobileCarWashWeb.LiveAuth, :require_technician} do
      live "/", TechDashboardLive
      live "/checklist/:id", ChecklistLive
    end
  end

  # Admin routes — owner-only metrics dashboard
  scope "/admin", MobileCarWashWeb.Admin do
    pipe_through :browser

    live_session :admin, on_mount: {MobileCarWashWeb.AdminAuth, :require_admin} do
      live "/metrics", MetricsLive
      live "/events", EventsLive
      live "/formation", FormationLive
      live "/org-chart", OrgChartLive
      live "/procedures", ProceduresLive
      live "/dispatch", DispatchLive
      live "/settings", SettingsLive
      live "/cash-flow", CashFlowLive
      live "/vans", VansLive
    end
  end

  # API v1 — for future native apps
  scope "/api/v1", MobileCarWashWeb.Api.V1 do
    pipe_through :api
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
