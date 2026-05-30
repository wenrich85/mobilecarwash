defmodule MobileCarWashWeb.Api.V1.AdminSuppliesController do
  @moduledoc """
  Admin supply inventory endpoints for native clients.
  """
  use MobileCarWashWeb, :controller

  alias MobileCarWash.Inventory
  alias MobileCarWash.Inventory.Supply

  require Ash.Query

  plug MobileCarWashWeb.Plugs.RequireApiAuth
  plug :require_admin
  action_fallback MobileCarWashWeb.Api.V1.FallbackController

  @categories %{
    "chemicals" => :chemicals,
    "equipment" => :equipment,
    "disposables" => :disposables,
    "safety" => :safety,
    "other" => :other
  }

  def index(conn, _params) do
    supplies =
      Supply
      |> Ash.Query.sort([:category, :name])
      |> Ash.read!(authorize?: false)

    json(conn, %{data: Enum.map(supplies, &supply_json/1)})
  end

  def create(conn, params) do
    with {:ok, attrs} <- supply_attrs(params, include_quantity?: true),
         {:ok, supply} <-
           Supply
           |> Ash.Changeset.for_create(:create, attrs)
           |> Ash.create(authorize?: false) do
      conn
      |> put_status(:created)
      |> json(%{data: supply_json(supply)})
    end
  end

  def update(conn, %{"id" => id} = params) do
    with {:ok, attrs} <- supply_attrs(params, include_quantity?: false),
         {:ok, supply} <- Ash.get(Supply, id, authorize?: false),
         {:ok, updated} <-
           supply
           |> Ash.Changeset.for_update(:update, attrs)
           |> Ash.update(authorize?: false) do
      json(conn, %{data: supply_json(updated)})
    end
  end

  def restock(conn, %{"id" => id, "quantity" => quantity} = params) do
    with {:ok, quantity} <- parse_positive_decimal(quantity),
         {:ok, supply} <- Ash.get(Supply, id, authorize?: false),
         {:ok, updated} <-
           Inventory.restock(
             supply,
             quantity,
             params["total_cost_cents"] || 0,
             blank_to_nil(params["notes"])
           ) do
      json(conn, %{data: supply_json(updated)})
    end
  end

  def use_supply(conn, %{"id" => id, "quantity" => quantity}) do
    with {:ok, quantity} <- parse_positive_decimal(quantity),
         {:ok, supply} <- Ash.get(Supply, id, authorize?: false),
         {:ok, updated} <-
           supply
           |> Ash.Changeset.for_update(:use_quantity, %{quantity: quantity})
           |> Ash.update(authorize?: false) do
      json(conn, %{data: supply_json(updated)})
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

  defp supply_attrs(params, opts) do
    include_quantity? = Keyword.fetch!(opts, :include_quantity?)

    with {:ok, category} <- category(params["category"] || "other"),
         {:ok, quantity_on_hand} <-
           quantity_on_hand(params["quantity_on_hand"], include_quantity?),
         {:ok, low_stock_threshold} <- parse_decimal_or_nil(params["low_stock_threshold"]),
         {:ok, active} <- parse_active(params, include_quantity?) do
      attrs = %{
        name: params["name"],
        category: category,
        unit: blank_default(params["unit"], "units"),
        low_stock_threshold: low_stock_threshold,
        unit_cost_cents: params["unit_cost_cents"],
        supplier: blank_to_nil(params["supplier"]),
        notes: blank_to_nil(params["notes"])
      }

      attrs =
        if is_nil(active), do: attrs, else: Map.put(attrs, :active, active)

      attrs =
        if include_quantity? do
          Map.put(attrs, :quantity_on_hand, quantity_on_hand)
        else
          attrs
        end

      {:ok, attrs}
    end
  end

  defp category(value) when is_binary(value) do
    case Map.fetch(@categories, value) do
      {:ok, category} -> {:ok, category}
      :error -> {:error, :invalid_category}
    end
  end

  defp category(_value), do: {:error, :invalid_category}

  defp quantity_on_hand(_value, false), do: {:ok, nil}
  defp quantity_on_hand(nil, true), do: {:ok, Decimal.new(0)}
  defp quantity_on_hand("", true), do: {:ok, Decimal.new(0)}
  defp quantity_on_hand(value, true), do: parse_decimal(value)

  defp parse_decimal_or_nil(nil), do: {:ok, nil}
  defp parse_decimal_or_nil(""), do: {:ok, nil}
  defp parse_decimal_or_nil(value), do: parse_decimal(value)

  defp parse_positive_decimal(value) do
    with {:ok, decimal} <- parse_decimal(value),
         true <- Decimal.gt?(decimal, Decimal.new(0)) do
      {:ok, decimal}
    else
      _ -> {:error, :invalid_quantity}
    end
  end

  defp parse_decimal(%Decimal{} = decimal), do: {:ok, decimal}
  defp parse_decimal(value) when is_integer(value), do: {:ok, Decimal.new(value)}

  defp parse_decimal(value) when is_binary(value) do
    case Decimal.parse(value) do
      {decimal, ""} -> {:ok, decimal}
      _ -> {:error, :invalid_decimal}
    end
  end

  defp parse_decimal(_value), do: {:error, :invalid_decimal}

  defp parse_active(params, true) do
    params
    |> Map.get("active", true)
    |> boolean()
  end

  defp parse_active(params, false) do
    params
    |> Map.get("active", nil)
    |> boolean()
  end

  defp boolean(nil), do: {:ok, nil}
  defp boolean(value) when is_boolean(value), do: {:ok, value}
  defp boolean("true"), do: {:ok, true}
  defp boolean("false"), do: {:ok, false}
  defp boolean(_value), do: {:error, :invalid_boolean}

  defp supply_json(supply) do
    %{
      id: supply.id,
      name: supply.name,
      category: to_string(supply.category),
      unit: supply.unit,
      quantity_on_hand: decimal_string(supply.quantity_on_hand),
      low_stock_threshold: decimal_string(supply.low_stock_threshold),
      unit_cost_cents: supply.unit_cost_cents,
      supplier: supply.supplier,
      notes: supply.notes,
      active: supply.active,
      low_stock: low_stock?(supply)
    }
  end

  defp low_stock?(%{low_stock_threshold: nil}), do: false

  defp low_stock?(supply) do
    Decimal.compare(supply.quantity_on_hand, supply.low_stock_threshold) != :gt
  end

  defp decimal_string(nil), do: nil
  defp decimal_string(decimal), do: Decimal.to_string(decimal, :normal)

  defp blank_default("", default), do: default
  defp blank_default(nil, default), do: default
  defp blank_default(value, _default), do: value

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(value), do: value

  defp current_user(conn), do: conn.assigns[:current_user] || conn.assigns[:current_customer]
end
