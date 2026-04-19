defmodule MobileCarWash.AI.VisionClientMock do
  @moduledoc """
  Test mock for `VisionClient`. ETS-backed — same pattern as
  `TwilioClientMock` and `ApnsClientMock`. Lets tests stub a response
  per image URL and inspect the calls that flowed through.
  """

  @calls :vision_mock_calls
  @stubs :vision_mock_stubs

  def init do
    ensure_table(@calls, :bag)
    ensure_table(@stubs, :set)
    :ets.delete_all_objects(@calls)
    :ets.delete_all_objects(@stubs)
  end

  @doc "Queue a success response for the next call matching `image_url`."
  def stub_success(image_url, tags_map) do
    ensure_table(@stubs, :set)
    :ets.insert(@stubs, {image_url, {:ok, tags_map}})
  end

  @doc "Queue an error response for the next call matching `image_url`."
  def stub_error(image_url, reason) do
    ensure_table(@stubs, :set)
    :ets.insert(@stubs, {image_url, {:error, reason}})
  end

  def classify(image_url, prompt) do
    ensure_table(@calls, :bag)
    :ets.insert(@calls, {image_url, prompt})

    case pop_stub(image_url) do
      nil -> {:ok, %{"is_vehicle_photo" => false}}
      response -> response
    end
  end

  def calls do
    ensure_table(@calls, :bag)
    :ets.tab2list(@calls)
  end

  defp pop_stub(image_url) do
    ensure_table(@stubs, :set)

    case :ets.lookup(@stubs, image_url) do
      [{^image_url, response}] ->
        :ets.delete(@stubs, image_url)
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
