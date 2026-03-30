defmodule MobileCarWash.CatalogBroadcaster do
  @moduledoc """
  Broadcasts catalog changes (services, plans) so all connected LiveViews
  reload fresh data without a page refresh.
  """
  alias Phoenix.PubSub

  @pubsub MobileCarWash.PubSub
  @topic "catalog:updates"

  def subscribe do
    PubSub.subscribe(@pubsub, @topic)
  end

  def broadcast_services_updated do
    PubSub.broadcast(@pubsub, @topic, :services_updated)
  end

  def broadcast_plans_updated do
    PubSub.broadcast(@pubsub, @topic, :plans_updated)
  end
end
