defmodule MobileCarWash.Notifications.PushTechOnTheWayWorker do
  @moduledoc """
  "Tech is on the way" push. Enqueued from the appointment's `:start`
  after-action hook, alongside the SMS equivalent.

  No-ops if the appointment has no technician assigned (an unusual edge
  case — SMS worker has the same guard).
  """
  use Oban.Worker, queue: :notifications, max_attempts: 3

  require Logger

  alias MobileCarWash.Scheduling.Appointment
  alias MobileCarWash.Operations.Technician
  alias MobileCarWash.Notifications.Push

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"appointment_id" => appointment_id}}) do
    with {:ok, appointment} <- Ash.get(Appointment, appointment_id, authorize?: false),
         true <- not is_nil(appointment.technician_id),
         {:ok, technician} <- Ash.get(Technician, appointment.technician_id, authorize?: false) do
      Push.tech_on_the_way(appointment, technician)
      |> then(&Push.send_to_customer(appointment.customer_id, &1))
    else
      false ->
        Logger.info("Push tech_on_the_way skipped: no technician assigned")
        :ok

      {:error, reason} ->
        Logger.error("Push tech_on_the_way data load failed: #{inspect(reason)}")
        :ok
    end
  end
end
