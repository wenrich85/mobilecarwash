defmodule MobileCarWashWeb.Api.V1.TechController do
  @moduledoc """
  Tech-facing profile endpoints. The signed-in `Customer` with role
  `:technician` or `:admin` maps to a `Technician` record via
  `user_account_id` (falling back to name match for legacy records).
  """
  use MobileCarWashWeb, :controller

  alias MobileCarWash.Operations.Technician

  require Ash.Query

  plug MobileCarWashWeb.Plugs.RequireTechAuth
  action_fallback MobileCarWashWeb.Api.V1.FallbackController

  def me(conn, _params) do
    case find_tech(current_user(conn)) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "no_tech_record"})

      tech ->
        json(conn, %{data: tech_json(tech)})
    end
  end

  def update_status(conn, params) do
    user = current_user(conn)

    with tech when not is_nil(tech) <- find_tech(user),
         status_str when is_binary(status_str) <- params["status"],
         status_atom <- safe_status_atom(status_str),
         {:ok, updated} <-
           tech
           |> Ash.Changeset.for_update(:set_status, %{status: status_atom})
           |> Ash.update() do
      json(conn, %{data: tech_json(updated)})
    else
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "no_tech_record"})

      {:error, _} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "invalid_status"})

      _ ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "invalid_status"})
    end
  end

  # ----------------------------------------------------------------

  @valid_statuses ~w(off_duty available on_break)
  defp safe_status_atom(s) when s in @valid_statuses, do: String.to_existing_atom(s)
  defp safe_status_atom(_), do: :__invalid__

  defp find_tech(user) do
    techs = Ash.read!(Technician)

    Enum.find(techs, fn t -> t.user_account_id == user.id end) ||
      Enum.find(techs, fn t -> t.name == user.name end)
  end

  defp tech_json(tech) do
    %{
      id: tech.id,
      name: tech.name,
      status: to_string(tech.status),
      zone: tech.zone && to_string(tech.zone),
      active: tech.active
    }
  end

  defp current_user(conn), do: conn.assigns[:current_user] || conn.assigns[:current_customer]
end
