defmodule MobileCarWashWeb.Api.V1.AdminScheduleTemplatesController do
  @moduledoc """
  Admin schedule template endpoints for native clients.
  """
  use MobileCarWashWeb, :controller

  alias MobileCarWash.Scheduling.BlockTemplate

  require Ash.Query

  @days_of_week %{
    1 => "Monday",
    2 => "Tuesday",
    3 => "Wednesday",
    4 => "Thursday",
    5 => "Friday",
    6 => "Saturday",
    7 => "Sunday"
  }

  plug MobileCarWashWeb.Plugs.RequireApiAuth
  plug :require_admin
  action_fallback MobileCarWashWeb.Api.V1.FallbackController

  def index(conn, _params) do
    json(conn, %{data: Enum.map(list_templates(), &template_json/1)})
  end

  def create(conn, params) do
    attrs = %{
      service_type_id: params["service_type_id"],
      day_of_week: params["day_of_week"],
      start_hour: params["start_hour"],
      active: true
    }

    with {:ok, template} <-
           BlockTemplate
           |> Ash.Changeset.for_create(:create, attrs)
           |> Ash.create(authorize?: false),
         {:ok, loaded} <- Ash.load(template, [:service_type]) do
      conn
      |> put_status(:created)
      |> json(%{data: template_json(loaded)})
    end
  end

  def toggle(conn, %{"id" => id}) do
    with {:ok, template} <- Ash.get(BlockTemplate, id, authorize?: false),
         {:ok, updated} <-
           template
           |> Ash.Changeset.for_update(:update, %{active: !template.active})
           |> Ash.update(authorize?: false),
         {:ok, loaded} <- Ash.load(updated, [:service_type]) do
      json(conn, %{data: template_json(loaded)})
    end
  end

  def delete(conn, %{"id" => id}) do
    with {:ok, template} <- Ash.get(BlockTemplate, id, authorize?: false),
         :ok <- Ash.destroy(template, authorize?: false) do
      json(conn, %{ok: true})
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

  defp list_templates do
    BlockTemplate
    |> Ash.Query.sort([:day_of_week, :start_hour])
    |> Ash.Query.load([:service_type])
    |> Ash.read!(authorize?: false)
  end

  defp template_json(template) do
    %{
      id: template.id,
      service_type_id: template.service_type_id,
      service_name: template.service_type.name,
      day_of_week: template.day_of_week,
      day_name: Map.fetch!(@days_of_week, template.day_of_week),
      start_hour: template.start_hour,
      active: template.active
    }
  end

  defp current_user(conn), do: conn.assigns[:current_user] || conn.assigns[:current_customer]
end
