defmodule MobileCarWashWeb.Api.V1.AdminVansController do
  @moduledoc """
  Admin van endpoints for native clients.
  """
  use MobileCarWashWeb, :controller

  alias MobileCarWash.Operations.Van

  require Ash.Query

  plug MobileCarWashWeb.Plugs.RequireApiAuth
  plug :require_admin
  action_fallback MobileCarWashWeb.Api.V1.FallbackController

  def index(conn, _params) do
    vans =
      Van
      |> Ash.Query.sort(name: :asc)
      |> Ash.read!(authorize?: false)

    json(conn, %{data: Enum.map(vans, &van_json/1)})
  end

  def create(conn, params) do
    attrs = %{
      name: params["name"],
      license_plate: blank_to_nil(params["license_plate"]),
      active: true
    }

    with {:ok, van} <-
           Van
           |> Ash.Changeset.for_create(:create, attrs)
           |> Ash.create(authorize?: false) do
      conn
      |> put_status(:created)
      |> json(%{data: van_json(van)})
    end
  end

  def update(conn, %{"id" => id} = params) do
    attrs = %{
      name: params["name"],
      license_plate: blank_to_nil(params["license_plate"])
    }

    with {:ok, van} <- Ash.get(Van, id, authorize?: false),
         {:ok, updated} <-
           van
           |> Ash.Changeset.for_update(:update, attrs)
           |> Ash.update(authorize?: false) do
      json(conn, %{data: van_json(updated)})
    end
  end

  def toggle(conn, %{"id" => id}) do
    with {:ok, van} <- Ash.get(Van, id, authorize?: false),
         {:ok, updated} <-
           van
           |> Ash.Changeset.for_update(:update, %{active: !van.active})
           |> Ash.update(authorize?: false) do
      json(conn, %{data: van_json(updated)})
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

  defp van_json(van) do
    %{
      id: van.id,
      name: van.name,
      license_plate: van.license_plate,
      active: van.active,
      inserted_at: DateTime.to_iso8601(van.inserted_at),
      updated_at: DateTime.to_iso8601(van.updated_at)
    }
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(value), do: value

  defp current_user(conn), do: conn.assigns[:current_user] || conn.assigns[:current_customer]
end
