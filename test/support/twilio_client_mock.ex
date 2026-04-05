defmodule MobileCarWash.Notifications.TwilioClientMock do
  @moduledoc """
  Test mock for TwilioClient. Stores sent messages in an ETS table
  so tests can assert on params across Oban inline process boundaries.
  """

  @table :twilio_mock_messages

  def init do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :public, :bag])
    end

    :ets.delete_all_objects(@table)
  end

  def send_sms(to, body) do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :public, :bag])
    end

    :ets.insert(@table, {to, body})
    {:ok, "SM_mock_#{System.unique_integer([:positive])}"}
  end

  def messages do
    if :ets.whereis(@table) == :undefined, do: [], else: :ets.tab2list(@table)
  end

  def messages_to(phone) do
    messages() |> Enum.filter(fn {to, _body} -> to == phone end)
  end
end
