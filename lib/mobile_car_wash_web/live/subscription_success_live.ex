defmodule MobileCarWashWeb.SubscriptionSuccessLive do
  use MobileCarWashWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Subscription Active!")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-lg mx-auto py-16 px-4 text-center">
      <div class="text-6xl mb-6">&#10003;</div>
      <h1 class="text-3xl font-bold mb-4">Subscription Active!</h1>
      <p class="text-base-content/60 mb-8">
        Your subscription is now active. You can manage it anytime from your account.
        Subscription benefits will be automatically applied when you book your next wash.
      </p>
      <div class="flex gap-4 justify-center">
        <.link navigate={~p"/account/subscription"} class="btn btn-primary">
          View My Plan
        </.link>
        <.link navigate={~p"/book"} class="btn btn-outline">
          Book a Wash
        </.link>
      </div>
    </div>
    """
  end
end
