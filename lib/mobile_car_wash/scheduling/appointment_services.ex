defmodule MobileCarWash.Scheduling.AppointmentServices do
  @moduledoc """
  Add-on services for appointments. `add/2` is the shared, charge-free
  attach core reused by the interactive one-off flow, the Stripe webhook,
  and the recurring scheduler. Charging lives in `request_add_services/2`
  and `complete_addon_checkout/1`.
  """

  alias MobileCarWash.Billing.{Payment, Pricing, StripeClient}
  alias MobileCarWash.Scheduling.{AddOn, Appointment, AppointmentAddOn, RecurringScheduleAddOn}
  alias MobileCarWash.Fleet.Vehicle

  require Ash.Query

  @doc """
  Attaches the given add-ons to `appointment`, capturing size-scaled prices
  and bumping the appointment's `price_cents` by the delta. No payment.
  Returns `{:ok, appointment}` (unchanged if no active add-ons resolve).
  """
  def add(appointment, add_on_ids) do
    case load_active_add_ons(add_on_ids) do
      [] ->
        {:ok, appointment}

      add_ons ->
        vehicle = Ash.get!(Vehicle, appointment.vehicle_id, authorize?: false)

        Enum.each(add_ons, fn add_on ->
          AppointmentAddOn
          |> Ash.Changeset.for_create(:create, %{
            appointment_id: appointment.id,
            add_on_id: add_on.id,
            price_cents: Pricing.calculate(add_on.price_cents, vehicle.size)
          })
          |> Ash.create!()
        end)

        delta = Pricing.addons_total_cents(add_ons, vehicle.size)

        appointment
        |> Ash.Changeset.for_update(:update, %{price_cents: appointment.price_cents + delta})
        |> Ash.update()
    end
  end

  @doc false
  def load_active_add_ons(nil), do: []
  def load_active_add_ons([]), do: []

  def load_active_add_ons(ids) do
    AddOn
    |> Ash.Query.filter(id in ^ids and active == true)
    |> Ash.read!()
  end

  @doc """
  Replaces a recurring schedule's add-on set: deletes existing join rows,
  then creates one per active add-on id. Affects FUTURE occurrences only.
  """
  def replace_schedule_add_ons(schedule_id, add_on_ids) do
    RecurringScheduleAddOn
    |> Ash.Query.for_read(:for_schedule, %{recurring_schedule_id: schedule_id})
    |> Ash.read!()
    |> Enum.each(&Ash.destroy!/1)

    add_on_ids
    |> load_active_add_ons()
    |> Enum.each(fn add_on ->
      RecurringScheduleAddOn
      |> Ash.Changeset.for_create(:create, %{
        recurring_schedule_id: schedule_id,
        add_on_id: add_on.id
      })
      |> Ash.create!()
    end)

    :ok
  end

  @doc "Current add-on ids attached to a recurring schedule."
  def schedule_add_on_ids(schedule_id) do
    RecurringScheduleAddOn
    |> Ash.Query.for_read(:for_schedule, %{recurring_schedule_id: schedule_id})
    |> Ash.read!()
    |> Enum.map(& &1.add_on_id)
  end

  @doc "Loaded active AddOn records attached to a recurring schedule."
  def schedule_add_ons(schedule_id) do
    schedule_id
    |> schedule_add_on_ids()
    |> load_active_add_ons()
  end

  @cutoff_seconds 12 * 3600

  @doc """
  Interactive one-off add-services flow. Caller must own the appointment.
  Charges off-session; on success attaches + records payment, on failure
  returns a hosted-checkout URL and attaches nothing.
  """
  def request_add_services(appointment, add_on_ids) do
    with true <- editable?(appointment) || {:error, :not_editable},
         add_ons when add_ons != [] <- load_active_add_ons(add_on_ids) do
      vehicle = Ash.get!(Vehicle, appointment.vehicle_id, authorize?: false)

      customer =
        Ash.get!(MobileCarWash.Accounts.Customer, appointment.customer_id, authorize?: false)

      amount_cents = Pricing.addons_total_cents(add_ons, vehicle.size)

      metadata = %{kind: "appointment_addons", appointment_id: appointment.id}

      case StripeClient.charge_off_session(customer.stripe_customer_id, amount_cents, metadata) do
        {:ok, intent} ->
          {:ok, _appt} = add(appointment, add_on_ids)
          record_succeeded_payment(appointment, customer, amount_cents, intent.id)
          {:ok, :charged}

        {:error, _reason} ->
          addon_checkout_fallback(appointment, customer, add_ons, add_on_ids, amount_cents)
      end
    else
      {:error, :not_editable} -> {:error, :not_editable}
      [] -> {:error, :no_add_ons}
      nil -> {:error, :no_add_ons}
    end
  end

  @doc "True when the appointment may still be modified (status + 12h cutoff)."
  def editable?(appointment) do
    appointment.status in [:pending, :confirmed] and
      DateTime.diff(appointment.scheduled_at, DateTime.utc_now()) > @cutoff_seconds
  end

  @doc """
  Webhook completion for a hosted add-on checkout: attach the add-ons and mark
  the pending payment succeeded.
  """
  def complete_addon_checkout(session) do
    metadata = Map.get(session, :metadata) || %{}
    appointment_id = metadata["appointment_id"] || metadata[:appointment_id]
    add_on_ids = parse_ids(metadata["add_on_ids"] || metadata[:add_on_ids])

    with {:ok, appointment} <- Ash.get(Appointment, appointment_id, authorize?: false),
         {:ok, _appt} <- add(appointment, add_on_ids) do
      mark_payment_succeeded(Map.get(session, :id), Map.get(session, :payment_intent))
      :ok
    end
  end

  defp parse_ids(nil), do: []
  defp parse_ids(""), do: []
  defp parse_ids(csv) when is_binary(csv), do: String.split(csv, ",", trim: true)
  defp parse_ids(list) when is_list(list), do: list

  defp mark_payment_succeeded(nil, _pi), do: :ok

  defp mark_payment_succeeded(session_id, payment_intent_id) do
    Payment
    |> Ash.Query.for_read(:by_checkout_session, %{session_id: session_id})
    |> Ash.read!()
    |> List.first()
    |> case do
      nil ->
        :ok

      payment ->
        {:ok, payment} =
          payment
          |> Ash.Changeset.for_update(:complete, %{stripe_payment_intent_id: payment_intent_id})
          |> Ash.update()

        enqueue_payment_receipt(payment)
        :ok
    end
  end

  defp record_succeeded_payment(appointment, customer, amount_cents, payment_intent_id) do
    {:ok, payment} =
      Payment
      |> Ash.Changeset.for_create(:create, %{amount_cents: amount_cents, status: :pending})
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.Changeset.force_change_attribute(:appointment_id, appointment.id)
      |> Ash.create()

    {:ok, payment} =
      payment
      |> Ash.Changeset.for_update(:complete, %{stripe_payment_intent_id: payment_intent_id})
      |> Ash.update()

    enqueue_payment_receipt(payment)
    payment
  end

  defp addon_checkout_fallback(appointment, customer, add_ons, add_on_ids, amount_cents) do
    {:ok, payment} =
      Payment
      |> Ash.Changeset.for_create(:create, %{amount_cents: amount_cents, status: :pending})
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.Changeset.force_change_attribute(:appointment_id, appointment.id)
      |> Ash.create()

    case StripeClient.create_addon_checkout(
           appointment,
           add_ons,
           add_on_ids,
           amount_cents,
           to_string(customer.email)
         ) do
      {:ok, session} ->
        {:ok, _} =
          payment
          |> Ash.Changeset.for_update(:update, %{stripe_checkout_session_id: session.id})
          |> Ash.update()

        {:ok, session.url}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp enqueue_payment_receipt(payment) do
    %{payment_id: payment.id}
    |> MobileCarWash.Notifications.PaymentReceiptWorker.new(queue: :notifications)
    |> Oban.insert()
  end
end
