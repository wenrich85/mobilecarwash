defmodule MobileCarWash.Accounting.SyncWorker do
  @moduledoc """
  Oban worker that syncs completed payments to the accounting system.
  Runs asynchronously — accounting failures never block bookings.
  """
  use Oban.Worker, queue: :billing, max_attempts: 5

  alias MobileCarWash.Accounting
  alias MobileCarWash.Billing.Payment
  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Scheduling.{Appointment, ServiceType}

  require Logger

  @impl true
  def perform(%Oban.Job{args: %{"payment_id" => payment_id}}) do
    with {:ok, payment} <- Ash.get(Payment, payment_id),
         {:ok, customer} <- Ash.get(Customer, payment.customer_id, authorize?: false) do
      service_name = resolve_service_name(payment)
      Accounting.sync_payment(customer, payment, service_name)
    else
      {:error, reason} ->
        Logger.error("Accounting sync worker failed to load data: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp resolve_service_name(payment) do
    cond do
      payment.appointment_id ->
        case Ash.get(Appointment, payment.appointment_id) do
          {:ok, appt} ->
            case Ash.get(ServiceType, appt.service_type_id) do
              {:ok, svc} -> svc.name
              _ -> "Detailing Service"
            end

          _ ->
            "Detailing Service"
        end

      payment.subscription_id ->
        "Subscription Payment"

      true ->
        "Payment"
    end
  end
end
