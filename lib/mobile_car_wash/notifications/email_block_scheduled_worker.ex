defmodule MobileCarWash.Notifications.EmailBlockScheduledWorker do
  @moduledoc """
  Emails the customer their confirmed arrival window after the route optimizer
  assigns a time inside their booked block. Enqueued by `Scheduling.BlockOptimizer`.
  """
  use Oban.Worker, queue: :notifications, max_attempts: 3

  alias MobileCarWash.Scheduling.{Appointment, ServiceType}
  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Fleet.Address
  alias MobileCarWash.Notifications.Email
  alias MobileCarWash.Mailer

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"appointment_id" => appointment_id}}) do
    with {:ok, appointment} <- Ash.get(Appointment, appointment_id, authorize?: false),
         {:ok, service_type} <-
           Ash.get(ServiceType, appointment.service_type_id, authorize?: false),
         {:ok, customer} <- Ash.get(Customer, appointment.customer_id, authorize?: false),
         {:ok, address} <- Ash.get(Address, appointment.address_id, authorize?: false) do
      email = Email.block_scheduled(appointment, service_type, customer, address)

      case Mailer.deliver(email) do
        {:ok, _} ->
          :ok

        {:error, reason} ->
          Logger.error("Email block scheduled failed: #{inspect(reason)}")
          {:error, reason}
      end
    else
      {:error, reason} ->
        Logger.error("Email block scheduled data load failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
