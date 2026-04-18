defmodule MobileCarWashWeb.Api.V1.BlocksController do
  @moduledoc """
  Lists open AppointmentBlocks for a given service across a date range.
  Used by the mobile app's window picker.
  """
  use MobileCarWashWeb, :controller

  alias MobileCarWash.Scheduling.BlockAvailability

  plug MobileCarWashWeb.Plugs.RequireApiAuth
  action_fallback MobileCarWashWeb.Api.V1.FallbackController

  def index(conn, %{"service_id" => service_id} = params) do
    with {:ok, from_date} <- parse_date(params["from"], Date.utc_today()),
         {:ok, to_date} <- parse_date(params["to"], Date.add(from_date, 14)) do
      blocks =
        service_id
        |> BlockAvailability.open_blocks_for_service_range(from_date, to_date)
        |> Enum.map(&block_json/1)

      json(conn, %{data: blocks})
    end
  end

  def index(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "service_id is required"})
  end

  defp block_json(b) do
    %{
      id: b.id,
      service_type_id: b.service_type_id,
      starts_at: b.starts_at,
      ends_at: b.ends_at,
      closes_at: b.closes_at,
      capacity: b.capacity,
      appointment_count: b.appointment_count,
      spots_left: b.capacity - b.appointment_count,
      status: b.status
    }
  end

  defp parse_date(nil, default), do: {:ok, default}

  defp parse_date(str, _default) when is_binary(str) do
    Date.from_iso8601(str)
  end
end
