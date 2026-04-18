defmodule MobileCarWash.Notifications.ApnsClientMock do
  @moduledoc """
  Test mock for `ApnsClient`. Stores sent pushes in an ETS bag so tests can
  assert on payloads across Oban inline-process boundaries the same way
  `TwilioClientMock` does for SMS.

  Optional per-token response stubbing lets worker tests exercise the
  failure paths (`:unregistered`, `:bad_device_token`) that trigger
  `DeviceToken.mark_failed/1`.
  """

  @pushes :apns_mock_pushes
  @stubs :apns_mock_stubs

  def init do
    ensure_table(@pushes, :bag)
    ensure_table(@stubs, :set)
    :ets.delete_all_objects(@pushes)
    :ets.delete_all_objects(@stubs)
  end

  @doc """
  Queue a response for the next `push/3` call matching `token`.
  Stored as `{:ok, term()}` or `{:error, reason}`. Consumed once.
  """
  def stub(token, response) do
    ensure_table(@stubs, :set)
    :ets.insert(@stubs, {token, response})
  end

  def push(token, payload, opts \\ []) do
    ensure_table(@pushes, :bag)
    :ets.insert(@pushes, {token, payload, opts})

    case pop_stub(token) do
      nil -> {:ok, "apns_mock_id_#{System.unique_integer([:positive])}"}
      response -> response
    end
  end

  def pushes do
    ensure_table(@pushes, :bag)
    :ets.tab2list(@pushes)
  end

  def pushes_to(token) do
    pushes() |> Enum.filter(fn {t, _, _} -> t == token end)
  end

  defp pop_stub(token) do
    ensure_table(@stubs, :set)

    case :ets.lookup(@stubs, token) do
      [{^token, response}] ->
        :ets.delete(@stubs, token)
        response

      _ ->
        nil
    end
  end

  defp ensure_table(table, type) do
    if :ets.whereis(table) == :undefined do
      :ets.new(table, [:named_table, :public, type])
    end
  end
end
