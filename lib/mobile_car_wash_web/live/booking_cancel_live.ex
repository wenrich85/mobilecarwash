defmodule MobileCarWashWeb.BookingCancelLive do
  @moduledoc """
  Displayed when a customer cancels Stripe Checkout.
  Offers the option to retry booking.
  """
  use MobileCarWashWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Payment Cancelled")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto py-12 px-4 text-center">
      <div class="text-6xl mb-4">✕</div>
      <h1 class="text-3xl font-bold mb-4">Payment Cancelled</h1>
      <p class="text-lg text-base-content/70 mb-8">
        Your payment was not completed. Your appointment has not been confirmed.
      </p>

      <div class="flex gap-4 justify-center">
        <.link navigate={~p"/book"} class="btn btn-primary">
          Try Again
        </.link>
        <.link navigate={~p"/"} class="btn btn-outline">
          Back to Home
        </.link>
      </div>
    </div>
    """
  end
end
