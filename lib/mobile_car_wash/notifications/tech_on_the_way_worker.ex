defmodule MobileCarWash.Notifications.TechOnTheWayWorker do
  @moduledoc """
  Email worker that fires when the appointment transitions to :en_route
  (tech tapped "Heading out" on the dashboard).
  """
  use Oban.Worker, queue: :notifications, max_attempts: 3

  alias MobileCarWash.Notifications.Email
  alias MobileCarWash.Scheduling.{Appointment, ServiceType}
  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Operations.Technician

  require Logger

  @impl true
  def perform(%Oban.Job{args: %{"appointment_id" => appointment_id}}) do
    with {:ok, appointment} <- Ash.get(Appointment, appointment_id, authorize?: false),
         {:ok, customer} <- Ash.get(Customer, appointment.customer_id, authorize?: false),
         {:ok, service_type} <-
           Ash.get(ServiceType, appointment.service_type_id, authorize?: false),
         true <- not is_nil(appointment.technician_id),
         {:ok, technician} <-
           Ash.get(Technician, appointment.technician_id, authorize?: false) do
      Email.tech_on_the_way(customer, appointment, service_type.name, technician.name)
      |> MobileCarWash.Mailer.deliver()

      :ok
    else
      false ->
        Logger.info("Tech-on-the-way email skipped: no technician assigned")
        :ok

      {:error, reason} ->
        Logger.error("Failed to send tech-on-the-way email: #{inspect(reason)}")
        :ok
    end
  end
end
