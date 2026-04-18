defmodule MobileCarWash.Notifications.Push do
  @moduledoc """
  Builds APNs push-notification payloads for customer lifecycle events and
  fans them out to every active `DeviceToken` for a customer.

  Payload budget is 4 KB; keep titles ≤ ~40 chars and bodies ≤ ~120 chars
  so they render cleanly on a lock screen.

  `send_to_customer/2` is the single call site every per-event worker uses —
  it loads active tokens, dispatches through the configured `ApnsClient`,
  and deactivates tokens that APNs reports as permanently dead.
  """

  require Ash.Query
  require Logger

  alias MobileCarWash.Notifications.{ApnsClient, DeviceToken}

  @permanent_failures ~w(unregistered bad_device_token device_token_not_for_topic payload_too_large)a

  # ------------------------------------------------------------------
  # Delivery
  # ------------------------------------------------------------------

  @doc """
  Sends `payload` to every active device token for `customer_id`.

  Returns `:ok` — callers should treat push as fire-and-forget. Permanent
  failures mark the token inactive; transient failures log and move on so
  Oban's own retry can pick up the job.
  """
  @spec send_to_customer(String.t(), map()) :: :ok
  def send_to_customer(customer_id, payload) do
    case active_tokens(customer_id) do
      [] ->
        Logger.info("Push skipped: customer has no active device tokens")
        :ok

      tokens ->
        Enum.each(tokens, &deliver(&1, payload))
        :ok
    end
  end

  defp active_tokens(customer_id) do
    DeviceToken
    |> Ash.Query.for_read(:active_for_customer, %{customer_id: customer_id})
    |> Ash.read!(authorize?: false)
  end

  defp deliver(%DeviceToken{} = row, payload) do
    case apns_client().push(row.token, payload) do
      {:ok, _} ->
        :ok

      {:error, reason} when reason in @permanent_failures ->
        row
        |> Ash.Changeset.for_update(:mark_failed, %{failure_reason: to_string(reason)})
        |> Ash.update(authorize?: false)

      {:error, reason} ->
        Logger.warning(
          "Push transient failure for token ending #{String.slice(row.token, -8..-1)}: #{inspect(reason)}"
        )

        :ok
    end
  end

  defp apns_client do
    Application.get_env(:mobile_car_wash, :apns_client, ApnsClient)
  end

  # ------------------------------------------------------------------
  # Payload builders
  # ------------------------------------------------------------------

  @doc "Booking confirmed — fires after Stripe payment succeeds."
  def booking_confirmation(appointment, service_type, _address) do
    time = format_time(appointment.scheduled_at)
    date = format_date(appointment.scheduled_at)

    build(
      appointment,
      title: "Booking confirmed",
      body: "Your #{service_type.name} is booked for #{date} at #{time}.",
      kind: "booking_confirmed"
    )
  end

  @doc "Arrival-window confirmed — fires after the route optimizer assigns a slot."
  def block_scheduled(appointment, service_type, _address) do
    time = format_time(appointment.scheduled_at)
    date = format_date(appointment.scheduled_at)

    build(
      appointment,
      title: "Arrival time confirmed",
      body: "Your #{service_type.name} on #{date} is set for ~#{time}.",
      kind: "block_scheduled"
    )
  end

  @doc "24-hour appointment reminder."
  def appointment_reminder(appointment, service_type, _address) do
    time = format_time(appointment.scheduled_at)

    build(
      appointment,
      title: "Appointment tomorrow",
      body: "Your #{service_type.name} is tomorrow at #{time}.",
      kind: "appointment_reminder"
    )
  end

  @doc "Technician en route — fires on appointment :start."
  def tech_on_the_way(appointment, technician) do
    build(
      appointment,
      title: "Tech is on the way",
      body: "#{technician.name} is heading to you now.",
      kind: "tech_on_the_way",
      extras: %{technician_id: technician.id},
      deep_link: "drivewaydetail://appointments/#{appointment.id}/tracking"
    )
  end

  @doc "Wash completed — fires on appointment :complete. Zeroes the badge."
  def wash_completed(appointment, service_type) do
    build(
      appointment,
      title: "Your wash is complete!",
      body: "Thanks for choosing Driveway Detail Co. Your #{service_type.name} is done.",
      kind: "wash_completed",
      badge: 0
    )
  end

  # ------------------------------------------------------------------
  # Payload construction
  # ------------------------------------------------------------------

  defp build(appointment, opts) do
    title = Keyword.fetch!(opts, :title)
    body = Keyword.fetch!(opts, :body)
    kind = Keyword.fetch!(opts, :kind)
    extras = Keyword.get(opts, :extras, %{})
    deep_link = Keyword.get(opts, :deep_link, "drivewaydetail://appointments/#{appointment.id}")

    aps =
      %{
        alert: %{title: title, body: body},
        sound: "default",
        "thread-id": "booking-#{appointment.id}"
      }
      |> maybe_put_badge(opts)

    %{
      aps: aps,
      data:
        Map.merge(
          %{
            kind: kind,
            appointment_id: appointment.id,
            deep_link: deep_link
          },
          extras
        )
    }
  end

  defp maybe_put_badge(aps, opts) do
    case Keyword.get(opts, :badge) do
      nil -> aps
      n -> Map.put(aps, :badge, n)
    end
  end

  defp format_time(datetime), do: Calendar.strftime(datetime, "%-I:%M %p")
  defp format_date(datetime), do: Calendar.strftime(datetime, "%b %-d")
end
