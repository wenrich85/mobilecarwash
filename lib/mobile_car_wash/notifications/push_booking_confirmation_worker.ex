defmodule MobileCarWash.Notifications.PushBookingConfirmationWorker do
  @moduledoc """
  Oban worker that sends an APNs push notification for a confirmed booking.
  Mirrors `SMSBookingConfirmationWorker` — same Oban queue, same trigger
  sites in `Scheduling.Booking.complete_payment/2`.

  Gracefully no-ops when the customer has no active device tokens.
  Permanent APNs failures (`:unregistered`, `:bad_device_token`,
  `:device_token_not_for_topic`) deactivate the offending token so future
  jobs skip it; transient failures leave the token active for Oban's
  built-in retry to pick up.
  """
  use Oban.Worker, queue: :notifications, max_attempts: 3

  require Ash.Query
  require Logger

  alias MobileCarWash.Scheduling.{Appointment, ServiceType}
  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Fleet.Address
  alias MobileCarWash.Notifications.{DeviceToken, Push}

  @permanent_failures ~w(unregistered bad_device_token device_token_not_for_topic payload_too_large)a

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"appointment_id" => appointment_id}}) do
    with {:ok, appointment} <- Ash.get(Appointment, appointment_id, authorize?: false),
         {:ok, customer} <- Ash.get(Customer, appointment.customer_id, authorize?: false),
         {:ok, service_type} <-
           Ash.get(ServiceType, appointment.service_type_id, authorize?: false),
         {:ok, address} <- Ash.get(Address, appointment.address_id, authorize?: false),
         tokens when tokens != [] <- active_tokens(customer.id) do
      payload = Push.booking_confirmation(appointment, service_type, address)
      Enum.each(tokens, &send_one(&1, payload))
      :ok
    else
      [] ->
        Logger.info("Push skipped: customer has no active device tokens")
        :ok

      {:error, reason} ->
        Logger.error("Push booking confirmation data load failed: #{inspect(reason)}")
        :ok
    end
  end

  defp active_tokens(customer_id) do
    DeviceToken
    |> Ash.Query.for_read(:active_for_customer, %{customer_id: customer_id})
    |> Ash.read!(authorize?: false)
  end

  defp send_one(%DeviceToken{} = row, payload) do
    case apns_client().push(row.token, payload) do
      {:ok, _} ->
        :ok

      {:error, reason} when reason in @permanent_failures ->
        mark_failed(row, reason)

      {:error, reason} ->
        Logger.warning(
          "Push transient failure for token ending #{String.slice(row.token, -8..-1)}: #{inspect(reason)}"
        )

        :ok
    end
  end

  defp mark_failed(row, reason) do
    row
    |> Ash.Changeset.for_update(:mark_failed, %{failure_reason: to_string(reason)})
    |> Ash.update(authorize?: false)
  end

  defp apns_client do
    Application.get_env(
      :mobile_car_wash,
      :apns_client,
      MobileCarWash.Notifications.ApnsClient
    )
  end
end
