defmodule MobileCarWash.Vehicles.NhtsaCacheTest do
  # async: false — shared named ETS table started with the app
  use ExUnit.Case, async: false

  alias MobileCarWash.Vehicles.NhtsaCache

  test "put then get returns the cached value" do
    key = {:models, "toyota", "2021", System.unique_integer([:positive])}
    assert NhtsaCache.put(key, ["Camry", "Corolla"]) == ["Camry", "Corolla"]
    assert NhtsaCache.get(key) == {:ok, ["Camry", "Corolla"]}
  end

  test "get returns :miss for an unknown key" do
    assert NhtsaCache.get({:nope, System.unique_integer([:positive])}) == :miss
  end

  test "get returns :miss once the entry has expired" do
    key = {:models, "ford", "2020", System.unique_integer([:positive])}
    NhtsaCache.put(key, ["F-150"], 0)
    assert NhtsaCache.get(key) == :miss
  end
end
