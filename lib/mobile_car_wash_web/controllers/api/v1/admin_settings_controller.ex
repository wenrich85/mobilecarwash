defmodule MobileCarWashWeb.Api.V1.AdminSettingsController do
  @moduledoc """
  Admin settings endpoints for native clients.
  """
  use MobileCarWashWeb, :controller

  alias MobileCarWash.Scheduling.{BlockedDate, SchedulingSettings}

  require Ash.Query

  plug MobileCarWashWeb.Plugs.RequireApiAuth
  plug :require_admin
  action_fallback MobileCarWashWeb.Api.V1.FallbackController

  def show(conn, _params) do
    json(conn, %{
      data: %{
        scheduling: scheduling_json(SchedulingSettings.get()),
        blocked_dates: blocked_dates_json()
      }
    })
  end

  def update_scheduling(conn, params) do
    with {:ok, settings} <-
           SchedulingSettings.update(%{
             max_intra_block_drive_minutes: params["max_intra_block_drive_minutes"]
           }) do
      json(conn, %{data: scheduling_json(settings)})
    end
  end

  def create_blocked_date(conn, %{"date" => date_string} = params) do
    with {:ok, date} <- Date.from_iso8601(date_string),
         {:ok, blocked_date} <-
           BlockedDate
           |> Ash.Changeset.for_create(:create, %{date: date, reason: params["reason"]})
           |> Ash.create(authorize?: false) do
      conn
      |> put_status(:created)
      |> json(%{data: blocked_date_json(blocked_date)})
    else
      {:error, :invalid_format} -> {:error, :invalid_date}
      {:error, :missing_format} -> {:error, :invalid_date}
      {:error, :invalid_date} -> {:error, :invalid_date}
      other -> other
    end
  end

  def delete_blocked_date(conn, %{"id" => id}) do
    with {:ok, blocked_date} <- Ash.get(BlockedDate, id, authorize?: false),
         :ok <- Ash.destroy(blocked_date, authorize?: false) do
      send_resp(conn, :no_content, "")
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

  defp blocked_dates_json do
    BlockedDate
    |> Ash.Query.sort(date: :asc)
    |> Ash.read!(authorize?: false)
    |> Enum.map(&blocked_date_json/1)
  end

  defp scheduling_json(settings) do
    %{
      max_intra_block_drive_minutes: settings.max_intra_block_drive_minutes
    }
  end

  defp blocked_date_json(blocked_date) do
    %{
      id: blocked_date.id,
      date: Date.to_iso8601(blocked_date.date),
      reason: blocked_date.reason
    }
  end

  defp current_user(conn), do: conn.assigns[:current_user] || conn.assigns[:current_customer]
end
