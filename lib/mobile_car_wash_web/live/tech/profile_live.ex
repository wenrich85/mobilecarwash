defmodule MobileCarWashWeb.Tech.ProfileLive do
  use MobileCarWashWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Tech Profile"), layout: false}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_customer}>
      <main class="mx-auto max-w-3xl px-4 py-10 sm:px-6 lg:px-8">
        <section class="rounded-2xl border border-base-300 bg-base-100 p-6 shadow-sm">
          <p class="text-xs font-semibold uppercase tracking-[0.2em] text-primary/80">
            Technician profile
          </p>
          <h1 class="mt-2 text-3xl font-semibold text-base-content">Profile</h1>
          <p class="mt-3 text-sm leading-6 text-base-content/70">
            This private profile page is reserved for the follow-up task that fills in applicant and technician profile details.
          </p>
        </section>
      </main>
    </Layouts.app>
    """
  end
end
