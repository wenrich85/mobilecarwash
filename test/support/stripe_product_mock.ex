defmodule MobileCarWash.Billing.StripeProductMock do
  @moduledoc """
  Test mock for `Stripe.Product`. Stores calls in ETS so tests can assert
  on params across process boundaries (Oban inline, etc.).
  """

  @table :stripe_product_mock_calls

  def init do
    ensure_table()
    :ets.delete_all_objects(@table)
  end

  def create(params, _opts \\ []) do
    ensure_table()
    id = "prod_test_#{System.unique_integer([:positive])}"
    :ets.insert(@table, {:create, id, params})
    {:ok, %{id: id, name: params[:name], active: Map.get(params, :active, true)}}
  end

  def update(id, params, _opts \\ []) do
    ensure_table()
    :ets.insert(@table, {:update, id, params})
    {:ok, %{id: id}}
  end

  def retrieve(id, _params \\ %{}, _opts \\ []) do
    {:ok, %{id: id}}
  end

  def calls, do: ensure_table() && :ets.tab2list(@table)

  def calls(kind) do
    calls() |> Enum.filter(fn {k, _, _} -> k == kind end)
  end

  defp ensure_table do
    try do
      :ets.new(@table, [:named_table, :public, :bag])
    rescue
      ArgumentError -> :ok
    end

    true
  end
end
