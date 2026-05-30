defmodule MobileCarWashWeb.Api.V1.AdminTagsController do
  @moduledoc """
  Admin tag options for native command center clients.
  """
  use MobileCarWashWeb, :controller

  alias MobileCarWash.Marketing.Tag

  require Ash.Query

  plug MobileCarWashWeb.Plugs.RequireApiAuth
  plug :require_admin
  action_fallback MobileCarWashWeb.Api.V1.FallbackController

  def index(conn, _params) do
    tags =
      Tag
      |> Ash.Query.sort(name: :asc)
      |> Ash.read!(authorize?: false)

    json(conn, %{data: Enum.map(tags, &tag_json/1)})
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

  defp tag_json(tag) do
    %{
      id: tag.id,
      slug: tag.slug,
      name: tag.name,
      description: tag.description,
      color: to_string(tag.color),
      icon: tag.icon,
      affects_booking: tag.affects_booking,
      protected: tag.protected,
      active: tag.active
    }
  end

  defp current_user(conn), do: conn.assigns[:current_user] || conn.assigns[:current_customer]
end
