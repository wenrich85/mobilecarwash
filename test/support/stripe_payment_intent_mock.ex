defmodule MobileCarWash.Billing.StripePaymentIntentMock do
  @moduledoc """
  Test mock for `Stripe.PaymentIntent`. Records calls in ETS and returns a
  canned response with a fake client_secret that mobile tests can assert on.
  """

  @table :stripe_payment_intent_mock_calls

  def init do
    ensure_table()
    :ets.delete_all_objects(@table)
  end

  def create(params, _opts \\ []) do
    ensure_table()
    id = "pi_test_#{System.unique_integer([:positive])}"
    client_secret = "#{id}_secret_test"
    :ets.insert(@table, {:create, id, params})
    {:ok, %{id: id, client_secret: client_secret, amount: params[:amount]}}
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
