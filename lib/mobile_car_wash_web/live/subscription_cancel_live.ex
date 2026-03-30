defmodule MobileCarWashWeb.SubscriptionCancelLive do
  use MobileCarWashWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Subscription Not Completed")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-lg mx-auto py-16 px-4 text-center">
      <h1 class="text-3xl font-bold mb-4">Subscription Not Completed</h1>
      <p class="text-base-content/60 mb-8">
        No worries — you weren't charged. You can subscribe anytime.
      </p>
      <div class="flex gap-4 justify-center">
        <.link navigate={~p"/subscribe"} class="btn btn-primary">
          Try Again
        </.link>
        <.link navigate={~p"/"} class="btn btn-ghost">
          Back to Home
        </.link>
      </div>
    </div>
    """
  end
end
