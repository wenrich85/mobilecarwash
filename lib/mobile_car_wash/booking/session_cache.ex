defmodule MobileCarWash.Booking.SessionCache do
  @moduledoc """
  Database-backed cache for persisting booking progress across LiveView reconnects.
  Entries expire after 2 hours. Keyed by a stable session identifier.

  Uses PostgreSQL instead of ETS — survives restarts and supports horizontal scaling.
  """

  alias MobileCarWash.Repo
  import Ecto.Query

  @ttl_hours 2

  @doc "Store booking state for a session."
  def put(session_id, state) when is_binary(session_id) and is_map(state) do
    now = DateTime.utc_now()
    data = :erlang.term_to_binary(state) |> Base.encode64()

    Repo.insert_all(
      "booking_sessions",
      [%{session_id: session_id, data: data, inserted_at: now, updated_at: now}],
      on_conflict: {:replace, [:data, :updated_at]},
      conflict_target: :session_id
    )

    :ok
  rescue
    _ -> :ok
  end

  @doc "Retrieve booking state for a session."
  def get(session_id) when is_binary(session_id) do
    cutoff = DateTime.add(DateTime.utc_now(), -@ttl_hours, :hour)

    case Repo.one(
           from(bs in "booking_sessions",
             where: bs.session_id == ^session_id and bs.updated_at > ^cutoff,
             select: bs.data
           )
         ) do
      nil ->
        nil

      data ->
        data |> Base.decode64!() |> :erlang.binary_to_term([:safe])
    end
  rescue
    _ -> nil
  end

  @doc "Delete booking state for a session."
  def delete(session_id) when is_binary(session_id) do
    Repo.delete_all(from(bs in "booking_sessions", where: bs.session_id == ^session_id))
    :ok
  rescue
    _ -> :ok
  end

  @doc "Clean up expired sessions. Called by Oban cron job."
  def cleanup_expired do
    cutoff = DateTime.add(DateTime.utc_now(), -@ttl_hours, :hour)
    {count, _} = Repo.delete_all(from(bs in "booking_sessions", where: bs.updated_at <= ^cutoff))
    {:ok, count}
  end
end
