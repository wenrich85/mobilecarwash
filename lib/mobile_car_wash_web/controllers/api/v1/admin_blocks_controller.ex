defmodule MobileCarWashWeb.Api.V1.AdminBlocksController do
  @moduledoc """
  Admin appointment block endpoints for native clients.
  """
  use MobileCarWashWeb, :controller

  alias MobileCarWash.Scheduling.AppointmentBlock

  require Ash.Query

  plug MobileCarWashWeb.Plugs.RequireApiAuth
  plug :require_admin
  action_fallback MobileCarWashWeb.Api.V1.FallbackController

  def index(conn, _params) do
    json(conn, %{data: Enum.map(upcoming_blocks(), &block_json/1)})
  end

  defp require_admin(conn, _opts) do
    case current_user(conn) do
      %{role: :admin} ->
        conn

      _ ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "forbidden", message: "Admin role required"})
        |> halt()
    end
  end

  defp upcoming_blocks do
    today =
      Date.utc_today()
      |> DateTime.new!(~T[00:00:00], "Etc/UTC")

    AppointmentBlock
    |> Ash.Query.filter(starts_at >= ^today)
    |> Ash.Query.sort(starts_at: :asc)
    |> Ash.Query.load([:service_type, :technician, :appointment_count])
    |> Ash.read!(authorize?: false)
  end

  defp block_json(block) do
    appointment_count = block.appointment_count || 0

    %{
      id: block.id,
      service_type_id: block.service_type_id,
      service_name: block.service_type.name,
      technician_id: block.technician_id,
      technician_name: block.technician.name,
      starts_at: DateTime.to_iso8601(block.starts_at),
      ends_at: DateTime.to_iso8601(block.ends_at),
      closes_at: DateTime.to_iso8601(block.closes_at),
      capacity: block.capacity,
      appointment_count: appointment_count,
      spots_left: max(block.capacity - appointment_count, 0),
      status: to_string(block.status)
    }
  end

  defp current_user(conn), do: conn.assigns[:current_user] || conn.assigns[:current_customer]
end
