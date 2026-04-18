defmodule MobileCarWash.Scheduling.BlockOptimizer do
  @moduledoc """
  Closes an AppointmentBlock and computes its route.

  Greedy nearest-neighbor from the shop origin. Each appointment gets:
    * `scheduled_at` — actual ETA (block.starts_at + accumulated drive + prior service)
    * `route_position` — 1..N order

  Then the block moves to `:scheduled` and each customer is texted their
  confirmed arrival time.
  """
  alias MobileCarWash.Scheduling.{Appointment, AppointmentBlock, ServiceType}
  alias MobileCarWash.Fleet.Address
  alias MobileCarWash.Operations.ShopConfig
  alias MobileCarWash.Routing.Haversine
  alias MobileCarWash.Notifications.{PushBlockScheduledWorker, SMSBlockScheduledWorker}
  alias MobileCarWash.Zones

  require Ash.Query

  @doc """
  Closes and optimizes a block. Returns `{:ok, block}`, `{:error, :already_optimized}`,
  or `{:error, :block_not_found}`.
  """
  def close_and_optimize(block_id) do
    with {:ok, block} <- fetch_block(block_id),
         :ok <- require_open(block) do
      appointments = load_appointments(block)
      service_type = service_type_for(block)

      ordered = order_nearest_neighbor(appointments)
      schedule_appointments(ordered, block, service_type)

      {:ok, updated} = mark_scheduled(block)
      enqueue_notifications(ordered)

      {:ok, updated}
    end
  end

  # --- Internals ---

  defp fetch_block(id) do
    case Ash.get(AppointmentBlock, id) do
      {:ok, block} -> {:ok, block}
      _ -> {:error, :block_not_found}
    end
  end

  defp require_open(%{status: :open}), do: :ok
  defp require_open(_), do: {:error, :already_optimized}

  defp load_appointments(block) do
    Appointment
    |> Ash.Query.filter(appointment_block_id == ^block.id)
    |> Ash.read!()
    |> Enum.map(fn appt ->
      {:ok, address} = Ash.get(Address, appt.address_id)
      Map.put(appt, :address, address)
    end)
  end

  defp service_type_for(block) do
    {:ok, st} = Ash.get(ServiceType, block.service_type_id)
    st
  end

  defp order_nearest_neighbor(appointments) do
    {ordered, _} =
      Enum.reduce(1..length(appointments)//1, {[], {appointments, ShopConfig.origin()}}, fn
        _i, {acc, {remaining, current_pos}} ->
          next = Enum.min_by(remaining, fn a -> travel_minutes_from(current_pos, a) end)
          rest = List.delete(remaining, next)
          {[next | acc], {rest, coords_for(next.address)}}
      end)

    Enum.reverse(ordered)
  end

  defp travel_minutes_from(pos, appt) do
    Haversine.travel_minutes(pos, coords_for(appt.address))
  end

  defp coords_for(address) do
    case Zones.coordinates_for_address(address) do
      {lat, lng} -> {lat, lng}
      nil -> ShopConfig.origin()
    end
  end

  defp schedule_appointments(ordered, block, service_type) do
    duration_sec = service_type.duration_minutes * 60

    {_, _} =
      Enum.with_index(ordered, 1)
      |> Enum.reduce({ShopConfig.origin(), block.starts_at}, fn {appt, position}, {pos, time} ->
        travel_sec = Haversine.travel_minutes(pos, coords_for(appt.address)) * 60
        arrival = DateTime.add(time, travel_sec, :second)

        {:ok, _} =
          appt
          |> Ash.Changeset.for_update(:update, %{})
          |> Ash.Changeset.force_change_attribute(:scheduled_at, arrival)
          |> Ash.Changeset.force_change_attribute(:route_position, position)
          |> Ash.update()

        {coords_for(appt.address), DateTime.add(arrival, duration_sec, :second)}
      end)

    :ok
  end

  defp mark_scheduled(block) do
    block
    |> Ash.Changeset.for_update(:update, %{status: :scheduled})
    |> Ash.update()
  end

  defp enqueue_notifications(appointments) do
    Enum.each(appointments, fn appt ->
      %{appointment_id: appt.id}
      |> SMSBlockScheduledWorker.new(queue: :notifications)
      |> Oban.insert()

      %{appointment_id: appt.id}
      |> PushBlockScheduledWorker.new(queue: :notifications)
      |> Oban.insert()
    end)
  end
end
