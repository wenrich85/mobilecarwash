defmodule MobileCarWashWeb.Api.V1.AppointmentsController do
  @moduledoc """
  Read-only endpoints for an authenticated customer's appointments.
  Upcoming list + individual detail. The mobile app polls `show` for status
  updates (tech en-route, in progress, completed).
  """
  use MobileCarWashWeb, :controller

  alias MobileCarWash.Scheduling.Appointment

  require Ash.Query

  plug MobileCarWashWeb.Plugs.RequireApiAuth
  action_fallback MobileCarWashWeb.Api.V1.FallbackController

  def index(conn, _params) do
    customer = current_customer(conn)
    now = DateTime.utc_now()

    appointments =
      Appointment
      |> Ash.Query.filter(
        customer_id == ^customer.id and
          status in [:pending, :confirmed, :in_progress] and
          scheduled_at > ^now
      )
      |> Ash.Query.sort(scheduled_at: :asc)
      |> Ash.read!(actor: customer)
      |> Enum.map(&appointment_json/1)

    json(conn, %{data: appointments})
  end

  def show(conn, %{"id" => id}) do
    customer = current_customer(conn)

    case Ash.get(Appointment, id, actor: customer) do
      {:ok, %{customer_id: cid} = appt} when cid == customer.id ->
        json(conn, appointment_json(appt))

      _ ->
        conn |> put_status(:not_found) |> json(%{error: "not_found"})
    end
  end

  defp appointment_json(a) do
    %{
      id: a.id,
      status: a.status,
      scheduled_at: a.scheduled_at,
      duration_minutes: a.duration_minutes,
      price_cents: a.price_cents,
      discount_cents: a.discount_cents,
      notes: a.notes,
      appointment_block_id: a.appointment_block_id,
      service_type_id: a.service_type_id,
      vehicle_id: a.vehicle_id,
      address_id: a.address_id,
      route_position: a.route_position
    }
  end

  defp current_customer(conn) do
    conn.assigns[:current_user] || conn.assigns[:current_customer]
  end
end
