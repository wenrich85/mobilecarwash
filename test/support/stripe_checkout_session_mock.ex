defmodule MobileCarWash.Billing.StripeCheckoutSessionMock do
  @moduledoc """
  Test mock for `Stripe.Checkout.Session`. Returns a canned checkout URL so
  LiveView tests can assert on a redirect without hitting the real Stripe API.
  """

  @table :stripe_checkout_session_mock_calls

  def init do
    ensure_table()
    :ets.delete_all_objects(@table)
  end

  def create(params, _opts \\ []) do
    ensure_table()
    id = "cs_test_#{System.unique_integer([:positive])}"
    url = "https://checkout.stripe.com/pay/#{id}"
    :ets.insert(@table, {:create, id, params})
    {:ok, %{id: id, url: url}}
  end

  def retrieve(id, _params \\ %{}, _opts \\ []) do
    {:ok, %{id: id}}
  end

  def calls, do: ensure_table() && :ets.tab2list(@table)

  defp ensure_table do
    try do
      :ets.new(@table, [:named_table, :public, :bag])
    rescue
      ArgumentError -> :ok
    end

    true
  end
end
