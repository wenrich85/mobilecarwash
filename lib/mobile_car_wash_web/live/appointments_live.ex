defmodule MobileCarWashWeb.AppointmentsLive do
  @moduledoc "Customer's appointment list — placeholder for Phase 3+"
  use MobileCarWashWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "My Appointments")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto py-12 px-4">
      <h1 class="text-3xl font-bold">My Appointments</h1>
      <p class="text-base-content/70 mt-4">Coming soon — manage your appointments here.</p>
    </div>
    """
  end
end
