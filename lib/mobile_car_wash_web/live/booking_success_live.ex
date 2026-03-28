defmodule MobileCarWashWeb.BookingSuccessLive do
  @moduledoc """
  Displayed after successful Stripe Checkout payment.
  Looks up the appointment via the Stripe session ID.
  """
  use MobileCarWashWeb, :live_view

  alias MobileCarWash.Billing.Payment
  alias MobileCarWash.Scheduling.{Appointment, ServiceType}

  @impl true
  def mount(%{"session_id" => session_id}, _session, socket) do
    payments =
      Ash.read!(Payment,
        action: :by_checkout_session,
        arguments: %{session_id: session_id}
      )

    case payments do
      [payment] ->
        appointment = Ash.get!(Appointment, payment.appointment_id)
        service_type = Ash.get!(ServiceType, appointment.service_type_id)

        {:ok,
         assign(socket,
           page_title: "Booking Confirmed",
           appointment: appointment,
           service_type: service_type,
           payment: payment
         )}

      [] ->
        {:ok,
         socket
         |> assign(page_title: "Booking", appointment: nil, service_type: nil, payment: nil)
         |> put_flash(:error, "Could not find your booking. Please contact support.")}
    end
  end

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Booking", appointment: nil, service_type: nil, payment: nil)
     |> put_flash(:error, "Missing session information.")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto py-12 px-4 text-center">
      <div :if={@appointment}>
        <div class="text-6xl mb-4 text-success">✓</div>
        <h1 class="text-3xl font-bold mb-4">Payment Successful!</h1>
        <p class="text-lg text-base-content/70 mb-8">
          Your {@service_type.name} is confirmed for
          {Calendar.strftime(@appointment.scheduled_at, "%B %d, %Y at %I:%M %p")}.
        </p>

        <div class="card bg-base-100 shadow-xl mx-auto max-w-md">
          <div class="card-body">
            <div class="space-y-3 text-left">
              <div><span class="font-semibold">Service:</span> {@service_type.name}</div>
              <div><span class="font-semibold">Amount Paid:</span> ${div(@payment.amount_cents, 100)}</div>
              <div><span class="font-semibold">Status:</span>
                <span class="badge badge-success">Confirmed</span>
              </div>
            </div>
            <p class="text-sm text-base-content/50 mt-4">Booking ID: {@appointment.id}</p>
          </div>
        </div>

        <p class="mt-8 text-base-content/70">
          A confirmation email has been sent. We'll also remind you 24 hours before your appointment.
        </p>

        <.link navigate={~p"/"} class="btn btn-primary mt-6">
          Back to Home
        </.link>
      </div>

      <div :if={!@appointment}>
        <h1 class="text-2xl font-bold mb-4">Booking Not Found</h1>
        <p class="text-base-content/70 mb-6">
          We couldn't locate your booking details. If you completed payment, please contact us.
        </p>
        <.link navigate={~p"/"} class="btn btn-primary">Back to Home</.link>
      </div>
    </div>
    """
  end
end
