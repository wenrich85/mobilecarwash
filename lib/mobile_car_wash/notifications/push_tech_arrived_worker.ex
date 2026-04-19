defmodule MobileCarWash.Notifications.PushTechArrivedWorker do
  @moduledoc """
  Push worker that fires when the appointment transitions to :on_site.
  Skips gracefully when no technician is assigned (edge case).
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
         {:ok, technician} <-
           Ash.get(Technician, appointment.technician_id, authorize?: false) do
      Push.tech_arrived(appointment, technician)
      |> then(&Push.send_to_customer(appointment.customer_id, &1))
    else
      false ->
        Logger.info("Push tech_arrived skipped: no technician assigned")
        :ok

      {:error, reason} ->
        Logger.error("Push tech_arrived data load failed: #{inspect(reason)}")
        :ok
    end
  end
end
