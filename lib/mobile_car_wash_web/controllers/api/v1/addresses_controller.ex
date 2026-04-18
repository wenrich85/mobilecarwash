defmodule MobileCarWashWeb.Api.V1.AddressesController do
  @moduledoc "CRUD-lite endpoints for a customer's service addresses."
  use MobileCarWashWeb, :controller

  alias MobileCarWash.Fleet.Address

  require Ash.Query

  plug MobileCarWashWeb.Plugs.RequireApiAuth
  action_fallback MobileCarWashWeb.Api.V1.FallbackController

  def index(conn, _params) do
    customer = current_customer(conn)

    addresses =
      Address
      |> Ash.Query.filter(customer_id == ^customer.id)
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.read!(actor: customer)
      |> Enum.map(&address_json/1)

    json(conn, %{data: addresses})
  end

  def create(conn, params) do
    customer = current_customer(conn)

    attrs =
      %{
        street: params["street"],
        city: params["city"],
        state: params["state"] || "TX",
        zip: params["zip"],
        is_default: params["is_default"] || false
      }
      |> maybe_put(:latitude, parse_float(params["latitude"]))
      |> maybe_put(:longitude, parse_float(params["longitude"]))

    with {:ok, address} <-
           Address
           |> Ash.Changeset.for_create(:create, attrs)
           |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
           |> Ash.create() do
      conn
      |> put_status(:created)
      |> json(address_json(address))
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp address_json(a) do
    %{
      id: a.id,
      street: a.street,
      city: a.city,
      state: a.state,
      zip: a.zip,
      latitude: a.latitude,
      longitude: a.longitude,
      zone: a.zone,
      is_default: a.is_default,
      customer_id: a.customer_id
    }
  end

  defp current_customer(conn) do
    conn.assigns[:current_user] || conn.assigns[:current_customer]
  end

  defp parse_float(nil), do: nil
  defp parse_float(n) when is_number(n), do: n * 1.0

  defp parse_float(s) when is_binary(s) do
    case Float.parse(s) do
      {n, _} -> n
      _ -> nil
    end
  end
end
