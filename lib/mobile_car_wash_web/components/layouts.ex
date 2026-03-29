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

    assigns = assign(assigns, :current_scope, scope)

    ~H"""
    <div class="drawer">
      <input id="mobile-drawer" type="checkbox" class="drawer-toggle" />

      <div class="drawer-content flex flex-col">
        <!-- Navbar -->
        <header class="navbar bg-base-100 shadow-sm sticky top-0 z-50">
          <!-- Mobile hamburger -->
          <div class="flex-none lg:hidden">
            <label for="mobile-drawer" class="btn btn-square btn-ghost">
              <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" class="inline-block w-6 h-6 stroke-current">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6h16M4 12h16M4 18h16" />
              </svg>
            </label>
          </div>

          <!-- Brand -->
          <div class="flex-1">
            <a href="/" class="btn btn-ghost text-xl font-bold">
              Mobile Car Wash
            </a>
          </div>

          <!-- Desktop nav -->
          <div class="flex-none hidden lg:block">
            <ul class="menu menu-horizontal items-center gap-1">
              <li><a href="/" class="btn btn-ghost btn-sm">Home</a></li>
              <li><a href="/book" class="btn btn-ghost btn-sm">Book a Wash</a></li>

              <li :if={@current_scope}><a href="/appointments" class="btn btn-ghost btn-sm">My Appointments</a></li>

              <li :if={@current_scope && Map.get(@current_scope, :role) in [:technician, :admin]}>
                <a href="/tech" class="btn btn-ghost btn-sm">Tech Dashboard</a>
              </li>

              <li :if={@current_scope && Map.get(@current_scope, :role) == :admin} class="dropdown dropdown-end">
                <div tabindex="0" role="button" class="btn btn-ghost btn-sm">Admin ▾</div>
                <ul tabindex="0" class="dropdown-content menu p-2 shadow bg-base-100 rounded-box w-52 z-50">
                  <li><a href="/admin/dispatch">Dispatch</a></li>
                  <li><a href="/admin/metrics">Metrics</a></li>
                  <li><a href="/admin/events">Events</a></li>
                  <li><a href="/admin/formation">Formation</a></li>
                  <li><a href="/admin/org-chart">Org Chart</a></li>
                  <li><a href="/admin/procedures">SOPs</a></li>
                </ul>
              </li>

              <li><.theme_toggle /></li>

              <li :if={@current_scope}>
                <span class="text-sm text-base-content/60">{Map.get(@current_scope, :name, "")}</span>
              </li>
              <li :if={@current_scope}>
                <a href="/sign-out" class="btn btn-outline btn-sm">Sign Out</a>
              </li>
              <li :if={!@current_scope}>
                <a href="/sign-in" class="btn btn-primary btn-sm">Sign In</a>
              </li>
            </ul>
          </div>
        </header>

        <!-- Page content -->
        <main class="flex-1">
          {render_slot(@inner_block) || @inner_content}
        </main>

        <.flash_group flash={@flash} />
      </div>

      <!-- Mobile drawer sidebar -->
      <div class="drawer-side z-50">
        <label for="mobile-drawer" class="drawer-overlay"></label>
        <ul class="menu p-4 w-72 min-h-full bg-base-200">
          <li class="menu-title text-lg font-bold mb-2">Mobile Car Wash</li>
          <li><a href="/">Home</a></li>
          <li><a href="/book">Book a Wash</a></li>

          <li :if={@current_scope}><a href="/appointments">My Appointments</a></li>

          <li :if={@current_scope && Map.get(@current_scope, :role) in [:technician, :admin]} class="menu-title mt-4">Technician</li>
          <li :if={@current_scope && Map.get(@current_scope, :role) in [:technician, :admin]}><a href="/tech">Dashboard</a></li>

          <li :if={@current_scope && Map.get(@current_scope, :role) == :admin} class="menu-title mt-4">Admin</li>
          <li :if={@current_scope && Map.get(@current_scope, :role) == :admin}><a href="/admin/dispatch">Dispatch</a></li>
          <li :if={@current_scope && Map.get(@current_scope, :role) == :admin}><a href="/admin/metrics">Metrics</a></li>
          <li :if={@current_scope && Map.get(@current_scope, :role) == :admin}><a href="/admin/events">Events</a></li>
          <li :if={@current_scope && Map.get(@current_scope, :role) == :admin}><a href="/admin/formation">Formation</a></li>
          <li :if={@current_scope && Map.get(@current_scope, :role) == :admin}><a href="/admin/org-chart">Org Chart</a></li>
          <li :if={@current_scope && Map.get(@current_scope, :role) == :admin}><a href="/admin/procedures">SOPs</a></li>

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
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
