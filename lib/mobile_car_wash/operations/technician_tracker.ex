defmodule MobileCarWash.Operations.TechnicianTracker do
  @moduledoc """
  Real-time technician duty-status broadcasts.

  Two topics:
    * `technician:<id>:status` — per-tech feed; the tech's own dashboard
      subscribes here (mostly for multi-tab consistency).
    * `technicians:status` — firehose of every tech's status changes;
      admin dispatch subscribes here to keep the "Techs on shift" strip
      live.

  Payload: `{:technician_status, %{technician_id, status, name, updated_at}}`.
  """

  alias Phoenix.PubSub

  @pubsub MobileCarWash.PubSub

  def subscribe(technician_id) do
    PubSub.subscribe(@pubsub, per_tech_topic(technician_id))
  end

  def subscribe_all do
    PubSub.subscribe(@pubsub, global_topic())
  end

  def broadcast_status(%{} = technician) do
    message =
      {:technician_status,
       %{
         technician_id: technician.id,
         name: Map.get(technician, :name),
         status: technician.status,
         updated_at: technician.updated_at
       }}

    PubSub.broadcast(@pubsub, per_tech_topic(technician.id), message)
    PubSub.broadcast(@pubsub, global_topic(), message)
  end

  defp per_tech_topic(technician_id), do: "technician:#{technician_id}:status"
  defp global_topic, do: "technicians:status"
end
