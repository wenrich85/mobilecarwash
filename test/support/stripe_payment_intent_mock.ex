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

  def create(params, opts \\ [])

  def create(%{off_session: true, payment_method: "pm_decline"}, _opts) do
    {:error,
     %Stripe.Error{
       source: :stripe,
       code: :card_error,
       message: "Your card was declined.",
       extra: %{card_code: :card_declined, decline_code: "generic_decline"}
     }}
  end

  def create(%{off_session: true} = params, _opts) do
    ensure_table()
    id = "pi_test_#{System.unique_integer([:positive])}"
    :ets.insert(@table, {:create, id, params})

    {:ok,
     %{id: id, status: "succeeded", amount: params[:amount], client_secret: "#{id}_secret_test"}}
  end

  def create(params, _opts) do
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
