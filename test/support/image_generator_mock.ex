defmodule MobileCarWash.AI.ImageGeneratorMock do
  @moduledoc """
  Test mock for `ImageGenerator`. ETS-backed — same pattern as
  `VisionClientMock`. Tests never hit OpenAI.

  Two modes:

    * `stub/2` — set a function that computes the response on each call
    * Default — returns `{:ok, "https://placehold.co/1024"}`

  Exposes `prompts/0` so tests can assert on what was sent.
  """

  @calls :image_gen_mock_calls
  @stub :image_gen_mock_stub

  def reset do
    ensure_table(@calls, :bag)
    ensure_table(@stub, :set)
    :ets.delete_all_objects(@calls)
    :ets.delete_all_objects(@stub)
  end

  @doc """
  Stub the behavior of a function on the mock. Currently only
  supports :generate.
  """
  def stub(:generate, fun) when is_function(fun, 1) do
    ensure_table(@stub, :set)
    :ets.insert(@stub, {:generate, fun})
  end

  def generate(prompt) do
    ensure_table(@calls, :bag)
    ensure_table(@stub, :set)
    :ets.insert(@calls, {:generate, prompt, System.monotonic_time()})

    case :ets.lookup(@stub, :generate) do
      [{:generate, fun}] -> fun.(prompt)
      _ -> {:ok, "https://placehold.co/1024?text=persona"}
    end
  end

  def prompts do
    ensure_table(@calls, :bag)

    @calls
    |> :ets.tab2list()
    |> Enum.filter(fn {kind, _, _} -> kind == :generate end)
    |> Enum.sort_by(fn {_, _, mono} -> mono end)
    |> Enum.map(fn {_, prompt, _} -> prompt end)
  end

  defp ensure_table(table, type) do
    if :ets.whereis(table) == :undefined do
      :ets.new(table, [:named_table, :public, type])
    end
  end
end
