defmodule MobileCarWash.Notifications.AddOnChargeFailedWorker do
  @moduledoc "Notifies a customer that their saved card was declined for recurring add-ons."
  use Oban.Worker, queue: :notifications, max_attempts: 3

  alias MobileCarWash.Notifications.Email
  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Scheduling.{Appointment, ServiceType}

  require Logger

  @impl true
  def perform(%Oban.Job{args: %{"appointment_id" => appointment_id}}) do
    with {:ok, appointment} <- Ash.get(Appointment, appointment_id, authorize?: false),
         {:ok, customer} <- Ash.get(Customer, appointment.customer_id, authorize?: false) do
      service_name =
        case Ash.get(ServiceType, appointment.service_type_id, authorize?: false) do
          {:ok, st} -> st.name
          _ -> "Detailing Service"
        end

      Email.addon_charge_failed(customer, service_name)
      |> MobileCarWash.Mailer.deliver()

      :ok
    else
      {:error, reason} ->
        Logger.error("Failed to send add-on decline notice: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
