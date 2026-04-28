defmodule MobileCarWashWeb.BookingSuccessLive do
  @moduledoc """
  Shown after a customer books — supports both Stripe Checkout return
  (?session_id=...) and in-app navigation from the :confirmed step
  (?id=<appointment_uuid>).
  """
  use MobileCarWashWeb, :live_view

  alias MobileCarWash.Billing.{Payment, Subscription}
  alias MobileCarWash.Scheduling.{Appointment, ServiceType}
  alias MobileCarWash.Fleet.Address
  alias MobileCarWash.Accounts.Customer

  @impl true
  def mount(%{"session_id" => session_id}, _session, socket) do
    case lookup_by_session(session_id) do
      {:ok, data} -> {:ok, assign_loaded(socket, data)}
      :error -> {:ok, assign_error(socket)}
    end
  end

  def mount(%{"id" => appointment_id}, _session, socket) do
    case lookup_by_appointment_id(appointment_id) do
      {:ok, data} -> {:ok, assign_loaded(socket, data)}
      :error -> {:ok, assign_error(socket)}
    end
  end

  def mount(_params, _session, socket) do
    {:ok, assign_error(socket)}
  end

  # === Private helpers ===

  defp lookup_by_session(session_id) do
    payments =
      Ash.read!(Payment,
        action: :by_checkout_session,
        arguments: %{session_id: session_id},
        authorize?: false
      )

    case payments do
      [payment] ->
        appointment = Ash.get!(Appointment, payment.appointment_id, authorize?: false)
        build_loaded(appointment, payment)

      _ ->
        :error
    end
  rescue
    _ -> :error
  end

  defp lookup_by_appointment_id(appointment_id) do
    appointment = Ash.get!(Appointment, appointment_id, authorize?: false)
    build_loaded(appointment, nil)
  rescue
    _ -> :error
  end

  defp build_loaded(appointment, payment) do
    service = Ash.get!(ServiceType, appointment.service_type_id, authorize?: false)

    address =
      case appointment.address_id do
        nil -> nil
        addr_id -> Ash.get!(Address, addr_id, authorize?: false)
      end

    customer =
      case appointment.customer_id do
        nil -> nil
        cust_id -> Ash.get!(Customer, cust_id, authorize?: false)
      end

    active_subscription =
      case customer do
        nil ->
          nil

        c ->
          case Subscription
               |> Ash.Query.for_read(:active_for_customer, %{customer_id: c.id})
               |> Ash.read!(authorize?: false) do
            [sub | _] -> sub
            [] -> nil
          end
      end

    {:ok,
     %{
       appointment: appointment,
       service: service,
       address: address,
       customer: customer,
       payment: payment,
       active_subscription: active_subscription
     }}
  end

  defp assign_loaded(socket, %{
         appointment: appt,
         service: service,
         address: address,
         customer: customer,
         payment: payment,
         active_subscription: sub
       }) do
    assign(socket,
      page_title: "Booking Confirmed",
      appointment: appt,
      service: service,
      address: address,
      customer: customer,
      payment: payment,
      active_subscription: sub,
      not_found: false
    )
  end

  defp assign_error(socket) do
    assign(socket,
      page_title: "Booking",
      appointment: nil,
      service: nil,
      address: nil,
      customer: nil,
      payment: nil,
      active_subscription: nil,
      not_found: true
    )
  end

  defp price_cents(nil, service), do: service.base_price_cents
  defp price_cents(payment, _service), do: payment.amount_cents

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-3xl mx-auto px-4 py-10 sm:py-14">
      <div :if={!@not_found}>
        <%!-- Confirmation strip --%>
        <div class="flex items-center gap-2 mb-6">
          <.icon name="hero-check-circle-solid" class="h-5 w-5 text-cyan-500" />
          <span class="text-xs font-semibold uppercase tracking-wide text-base-content/70">
            Booking confirmed
          </span>
        </div>

        <%!-- Appointment summary card --%>
        <div class="rounded-2xl border-t-4 border-cyan-500 bg-base-100 shadow-sm p-6 sm:p-8">
          <h1 class="text-2xl sm:text-3xl font-bold text-base-content">
            {Calendar.strftime(@appointment.scheduled_at, "%A, %B %-d at %-I:%M %p")}
          </h1>

          <%!-- Service + price chips --%>
          <div class="mt-4 flex flex-wrap items-center gap-2">
            <span class="inline-flex items-center px-3 py-1 rounded-full bg-base-200 text-sm font-medium text-base-content">
              {@service.name}
            </span>
            <span class="inline-flex items-center px-3 py-1 rounded-full bg-base-200 text-sm font-mono">
              ${div(price_cents(@payment, @service), 100)}
            </span>
          </div>

          <%!-- Address line --%>
          <div :if={@address} class="mt-5 flex items-start gap-2 text-base-content/80">
            <.icon name="hero-map-pin" class="h-5 w-5 shrink-0 mt-0.5 text-cyan-500" />
            <div class="text-sm leading-relaxed">
              <div>{@address.street}</div>
              <div>{@address.city}, {@address.state} {@address.zip}</div>
            </div>
          </div>

          <%!-- Technician line (conditional) --%>
          <p :if={@appointment.technician_id == nil} class="mt-5 text-sm text-base-content/60">
            We'll let you know once a technician is assigned.
          </p>
        </div>
      </div>

      <div :if={@not_found}>
        <h1 class="text-2xl font-bold mb-4">We couldn't find that booking.</h1>
        <p class="text-base-content/70 mb-6">
          If you completed payment, contact us and we'll sort it out — we have your details.
        </p>
        <.link navigate={~p"/"} class="btn btn-ghost">← Back to home</.link>
      </div>
    </div>
    """
  end
end
