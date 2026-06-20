defmodule MobileCarWash.Vehicles.NhtsaClientMock do
  @moduledoc """
  Test mock for `NhtsaClient`. Tests stage canned responses with
  `put_vin/2` and `put_models/3`; the client delegates here in test env so
  no NHTSA network call is ever made. Backed by a named ETS table.

  Note: This mock uses its own ETS table keyed by original-case make+year,
  independent of `NhtsaCache`'s downcased-make cache scheme.
  """
  @table :nhtsa_mock

  def init do
    ensure_table()
    :ets.delete_all_objects(@table)
  end

  def put_vin(vin, result), do: insert({:vin, vin}, result)
  def put_models(make, year, models), do: insert({:models, make, to_string(year)}, models)

  def put_models_error(make, year, reason),
    do: insert({:models, make, to_string(year)}, {:error, reason})

  def decode_vin(vin) do
    case lookup({:vin, vin}) do
      {:ok, result} -> result
      :miss -> {:error, :vin_not_decoded}
    end
  end

  def models_for_make_year(make, year) do
    case lookup({:models, make, to_string(year)}) do
      {:ok, {:error, _} = err} -> err
      {:ok, models} -> {:ok, models}
      :miss -> {:ok, []}
    end
  end

  defp insert(key, value) do
    ensure_table()
    :ets.insert(@table, {key, value})
    value
  end

  defp lookup(key) do
    ensure_table()

    case :ets.lookup(@table, key) do
      [{^key, value}] -> {:ok, value}
      _ -> :miss
    end
  end

  defp ensure_table do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :public, :set])
    end
  end
end
