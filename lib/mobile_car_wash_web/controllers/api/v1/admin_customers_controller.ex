defmodule MobileCarWashWeb.Api.V1.AdminCustomersController do
  @moduledoc """
  Admin-facing customer rows for native command center clients.
  """
  use MobileCarWashWeb, :controller

  alias MobileCarWash.Marketing.{AcquisitionChannel, CustomerTag, Tag}
  alias MobileCarWash.Reporting.CustomerList

  require Ash.Query

  plug MobileCarWashWeb.Plugs.RequireApiAuth
  plug :require_admin
  action_fallback MobileCarWashWeb.Api.V1.FallbackController

  @page_size 50

  def index(conn, params) do
    filters = %{
      q: params["q"],
      channel_id: params["channel"],
      role: params["role"],
      verified: params["verified"],
      tag_id: params["tag"]
    }

    customers =
      filters
      |> CustomerList.list_filtered()
      |> CustomerList.sort(params["sort"] || "joined_desc")
      |> Enum.take(@page_size)

    channels = load_channels(customers)
    tag_map = load_tags(customers)
    tag_reasons = load_tag_reasons(customers)

    data =
      Enum.map(customers, fn customer ->
        customer_json(customer, channels, tag_map, tag_reasons)
      end)

    json(conn, %{data: data})
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

  defp load_channels(customers) do
    ids =
      customers
      |> Enum.map(& &1.acquired_channel_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    load_map(AcquisitionChannel, ids)
  end

  defp load_tags(customers) do
    ids =
      customers
      |> Enum.flat_map(& &1.__tag_ids__)
      |> Enum.uniq()

    load_map(Tag, ids)
  end

  defp load_tag_reasons(customers) do
    customer_ids = customers |> Enum.map(& &1.id) |> Enum.uniq()
    tag_ids = customers |> Enum.flat_map(& &1.__tag_ids__) |> Enum.uniq()

    case {customer_ids, tag_ids} do
      {[], _} ->
        %{}

      {_, []} ->
        %{}

      _ ->
        CustomerTag
        |> Ash.Query.filter(customer_id in ^customer_ids and tag_id in ^tag_ids)
        |> Ash.read!(authorize?: false)
        |> Map.new(&{{&1.customer_id, &1.tag_id}, &1.reason})
    end
  end

  defp load_map(_resource, []), do: %{}

  defp load_map(resource, ids) do
    resource
    |> Ash.Query.filter(id in ^ids)
    |> Ash.read!(authorize?: false)
    |> Map.new(&{&1.id, &1})
  end

  defp customer_json(customer, channels, tag_map, tag_reasons) do
    channel = Map.get(channels, customer.acquired_channel_id)

    %{
      id: customer.id,
      email: to_string(customer.email),
      name: customer.name,
      phone: customer.phone,
      role: to_string(customer.role),
      verified: not is_nil(customer.email_verified_at),
      disabled: not is_nil(customer.disabled_at),
      acquired_channel_id: customer.acquired_channel_id,
      acquired_channel_name: channel && channel.display_name,
      inserted_at: customer.inserted_at,
      lifetime_revenue_cents: customer.__lifetime_revenue__ || 0,
      last_wash_at: customer.__last_wash_at__,
      tags: tags_json(customer, tag_map, tag_reasons)
    }
  end

  defp tags_json(customer, tag_map, tag_reasons) do
    Enum.flat_map(customer.__tag_ids__, fn tag_id ->
      case Map.get(tag_map, tag_id) do
        nil ->
          []

        tag ->
          [
            %{
              id: tag.id,
              name: tag.name,
              slug: tag.slug,
              color: to_string(tag.color),
              reason: Map.get(tag_reasons, {customer.id, tag.id})
            }
          ]
      end
    end)
  end

  defp current_user(conn), do: conn.assigns[:current_user] || conn.assigns[:current_customer]
end
