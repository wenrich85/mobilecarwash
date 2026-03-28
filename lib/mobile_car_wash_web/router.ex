defmodule MobileCarWashWeb.Router do
  use MobileCarWashWeb, :router
  use AshAuthentication.Phoenix.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {MobileCarWashWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers, %{
      "content-security-policy" =>
        "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; connect-src 'self' ws://localhost:*; frame-ancestors 'none'"
    }
    plug :load_from_session
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :load_from_bearer
  end

  # Public routes — no auth required
  scope "/", MobileCarWashWeb do
    pipe_through :browser

    get "/", PageController, :home

    # Authentication routes (sign in, sign up, sign out)
    sign_in_route()
    sign_out_route AuthController
    auth_routes MobileCarWash.Accounts.Customer, to: AuthController
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
