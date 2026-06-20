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

  # Regression: a stale boot (server started before this GenServer was added
  # to the supervision tree) or a crashed cache leaves the ETS table absent.
  # get/put must degrade gracefully instead of raising and crashing the
  # booking LiveView. We stop the supervised child to remove its table
  # deterministically (ETS table lifecycle ops require ownership, so the test
  # process cannot just delete it), then restart it to restore state.
  test "get/put degrade gracefully when the cache table is absent" do
    :ok = Supervisor.terminate_child(MobileCarWash.Supervisor, NhtsaCache)
    assert :ets.whereis(:nhtsa_cache) == :undefined

    key = {:models, "bmw", "2025"}
    assert NhtsaCache.get(key) == :miss
    # put is a no-op but still returns the value (no crash, nothing cached)
    assert NhtsaCache.put(key, ["X5", "M3"]) == ["X5", "M3"]
    assert NhtsaCache.get(key) == :miss

    {:ok, _pid} = Supervisor.restart_child(MobileCarWash.Supervisor, NhtsaCache)
    assert :ets.whereis(:nhtsa_cache) != :undefined
  end
end
