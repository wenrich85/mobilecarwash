defmodule MobileCarWash.Notifications.PaymentReceiptWorker do
  @moduledoc "Sends payment receipt emails after successful payments."
  use Oban.Worker, queue: :notifications, max_attempts: 3

  alias MobileCarWash.Notifications.Email
  alias MobileCarWash.Billing.Payment
  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Scheduling.{Appointment, ServiceType}

  require Logger

  @impl true
  def perform(%Oban.Job{args: %{"payment_id" => payment_id}}) do
    with {:ok, payment} <- Ash.get(Payment, payment_id),
         {:ok, customer} <- Ash.get(Customer, payment.customer_id, authorize?: false) do
      service_name =
        if payment.appointment_id do
          case Ash.get(Appointment, payment.appointment_id) do
            {:ok, appt} ->
              case Ash.get(ServiceType, appt.service_type_id) do
                {:ok, svc} -> svc.name
                _ -> "Detailing Service"
              end
            _ -> "Detailing Service"
          end
        else
          "Subscription Payment"
        end

      Email.payment_receipt(customer, payment, service_name)
      |> MobileCarWash.Mailer.deliver()

      :ok
    else
      {:error, reason} ->
        Logger.error("Failed to send payment receipt: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
