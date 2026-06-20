defmodule MobileCarWash.Vehicles.NhtsaCache do
  @moduledoc """
  In-memory ETS TTL cache for NHTSA vPIC responses (makes/models).
  In-memory only — re-warms from the API after a restart. Keeps the
  vehicle dropdowns instant and limits external calls.

  Degrades gracefully: if the cache table is absent (e.g. this GenServer
  has not started yet, or has crashed and not been restarted), `get/1`
  reports a miss and `put/3` is a no-op, so callers fall back to a live
  API call instead of crashing the booking flow.
  """
  use GenServer

  @table :nhtsa_cache
  @default_ttl_ms :timer.hours(24 * 30)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Fetch a cached value. Returns {:ok, value} on a live hit, :miss otherwise."
  @spec get(term()) :: {:ok, term()} | :miss
  def get(key) do
    if :ets.whereis(@table) == :undefined do
      :miss
    else
      case :ets.lookup(@table, key) do
        [{^key, value, expires_at}] ->
          if System.monotonic_time(:millisecond) < expires_at, do: {:ok, value}, else: :miss

        _ ->
          :miss
      end
    end
  end

  @doc """
  Store a value with a TTL (default ~30 days). Returns the value.

  A no-op (still returns the value) when the cache table is absent.
  """
  @spec put(term(), term(), non_neg_integer()) :: term()
  def put(key, value, ttl_ms \\ @default_ttl_ms) do
    if :ets.whereis(@table) != :undefined do
      expires_at = System.monotonic_time(:millisecond) + ttl_ms
      :ets.insert(@table, {key, value, expires_at})
    end

    value
  end

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, %{}}
  end
end
