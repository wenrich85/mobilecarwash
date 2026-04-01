defmodule MobileCarWash.CashFlow.Broadcaster do
  @moduledoc """
  PubSub broadcaster for cash flow updates.
  Notifies all connected LiveViews when balances change.
  """
  @pubsub MobileCarWash.PubSub
  @topic "cash_flow:updates"

  def subscribe do
    Phoenix.PubSub.subscribe(@pubsub, @topic)
  end

  def broadcast_updated do
    Phoenix.PubSub.broadcast(@pubsub, @topic, :cash_flow_updated)
  end
end
