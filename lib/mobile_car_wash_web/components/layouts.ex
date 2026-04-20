defmodule MobileCarWashWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use MobileCarWashWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  GDPR/CCPA strict-opt-in cookie consent banner. Rendered in the
  root layout whenever `@current_consent` is nil (set by the
  LoadCookieConsent plug). Hidden once the visitor picks a choice.
  """
  attr :conn, Plug.Conn, required: true

  def cookie_banner(assigns) do
    ~H"""
    <div
      id="cookie-banner"
      class="fixed bottom-0 inset-x-0 z-50 bg-base-200 border-t border-base-300 shadow-lg"
      role="dialog"
      aria-label="Cookie consent"
    >
      <div class="max-w-5xl mx-auto px-4 py-4 flex flex-col md:flex-row md:items-center md:justify-between gap-4">
        <div class="flex-1 text-sm text-base-content/90">
          <p class="font-semibold mb-1">We use cookies to improve your experience.</p>
          <p class="text-base-content/70">
            Essential cookies keep the site working. Analytics and marketing
            cookies help us understand what's useful and reach more drivers
            like you. You can change this anytime.
          </p>
        </div>

        <div class="flex flex-col sm:flex-row gap-2 shrink-0">
          <form action="/cookie-consent" method="post" class="contents">
            <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
            <input type="hidden" name="choice" value="essential_only" />
            <button type="submit" class="btn btn-ghost btn-sm">
              Essential only
            </button>
          </form>

          <form action="/cookie-consent" method="post" class="contents">
            <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
            <input type="hidden" name="choice" value="accept_all" />
            <button type="submit" class="btn btn-primary btn-sm">
              Accept all
            </button>
          </form>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: false

  def app(assigns) do
    # Build scope from current_customer (set by LiveAuth hooks) or current_scope
    customer = assigns[:current_scope] || assigns[:current_customer]

    scope =
      case customer do
        %{name: name, role: role} -> %{name: name, role: role}
        _ -> nil
      end

    # The soft-gate verification banner needs to know whether the
    # signed-in customer has clicked their link yet. Pull it off the
    # raw record — the scope map omits it so admin/tech sessions don't
    # get a banner that doesn't apply to them.
    unverified? =
      case customer do
        %{role: :customer, email_verified_at: nil} -> true
        _ -> false
      end

    assigns = assign(assigns, current_scope: scope, show_verify_banner: unverified?)

    ~H"""
    <div class="drawer">
      <label for="mobile-drawer" class="sr-only">Toggle navigation menu</label>
      <input id="mobile-drawer" type="checkbox" class="drawer-toggle" aria-label="Toggle navigation menu" />

      <div class="drawer-content flex flex-col">
        <!-- Skip to content -->
        <a href="#main-content" class="sr-only focus:not-sr-only focus:absolute focus:z-[100] focus:top-2 focus:left-2 focus:btn focus:btn-primary focus:btn-sm">
          Skip to content
        </a>

        <!-- Navbar -->
        <header class="navbar bg-base-100 shadow-sm sticky top-0 z-50">
          <!-- Mobile hamburger -->
          <div class="flex-none lg:hidden">
            <label for="mobile-drawer" class="btn btn-square btn-ghost" aria-label="Open navigation menu">
              <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" class="inline-block w-6 h-6 stroke-current" aria-hidden="true">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6h16M4 12h16M4 18h16" />
              </svg>
            </label>
          </div>

          <!-- Brand -->
          <div class="flex-1">
            <a href="/" class="btn btn-ghost h-auto py-1 px-2">
              <img src="/images/logo_light.svg" alt="Driveway Detail Co" width="216" height="36" class="h-9 w-auto dark:hidden" />
              <img src="/images/logo_dark.svg" alt="Driveway Detail Co" width="216" height="36" class="h-9 w-auto hidden dark:block" />
            </a>
          </div>

          <!-- Desktop nav -->
          <nav aria-label="Main navigation" class="flex-none hidden lg:block">
            <ul class="menu menu-horizontal items-center gap-1">
              <li><a href="/" class="btn btn-ghost btn-sm">Home</a></li>
              <li><a href="/book" class="btn btn-ghost btn-sm">Book a Wash</a></li>

              <li :if={@current_scope}><a href="/appointments" class="btn btn-ghost btn-sm">My Appointments</a></li>
              <li :if={@current_scope}><a href="/account/subscription" class="btn btn-ghost btn-sm">My Plan</a></li>

              <li :if={@current_scope && Map.get(@current_scope, :role) in [:technician, :admin]}>
                <a href="/tech" class="btn btn-ghost btn-sm">Tech Dashboard</a>
              </li>

              <li :if={@current_scope && Map.get(@current_scope, :role) == :admin}>
                <a href="/admin" class="btn btn-primary btn-sm">Admin Hub</a>
              </li>

              <li><.theme_toggle /></li>

              <li :if={@current_scope}>
                <span class="text-sm text-base-content/80">{Map.get(@current_scope, :name, "")}</span>
              </li>
              <li :if={@current_scope}>
                <a href="/sign-out" class="btn btn-outline btn-sm">Sign Out</a>
              </li>
              <li :if={!@current_scope}>
                <a href="/sign-in" class="btn btn-primary btn-sm">Sign In</a>
              </li>
            </ul>
          </nav>
        </header>

        <!-- Verify-email banner — customer-only, dismissable once they
             click the link in their signup email. Soft gate, not hard. -->
        <div :if={@show_verify_banner} class="bg-warning/10 border-b border-warning/30">
          <div class="max-w-7xl mx-auto px-4 py-2 flex items-center justify-between gap-3 flex-wrap">
            <p class="text-sm text-warning-content/90">
              <span class="font-semibold">Verify your email.</span>
              We sent a confirmation link when you signed up — please tap it so
              we can send you booking updates.
            </p>
            <form action="/auth/resend-verification" method="post" class="inline">
              <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
              <button type="submit" class="btn btn-warning btn-sm">
                Resend email
              </button>
            </form>
          </div>
        </div>

        <!-- Page content -->
        <main id="main-content" class="flex-1">
          {render_slot(@inner_block) || @inner_content}
        </main>

        <.flash_group flash={@flash} />

        <!-- Footer -->
        <footer class="bg-base-200 border-t border-base-300">
          <div class="max-w-7xl mx-auto px-4 py-12">
            <div class="grid grid-cols-1 md:grid-cols-4 gap-8">
              <div>
                <img src="/images/logo_light.svg" alt="Driveway Detail Co" width="192" height="32" class="h-8 w-auto mb-3 dark:hidden" />
                <img src="/images/logo_dark.svg" alt="Driveway Detail Co" width="192" height="32" class="h-8 w-auto mb-3 hidden dark:block" />
                <p class="text-sm text-base-content/80">
                  Professional mobile detailing at your door. Veteran-owned in San Antonio, TX.
                </p>
              </div>
              <div>
                <h4 class="font-semibold mb-3 text-sm">Services</h4>
                <ul class="space-y-2 text-sm text-base-content/80">
                  <li><a href="/book" class="hover:text-base-content">Book a Wash</a></li>
                  <li><a href="/subscribe" class="hover:text-base-content">Monthly Plans</a></li>
                  <li><a href="/#services" class="hover:text-base-content">Pricing</a></li>
                </ul>
              </div>
              <div>
                <h4 class="font-semibold mb-3 text-sm">Account</h4>
                <ul class="space-y-2 text-sm text-base-content/80">
                  <li :if={@current_scope}>
                    <span class="font-semibold text-base-content">{Map.get(@current_scope, :name, "")}</span>
                  </li>
                  <li :if={!@current_scope}>
                    <a href="/sign-in" class="hover:text-base-content">Sign In</a>
                  </li>
                  <li :if={@current_scope}><a href="/sign-out" class="hover:text-base-content">Sign Out</a></li>
                  <li :if={@current_scope}><a href="/appointments" class="hover:text-base-content">My Appointments</a></li>
                  <li :if={@current_scope}><a href="/account/subscription" class="hover:text-base-content">My Plan</a></li>
                </ul>
              </div>
              <div>
                <h4 class="font-semibold mb-3 text-sm">Company</h4>
                <ul class="space-y-2 text-sm text-base-content/80">
                  <li>San Antonio, TX</li>
                  <li>Mon–Sat 8am–6pm</li>
                </ul>
              </div>
            </div>
            <div class="border-t border-base-300 mt-8 pt-6 text-center text-xs text-base-content/70">
              <p>&copy; {DateTime.utc_now().year} Driveway Detail Co. All rights reserved. Veteran-owned.</p>
            </div>
          </div>
        </footer>
      </div>

      <!-- Mobile drawer sidebar -->
      <div class="drawer-side z-50">
        <label for="mobile-drawer" class="drawer-overlay"></label>
        <ul class="menu p-4 w-72 min-h-full bg-base-200">
          <li class="mb-4 px-2">
            <img src="/images/logo_light.svg" alt="Driveway Detail Co" width="240" height="40" class="h-10 w-auto dark:hidden" />
            <img src="/images/logo_dark.svg" alt="Driveway Detail Co" width="240" height="40" class="h-10 w-auto hidden dark:block" />
          </li>
          <li><a href="/">Home</a></li>
          <li><a href="/book">Book a Wash</a></li>

          <li :if={@current_scope}><a href="/appointments">My Appointments</a></li>
          <li :if={@current_scope}><a href="/account/subscription">My Plan</a></li>

          <li :if={@current_scope && Map.get(@current_scope, :role) in [:technician, :admin]} class="menu-title mt-4">Technician</li>
          <li :if={@current_scope && Map.get(@current_scope, :role) in [:technician, :admin]}><a href="/tech">Dashboard</a></li>

          <li :if={@current_scope && Map.get(@current_scope, :role) == :admin} class="menu-title mt-4">Admin</li>
          <li :if={@current_scope && Map.get(@current_scope, :role) == :admin}><a href="/admin" class="font-semibold">Admin Hub</a></li>

          <li :if={@current_scope} class="mt-4"><a href="/sign-out" class="text-error">Sign Out</a></li>
          <li :if={!@current_scope} class="mt-4"><a href="/sign-in" class="font-semibold">Sign In</a></li>
        </ul>
      </div>
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div role="group" aria-label="Theme" class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
        aria-label="Use system theme"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
        aria-label="Use light theme"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
        aria-label="Use dark theme"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
