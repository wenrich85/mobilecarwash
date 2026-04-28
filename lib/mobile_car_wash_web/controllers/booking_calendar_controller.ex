defmodule MobileCarWashWeb.BookingCalendarController do
  @moduledoc """
  Serves an iCalendar (.ics) file for a booked appointment so the customer
  can drop it into Apple Calendar / any RFC 5545–capable client. Linked
  from the BookingSuccessLive "Download .ics" button.
  """
  use MobileCarWashWeb, :controller

  alias MobileCarWash.Scheduling.{Appointment, ServiceType}
  alias MobileCarWash.Fleet.Address

  def show(conn, %{"id" => appointment_id}) do
    case load_appointment(appointment_id) do
      {:ok, appointment, service, address} ->
        body = build_ics(appointment, service, address)

        conn
        |> put_resp_header("content-type", "text/calendar; charset=utf-8")
        |> put_resp_header(
          "content-disposition",
          ~s|attachment; filename="booking-#{appointment.id}.ics"|
        )
        |> send_resp(200, body)

      :error ->
        conn
        |> put_status(:not_found)
        |> text("Booking not found.")
    end
  end

  # === Private helpers ===

  defp load_appointment(appointment_id) do
    appointment = Ash.get!(Appointment, appointment_id, authorize?: false)
    service = Ash.get!(ServiceType, appointment.service_type_id, authorize?: false)

    address =
      case appointment.address_id do
        nil -> nil
        addr_id -> Ash.get!(Address, addr_id, authorize?: false)
      end

    {:ok, appointment, service, address}
  rescue
    _ -> :error
  end

  defp build_ics(appointment, service, address) do
    duration = appointment.duration_minutes || 90

    dtstart =
      appointment.scheduled_at
      |> DateTime.shift_zone!("Etc/UTC")
      |> Calendar.strftime("%Y%m%dT%H%M%SZ")

    dtend =
      appointment.scheduled_at
      |> DateTime.add(duration * 60, :second)
      |> DateTime.shift_zone!("Etc/UTC")
      |> Calendar.strftime("%Y%m%dT%H%M%SZ")

    dtstamp =
      DateTime.utc_now()
      |> Calendar.strftime("%Y%m%dT%H%M%SZ")

    location = format_address(address)

    [
      "BEGIN:VCALENDAR",
      "VERSION:2.0",
      "PRODID:-//Driveway Detail Co//Booking//EN",
      "CALSCALE:GREGORIAN",
      "METHOD:PUBLISH",
      "BEGIN:VEVENT",
      "UID:#{appointment.id}@drivewaydetailcosa.com",
      "DTSTAMP:#{dtstamp}",
      "DTSTART:#{dtstart}",
      "DTEND:#{dtend}",
      "SUMMARY:#{service.name}",
      "DESCRIPTION:Booking ID: #{appointment.id}\\nService: #{service.name}\\nWe'll text you 30 minutes before arrival.",
      "LOCATION:#{location}",
      "STATUS:CONFIRMED",
      "END:VEVENT",
      "END:VCALENDAR"
    ]
    |> Enum.join("\r\n")
    |> Kernel.<>("\r\n")
  end

  defp format_address(nil), do: ""

  defp format_address(address) do
    "#{address.street}, #{address.city}, #{address.state} #{address.zip}"
  end
end
