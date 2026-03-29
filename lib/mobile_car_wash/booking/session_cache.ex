defmodule MobileCarWash.Booking.SessionCache do
  @moduledoc """
  ETS-backed cache for persisting booking progress across LiveView reconnects.
  Entries expire after 2 hours. Keyed by a stable session identifier.
  """
  use GenServer

  @table :booking_session_cache
  @ttl_ms :timer.hours(2)
  @cleanup_interval :timer.minutes(15)

  # --- Public API ---

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc "Store booking state for a session."
  def put(session_id, state) when is_binary(session_id) and is_map(state) do
    :ets.insert(@table, {session_id, state, System.monotonic_time(:millisecond)})
    :ok
  end

  @doc "Retrieve booking state for a session."
  def get(session_id) when is_binary(session_id) do
    case :ets.lookup(@table, session_id) do
      [{^session_id, state, inserted_at}] ->
        if System.monotonic_time(:millisecond) - inserted_at < @ttl_ms do
          state
        else
          :ets.delete(@table, session_id)
          nil
        end

      [] ->
        nil
    end
  end

  @doc "Delete booking state for a session."
  def delete(session_id) when is_binary(session_id) do
    :ets.delete(@table, session_id)
    :ok
  end

  # --- GenServer callbacks ---

  @impl true
  def init(_) do
    table = :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    schedule_cleanup()
    {:ok, %{table: table}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    now = System.monotonic_time(:millisecond)

    :ets.foldl(
      fn {session_id, _state, inserted_at}, acc ->
        if now - inserted_at >= @ttl_ms do
          :ets.delete(@table, session_id)
        end

        acc
      end,
      :ok,
      @table
    )

    schedule_cleanup()
    {:noreply, state}
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end
end
