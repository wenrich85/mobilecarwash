defmodule MobileCarWashWeb.Api.V1.VehiclesController do
  @moduledoc "CRUD-lite endpoints for a customer's vehicles."
  use MobileCarWashWeb, :controller

  alias MobileCarWash.Fleet.Vehicle

  require Ash.Query

  plug MobileCarWashWeb.Plugs.RequireApiAuth
  action_fallback MobileCarWashWeb.Api.V1.FallbackController

  def index(conn, _params) do
    customer = current_customer(conn)

    vehicles =
      Vehicle
      |> Ash.Query.filter(customer_id == ^customer.id)
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.read!(actor: customer)
      |> Enum.map(&vehicle_json/1)

    json(conn, %{data: vehicles})
  end

  def create(conn, params) do
    customer = current_customer(conn)

    attrs = %{
      make: params["make"],
      model: params["model"],
      year: parse_int(params["year"]),
      color: params["color"],
      size: parse_size(params["size"])
    }

    with {:ok, vehicle} <-
           Vehicle
           |> Ash.Changeset.for_create(:create, attrs)
           |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
           |> Ash.create() do
      conn
      |> put_status(:created)
      |> json(vehicle_json(vehicle))
    end
  end

  defp vehicle_json(v) do
    %{
      id: v.id,
      make: v.make,
      model: v.model,
      year: v.year,
      color: v.color,
      size: v.size,
      customer_id: v.customer_id
    }
  end

  defp current_customer(conn) do
    conn.assigns[:current_user] || conn.assigns[:current_customer]
  end

  defp parse_int(nil), do: nil
  defp parse_int(n) when is_integer(n), do: n

  defp parse_int(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, _} -> n
      _ -> nil
    end
  end

  defp parse_size(nil), do: nil
  defp parse_size(atom) when is_atom(atom), do: atom

  defp parse_size(s) when is_binary(s) do
    case s do
      "car" -> :car
      "suv_van" -> :suv_van
      "pickup" -> :pickup
      _ -> nil
    end
  end
end
