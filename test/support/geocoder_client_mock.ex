defmodule MobileCarWash.Fleet.GeocoderClientMock do
  @moduledoc """
  Test mock for `GeocoderClient`. Tests stage canned suggestions with
  `put_suggestions/2`; the client delegates here in test env so no geocoder
  network call is ever made. Backed by a named ETS table.

  Mirrors `Vehicles.NhtsaClientMock`.
  """
  @table :geocoder_mock

  def init do
    ensure_table()
    :ets.delete_all_objects(@table)
  end

  def put_suggestions(query, suggestions), do: insert({:suggest, query}, suggestions)

  def put_error(query, reason), do: insert({:suggest, query}, {:error, reason})

  def suggest(query) do
    case lookup({:suggest, query}) do
      {:ok, {:error, _} = err} -> err
      {:ok, suggestions} -> {:ok, suggestions}
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
