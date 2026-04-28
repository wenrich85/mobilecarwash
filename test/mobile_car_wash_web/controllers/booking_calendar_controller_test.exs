defmodule MobileCarWashWeb.BookingCalendarControllerTest do
  @moduledoc """
  Verifies the GET /book/:id/calendar.ics endpoint that backs the
  "Download .ics" button on the booking success page.
  """
  use MobileCarWashWeb.ConnCase, async: false

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Fleet.{Address, Vehicle}
  alias MobileCarWash.Scheduling.{Appointment, ServiceType}

  defp setup_appointment do
    {:ok, customer} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "ics-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "ICS Test",
        phone: "+15125558700"
      })
      |> Ash.create()

    {:ok, service} =
      ServiceType
      |> Ash.Changeset.for_create(:create, %{
        name: "Premium Detail",
        slug: "ics-svc-#{System.unique_integer([:positive])}",
        base_price_cents: 8_900,
        duration_minutes: 90
      })
      |> Ash.create()

    {:ok, vehicle} =
      Vehicle
      |> Ash.Changeset.for_create(:create, %{make: "BMW", model: "M3"})
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create()

    {:ok, address} =
      Address
      |> Ash.Changeset.for_create(:create, %{
        street: "1717 ICS Lane",
        city: "San Antonio",
        state: "TX",
        zip: "78261"
      })
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create()

    {:ok, appt} =
      Appointment
      |> Ash.Changeset.for_create(:book, %{
        customer_id: customer.id,
        vehicle_id: vehicle.id,
        address_id: address.id,
        service_type_id: service.id,
        scheduled_at: DateTime.add(DateTime.utc_now(), 3 * 86_400, :second),
        price_cents: 8_900,
        duration_minutes: 90
      })
      |> Ash.create()

    {appt, service, address}
  end

  describe "GET /book/:id/calendar.ics" do
    test "returns 200 with text/calendar content type", %{conn: conn} do
      {appt, _service, _address} = setup_appointment()

      conn = get(conn, ~p"/book/#{appt.id}/calendar.ics")

      assert conn.status == 200

      content_type =
        conn
        |> Plug.Conn.get_resp_header("content-type")
        |> List.first()

      assert content_type =~ "text/calendar"
    end

    test "body contains VCALENDAR scaffolding + service name + UTC DTSTART", %{conn: conn} do
      {appt, service, _address} = setup_appointment()

      conn = get(conn, ~p"/book/#{appt.id}/calendar.ics")
      body = conn.resp_body

      assert body =~ "BEGIN:VCALENDAR"
      assert body =~ "END:VCALENDAR"
      assert body =~ "BEGIN:VEVENT"
      assert body =~ "END:VEVENT"
      assert body =~ "SUMMARY:#{service.name}"

      expected_dtstart =
        appt.scheduled_at
        |> DateTime.shift_zone!("Etc/UTC")
        |> Calendar.strftime("%Y%m%dT%H%M%SZ")

      assert body =~ "DTSTART:#{expected_dtstart}"
    end

    test "body contains the full address as LOCATION", %{conn: conn} do
      {appt, _service, address} = setup_appointment()

      conn = get(conn, ~p"/book/#{appt.id}/calendar.ics")
      body = conn.resp_body

      assert body =~ "LOCATION:#{address.street}"
      assert body =~ address.city
      assert body =~ address.zip
    end

    test "Content-Disposition is attachment with booking-<id>.ics filename", %{conn: conn} do
      {appt, _service, _address} = setup_appointment()

      conn = get(conn, ~p"/book/#{appt.id}/calendar.ics")

      disposition =
        conn
        |> Plug.Conn.get_resp_header("content-disposition")
        |> List.first()

      assert disposition =~ "attachment"
      assert disposition =~ "booking-#{appt.id}.ics"
    end

    test "returns 404 for unknown id", %{conn: conn} do
      bogus_id = Ecto.UUID.generate()

      conn = get(conn, ~p"/book/#{bogus_id}/calendar.ics")

      assert conn.status == 404
    end
  end
end
