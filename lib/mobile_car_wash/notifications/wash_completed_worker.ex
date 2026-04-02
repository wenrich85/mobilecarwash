defmodule MobileCarWash.Notifications.WashCompletedWorker do
  @moduledoc "Sends wash completed summary email to the customer."
  use Oban.Worker, queue: :notifications, max_attempts: 3

  alias MobileCarWash.Notifications.Email
  alias MobileCarWash.Scheduling.{Appointment, ServiceType}
  alias MobileCarWash.Accounts.Customer

  require Logger

  @impl true
  def perform(%Oban.Job{args: %{"appointment_id" => appointment_id}}) do
    with {:ok, appt} <- Ash.get(Appointment, appointment_id),
         {:ok, customer} <- Ash.get(Customer, appt.customer_id, authorize?: false),
         {:ok, service} <- Ash.get(ServiceType, appt.service_type_id) do
      Email.wash_completed(customer, appt, service.name)
      |> MobileCarWash.Mailer.deliver()

      :ok
    else
      {:error, reason} ->
        Logger.error("Failed to send wash completed email: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
