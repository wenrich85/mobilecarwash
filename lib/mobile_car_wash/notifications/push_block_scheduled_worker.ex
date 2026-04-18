defmodule MobileCarWash.Notifications.PushBlockScheduledWorker do
  @moduledoc """
  Arrival-window-confirmed push. Enqueued by `Scheduling.BlockOptimizer`
  after the route optimizer assigns a specific arrival time inside the
  customer's booked block.
  """
  use Oban.Worker, queue: :notifications, max_attempts: 3

  require Logger

  alias MobileCarWash.Scheduling.{Appointment, ServiceType}
  alias MobileCarWash.Fleet.Address
  alias MobileCarWash.Notifications.Push

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"appointment_id" => appointment_id}}) do
    with {:ok, appointment} <- Ash.get(Appointment, appointment_id, authorize?: false),
         {:ok, service_type} <-
           Ash.get(ServiceType, appointment.service_type_id, authorize?: false),
         {:ok, address} <- Ash.get(Address, appointment.address_id, authorize?: false) do
      Push.block_scheduled(appointment, service_type, address)
      |> then(&Push.send_to_customer(appointment.customer_id, &1))
    else
      {:error, reason} ->
        Logger.error("Push block scheduled data load failed: #{inspect(reason)}")
        :ok
    end
  end
end
