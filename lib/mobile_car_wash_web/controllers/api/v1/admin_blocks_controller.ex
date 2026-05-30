defmodule MobileCarWashWeb.Api.V1.AdminBlocksController do
  @moduledoc """
  Admin appointment block endpoints for native clients.
  """
  use MobileCarWashWeb, :controller

  alias MobileCarWash.Scheduling.{AppointmentBlock, BlockGenerator, BlockOptimizer}

  require Ash.Query

  plug MobileCarWashWeb.Plugs.RequireApiAuth
  plug :require_admin
  action_fallback MobileCarWashWeb.Api.V1.FallbackController

  def index(conn, _params) do
    json(conn, %{data: Enum.map(upcoming_blocks(), &block_json/1)})
  end

  def generate(conn, %{"technician_id" => technician_id}) do
    :ok = BlockGenerator.generate_ahead(14, technician_id: technician_id)

    json(conn, %{data: Enum.map(upcoming_blocks(), &block_json/1)})
  end

  def optimize(conn, %{"id" => id}) do
    with {:ok, _block} <- BlockOptimizer.close_and_optimize(id),
         {:ok, block} <- loaded_block(id) do
      json(conn, %{data: block_json(block)})
    else
      {:error, :block_not_found} -> {:error, :not_found}
      other -> other
    end
  end

  def cancel(conn, %{"id" => id}) do
    with {:ok, block} <- Ash.get(AppointmentBlock, id, authorize?: false),
         {:ok, updated} <-
           block
           |> Ash.Changeset.for_update(:update, %{status: :cancelled})
           |> Ash.update(authorize?: false),
         {:ok, loaded} <- Ash.load(updated, [:service_type, :technician, :appointment_count]) do
      json(conn, %{data: block_json(loaded)})
    end
  end

  def close(conn, %{"id" => id, "closes_at" => closes_at}) do
    with {:ok, parsed_closes_at} <- parse_datetime(closes_at),
         {:ok, block} <- Ash.get(AppointmentBlock, id, authorize?: false),
         {:ok, updated} <-
           block
           |> Ash.Changeset.for_update(:update, %{closes_at: parsed_closes_at})
           |> Ash.update(authorize?: false),
         {:ok, loaded} <- Ash.load(updated, [:service_type, :technician, :appointment_count]) do
      json(conn, %{data: block_json(loaded)})
    end
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

  defp loaded_block(id) do
    AppointmentBlock
    |> Ash.get(id, load: [:service_type, :technician, :appointment_count], authorize?: false)
  end

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      {:error, reason} -> {:error, reason}
    end
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
