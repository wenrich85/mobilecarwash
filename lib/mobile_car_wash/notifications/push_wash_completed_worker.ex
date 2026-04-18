defmodule MobileCarWash.Notifications.PushWashCompletedWorker do
  @moduledoc """
  "Wash complete" push. Enqueued from the appointment's `:complete`
  after-action hook, alongside the SMS equivalent.
  """
  use Oban.Worker, queue: :notifications, max_attempts: 3

  require Logger

  alias MobileCarWash.Scheduling.{Appointment, ServiceType}
  alias MobileCarWash.Notifications.Push

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"appointment_id" => appointment_id}}) do
    with {:ok, appointment} <- Ash.get(Appointment, appointment_id, authorize?: false),
         {:ok, service_type} <-
           Ash.get(ServiceType, appointment.service_type_id, authorize?: false) do
      Push.wash_completed(appointment, service_type)
      |> then(&Push.send_to_customer(appointment.customer_id, &1))
    else
      {:error, reason} ->
        Logger.error("Push wash_completed data load failed: #{inspect(reason)}")
        :ok
    end
  end
end
