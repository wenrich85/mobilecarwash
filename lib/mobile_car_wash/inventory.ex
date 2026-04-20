defmodule MobileCarWash.Inventory do
  @moduledoc """
  Supplies inventory management.
  Tracks on-hand quantities of chemicals, equipment, and disposables.
  Restocking automatically records a cash flow expense.
  """
  use Ash.Domain

  alias MobileCarWash.Inventory.{Supply, SupplyUsage}

  require Ash.Query

  resources do
    resource(Supply)
    resource(SupplyUsage)
  end

  @doc "All active supplies, sorted by category then name."
  def list_supplies do
    Supply
    |> Ash.Query.filter(active == true)
    |> Ash.Query.sort([:category, :name])
    |> Ash.read!()
  end

  @doc "All supplies including inactive."
  def list_all_supplies do
    Supply
    |> Ash.Query.sort([:category, :name])
    |> Ash.read!()
  end

  @doc "Supplies at or below their low_stock_threshold."
  def low_stock_supplies do
    list_supplies()
    |> Enum.filter(fn s ->
      s.low_stock_threshold != nil and
        Decimal.compare(s.quantity_on_hand, s.low_stock_threshold) != :gt
    end)
  end

  @doc """
  Restock a supply: add quantity and record the cost as a cash flow expense.
  `total_cost_cents` is what was actually paid (may differ from unit_cost × qty).
  """
  def restock(supply, quantity, total_cost_cents, notes \\ nil) do
    with {:ok, supply} <-
           supply
           |> Ash.Changeset.for_update(:restock, %{quantity: quantity})
           |> Ash.update() do
      # Record as a cash flow expense so the 5-bucket system stays accurate.
      if total_cost_cents > 0 do
        description = "Supply purchase — #{supply.name} (#{format_qty(quantity)} #{supply.unit})"
        description = if notes, do: "#{description}: #{notes}", else: description
        MobileCarWash.CashFlow.Engine.record_expense(total_cost_cents, description)
      end

      {:ok, supply}
    end
  end

  @doc """
  Log supply usage for a wash. Automatically decrements quantity_on_hand on the supply.
  `attrs` must include `:supply_id` and `:quantity_used`. Other fields are optional.
  """
  def log_usage(attrs) do
    SupplyUsage
    |> Ash.Changeset.for_create(:log, attrs)
    |> Ash.create(authorize?: false)
  end

  @doc "All usage records for a given appointment, newest first."
  def usage_for_appointment(appointment_id) do
    SupplyUsage
    |> Ash.Query.for_read(:for_appointment, %{appointment_id: appointment_id})
    |> Ash.Query.sort(occurred_at: :desc)
    |> Ash.read!(authorize?: false)
  end

  @doc "All usage records for a given technician, newest first."
  def usage_for_technician(technician_id) do
    SupplyUsage
    |> Ash.Query.for_read(:for_technician, %{technician_id: technician_id})
    |> Ash.Query.sort(occurred_at: :desc)
    |> Ash.read!(authorize?: false)
  end

  @doc "All usage records for a given van, newest first."
  def usage_for_van(van_id) do
    SupplyUsage
    |> Ash.Query.for_read(:for_van, %{van_id: van_id})
    |> Ash.Query.sort(occurred_at: :desc)
    |> Ash.read!(authorize?: false)
  end

  @doc "All usage records for a given supply, newest first."
  def usage_for_supply(supply_id) do
    SupplyUsage
    |> Ash.Query.for_read(:for_supply, %{supply_id: supply_id})
    |> Ash.Query.sort(occurred_at: :desc)
    |> Ash.read!(authorize?: false)
  end

  defp format_qty(qty) do
    f = Decimal.to_float(qty)
    if trunc(f) == f, do: "#{trunc(f)}", else: "#{Float.round(f, 2)}"
  end
end
