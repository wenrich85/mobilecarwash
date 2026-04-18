defmodule MobileCarWash.Notifications.Push do
  @moduledoc """
  Builds APNs push-notification payloads for customer lifecycle events.

  Each function returns a JSON-serializable map with the APNs-reserved
  `aps` dict plus a `data` object for the iOS app to deep-link from.

  Payload budget is 4 KB; keep titles ≤ ~40 chars and bodies ≤ ~120 chars
  so they render cleanly on a lock screen.
  """

  @doc """
  Booking confirmed — fires after Stripe payment succeeds, mirroring the
  SMS confirmation path in `Scheduling.Booking.complete_payment/2`.
  """
  def booking_confirmation(appointment, service_type, _address) do
    time = format_time(appointment.scheduled_at)
    date = format_date(appointment.scheduled_at)

    %{
      aps: %{
        alert: %{
          title: "Booking confirmed",
          body: "Your #{service_type.name} is booked for #{date} at #{time}."
        },
        sound: "default",
        "thread-id": "booking-#{appointment.id}"
      },
      data: %{
        kind: "booking_confirmed",
        appointment_id: appointment.id,
        deep_link: "drivewaydetail://appointments/#{appointment.id}"
      }
    }
  end

  defp format_time(datetime), do: Calendar.strftime(datetime, "%-I:%M %p")
  defp format_date(datetime), do: Calendar.strftime(datetime, "%b %-d")
end
