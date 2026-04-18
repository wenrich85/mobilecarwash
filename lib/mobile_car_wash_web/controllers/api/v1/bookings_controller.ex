defmodule MobileCarWashWeb.Api.V1.BookingsController do
  @moduledoc """
  Creates a booking for the authenticated customer into an AppointmentBlock.
  Returns the new appointment and a Stripe PaymentIntent client_secret the
  mobile Payment Sheet uses to complete payment.
  """
  use MobileCarWashWeb, :controller

  alias MobileCarWash.Scheduling.Booking

  plug MobileCarWashWeb.Plugs.RequireApiAuth
  action_fallback MobileCarWashWeb.Api.V1.FallbackController

  def create(conn, params) do
    customer = current_customer(conn)

    booking_params =
      %{
        customer_id: customer.id,
        service_type_id: params["service_type_id"],
        vehicle_id: params["vehicle_id"],
        address_id: params["address_id"],
        payment_flow: :mobile
      }
      |> maybe_put(:appointment_block_id, params["appointment_block_id"])
      |> maybe_put(:subscription_id, params["subscription_id"])
      |> maybe_put(:loyalty_redeem, params["loyalty_redeem"])
      |> maybe_put(:referral_code, params["referral_code"])
      |> maybe_put(:notes, params["notes"])

    case Booking.create_booking(booking_params) do
      {:ok, %{appointment: appt} = result} ->
        conn
        |> put_status(:created)
        |> json(%{
          appointment: appointment_json(appt),
          payment_intent_client_secret: result[:payment_intent_client_secret]
        })

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: to_string(reason)})
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

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
