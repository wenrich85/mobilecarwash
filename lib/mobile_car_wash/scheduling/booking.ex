defmodule MobileCarWash.Scheduling.Booking do
  @moduledoc """
  Booking orchestrator — coordinates the multi-resource creation of a booking.

  This is the single entry point for creating a complete booking:
  1. Creates or looks up vehicle (verifies customer ownership)
  2. Creates or looks up address (verifies customer ownership)
  3. Calculates price (base from service type, minus subscription discount)
  4. Verifies time slot availability
  5. Creates appointment
  6. Updates subscription usage if applicable

  All operations are wrapped in a database transaction.
  """

  alias MobileCarWash.Repo

  alias MobileCarWash.Scheduling.{
    Appointment,
    AppointmentBlock,
    AppointmentTracker,
    Availability,
    ServiceType
  }

  alias MobileCarWash.Fleet.{Vehicle, Address}
  alias MobileCarWash.Billing.{Payment, Subscription, SubscriptionUsage, StripeClient}
  alias MobileCarWash.CashFlow.Engine, as: CashFlowEngine

  require Ash.Query

  @type booking_params :: %{
          optional(:scheduled_at) => DateTime.t(),
          optional(:appointment_block_id) => String.t(),
          optional(:notes) => String.t() | nil,
          optional(:subscription_id) => String.t() | nil,
          customer_id: String.t(),
          service_type_id: String.t(),
          vehicle_id: String.t(),
          address_id: String.t()
        }

  @doc """
  Creates a complete booking with all associated resources.

  Returns `{:ok, %{appointment: appointment, checkout_url: url}}` or `{:error, reason}`.
  The checkout_url is the Stripe Checkout URL the customer should be redirected to.
  If payment amount is 0 (fully covered by subscription), no Stripe session is created.
  """
  @spec create_booking(booking_params()) :: {:ok, map()} | {:error, term()}
  def create_booking(params) do
    result =
      Repo.transaction(fn ->
        with {:ok, service_type} <- fetch_service_type(params.service_type_id),
             {:ok, vehicle} <- verify_vehicle_ownership(params.vehicle_id, params.customer_id),
             {:ok, _address} <- verify_address_ownership(params.address_id, params.customer_id),
             {:ok, params} <- resolve_schedule(params, service_type),
             {:ok, price_cents, discount_cents} <-
               calculate_price(service_type, vehicle.size, params[:subscription_id]),
             {price_cents, discount_cents} =
               apply_loyalty_discount(price_cents, discount_cents, params[:loyalty_redeem]),
             :ok <- maybe_redeem_loyalty(params[:loyalty_redeem], params.customer_id),
             {price_cents, discount_cents} =
               maybe_apply_referral(price_cents, discount_cents, params[:referral_code]),
             {:ok, appointment} <-
               create_appointment(params, service_type, price_cents, discount_cents),
             :ok <- maybe_update_subscription_usage(params[:subscription_id], service_type),
             {:ok, result} <- create_payment_and_checkout(appointment, service_type, params) do
          result
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)

    # Broadcast to dispatch after successful transaction
    case result do
      {:ok, %{appointment: appointment}} ->
        AppointmentTracker.broadcast_new_appointment(appointment.id)
        maybe_close_full_block(appointment.appointment_block_id)

      _ ->
        :ok
    end

    result
  end

  # If the block this appointment belongs to just hit capacity, close +
  # optimize it immediately so customers get their confirmed times.
  defp maybe_close_full_block(nil), do: :ok

  defp maybe_close_full_block(block_id) do
    case Ash.get(AppointmentBlock, block_id, load: [:appointment_count]) do
      {:ok, %{status: :open, capacity: cap, appointment_count: count} = block}
      when count >= cap ->
        MobileCarWash.Scheduling.BlockOptimizer.close_and_optimize(block.id)

      _ ->
        :ok
    end
  end

  @doc """
  Completes a booking after successful Stripe payment.
  Called from the webhook handler.
  """
  def complete_payment(checkout_session_id, stripe_payment_intent_id \\ nil) do
    payments =
      Ash.read!(Payment,
        action: :by_checkout_session,
        arguments: %{session_id: checkout_session_id}
      )

    case payments do
      [payment] ->
        # Update payment status
        {:ok, payment} =
          payment
          |> Ash.Changeset.for_update(:complete, %{
            stripe_payment_intent_id: stripe_payment_intent_id
          })
          |> Ash.update()

        # Confirm the appointment
        if payment.appointment_id do
          case Ash.get(Appointment, payment.appointment_id) do
            {:ok, appointment} ->
              {:ok, appointment} =
                appointment
                |> Ash.Changeset.for_update(:payment_confirm, %{})
                |> Ash.update()

              # Enqueue confirmation email + SMS + push
              enqueue_confirmation_email(appointment)
              enqueue_sms_confirmation(appointment)
              enqueue_push_confirmation(appointment)
              # Schedule reminder email + SMS + push (all 24h before)
              enqueue_appointment_reminder(appointment)
              enqueue_sms_reminder(appointment)
              enqueue_push_reminder(appointment)
              # Enqueue payment receipt
              enqueue_payment_receipt(payment)
              # Sync to external accounting system (ZohoBooks/QB)
              enqueue_accounting_sync(payment)
              # Record income in local cash flow ledger
              record_payment_in_cash_flow(payment, appointment)
              # Credit referrer if a referral code was used
              enqueue_referral_credit(appointment)

              {:ok, %{payment: payment, appointment: appointment}}

            _ ->
              {:ok, %{payment: payment}}
          end
        else
          {:ok, %{payment: payment}}
        end

      [] ->
        {:error, :payment_not_found}
    end
  end

  @doc """
  Marks a payment as failed (e.g., expired checkout session).
  """
  def fail_payment(checkout_session_id) do
    payments =
      Ash.read!(Payment,
        action: :by_checkout_session,
        arguments: %{session_id: checkout_session_id}
      )

    case payments do
      [payment] ->
        payment
        |> Ash.Changeset.for_update(:fail, %{})
        |> Ash.update()

      [] ->
        {:error, :payment_not_found}
    end
  end

  # --- Private ---

  defp apply_loyalty_discount(price_cents, discount_cents, true) when price_cents > 0 do
    # Loyalty free wash — full discount, net becomes 0
    {0, price_cents + discount_cents}
  end

  defp apply_loyalty_discount(price_cents, discount_cents, _), do: {price_cents, discount_cents}

  defp maybe_redeem_loyalty(true, customer_id) do
    case MobileCarWash.Loyalty.redeem(customer_id) do
      {:ok, _} -> :ok
      {:error, :no_free_washes} -> {:error, :no_loyalty_free_washes}
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_redeem_loyalty(_, _), do: :ok

  defp fetch_service_type(service_type_id) do
    case Ash.get(ServiceType, service_type_id) do
      {:ok, service_type} -> {:ok, service_type}
      {:error, _} -> {:error, :service_type_not_found}
    end
  end

  defp verify_vehicle_ownership(vehicle_id, customer_id) do
    case Ash.get(Vehicle, vehicle_id) do
      {:ok, vehicle} ->
        if vehicle.customer_id == customer_id do
          {:ok, vehicle}
        else
          {:error, :vehicle_not_owned}
        end

      {:error, _} ->
        {:error, :vehicle_not_found}
    end
  end

  defp verify_address_ownership(address_id, customer_id) do
    case Ash.get(Address, address_id) do
      {:ok, address} ->
        if address.customer_id == customer_id do
          {:ok, address}
        else
          {:error, :address_not_owned}
        end

      {:error, _} ->
        {:error, :address_not_found}
    end
  end

  defp check_availability(scheduled_at, duration_minutes) do
    date = DateTime.to_date(scheduled_at)

    # Query existing appointments for this date
    {:ok, day_start} = DateTime.new(date, ~T[00:00:00])
    {:ok, day_end} = DateTime.new(Date.add(date, 1), ~T[00:00:00])

    existing =
      Appointment
      |> Ash.Query.filter(
        scheduled_at >= ^day_start and
          scheduled_at < ^day_end and
          status in [:pending, :confirmed, :in_progress]
      )
      |> Ash.read!()
      |> Enum.map(fn appt ->
        %{scheduled_at: appt.scheduled_at, duration_minutes: appt.duration_minutes}
      end)

    if Availability.slot_available?(scheduled_at, duration_minutes, existing) do
      :ok
    else
      {:error, :slot_unavailable}
    end
  end

  # Routes to either the block flow (new) or the legacy time-slot flow. In
  # block mode, the block has already been validated as open with capacity —
  # we fill in `scheduled_at` from the block as a tentative placeholder that
  # the route optimizer will overwrite.
  defp resolve_schedule(params, service_type) do
    case params[:appointment_block_id] do
      nil ->
        with :ok <- check_availability(params.scheduled_at, service_type.duration_minutes) do
          {:ok, params}
        end

      block_id ->
        with {:ok, block} <- fetch_block(block_id),
             :ok <- validate_block_for_booking(block, service_type),
             :ok <- validate_block_proximity(block, params.address_id) do
          {:ok, Map.put(params, :scheduled_at, block.starts_at)}
        end
    end
  end

  defp fetch_block(block_id) do
    case Ash.get(AppointmentBlock, block_id, load: [:appointment_count]) do
      {:ok, block} -> {:ok, block}
      {:error, _} -> {:error, :block_not_found}
    end
  end

  defp validate_block_for_booking(block, service_type) do
    cond do
      block.service_type_id != service_type.id ->
        {:error, :block_service_mismatch}

      block.status != :open ->
        {:error, :block_not_open}

      DateTime.compare(block.closes_at, DateTime.utc_now()) != :gt ->
        {:error, :block_closed}

      block.appointment_count >= block.capacity ->
        {:error, :block_full}

      true ->
        :ok
    end
  end

  # Enforces that a block's appointments stay geographically clustered: a
  # new booking must be within the admin-configured drive-time threshold
  # of at least one existing appointment. Empty blocks always accept —
  # the first booking seeds the cluster.
  defp validate_block_proximity(block, address_id) do
    existing_coords = existing_block_coords(block.id)

    cond do
      existing_coords == [] ->
        :ok

      true ->
        with {:ok, {lat, lng}} <- candidate_coords(address_id),
             max_minutes <-
               MobileCarWash.Scheduling.SchedulingSettings.get().max_intra_block_drive_minutes,
             true <- any_within?(existing_coords, {lat, lng}, max_minutes) do
          :ok
        else
          false -> {:error, :block_too_far}
          {:error, _} = err -> err
        end
    end
  end

  defp existing_block_coords(block_id) do
    import Ash.Expr

    Appointment
    |> Ash.Query.filter(expr(appointment_block_id == ^block_id and status != :cancelled))
    |> Ash.Query.load(:address)
    |> Ash.read!(authorize?: false)
    |> Enum.map(& &1.address)
    |> Enum.filter(&(&1.latitude && &1.longitude))
    |> Enum.map(&{&1.latitude, &1.longitude})
  end

  defp candidate_coords(address_id) do
    case Ash.get(Address, address_id, authorize?: false) do
      {:ok, %{latitude: lat, longitude: lng}} when is_number(lat) and is_number(lng) ->
        {:ok, {lat, lng}}

      {:ok, _} ->
        {:error, :address_missing_coordinates}

      {:error, _} ->
        {:error, :address_not_found}
    end
  end

  defp any_within?(existing_coords, candidate, max_minutes) do
    Enum.any?(existing_coords, fn coords ->
      MobileCarWash.Routing.Haversine.travel_minutes(coords, candidate) <= max_minutes
    end)
  end

  defp calculate_price(service_type, vehicle_size, nil) do
    price = MobileCarWash.Billing.Pricing.calculate(service_type.base_price_cents, vehicle_size)
    {:ok, price, 0}
  end

  defp calculate_price(service_type, vehicle_size, subscription_id) do
    sized_price =
      MobileCarWash.Billing.Pricing.calculate(service_type.base_price_cents, vehicle_size)

    case Ash.get(Subscription, subscription_id, load: [:plan]) do
      {:ok, %{status: :active, plan: plan}} ->
        discount = calculate_subscription_discount(service_type, plan)
        price = max(sized_price - discount, 0)
        {:ok, price, discount}

      _ ->
        {:ok, sized_price, 0}
    end
  end

  defp calculate_subscription_discount(service_type, plan) do
    cond do
      # Basic wash covered by subscription
      service_type.slug == "basic_wash" and plan.basic_washes_per_month > 0 ->
        # Covered washes are free (check usage happens in maybe_update_subscription_usage)
        service_type.base_price_cents

      # Deep clean discount
      service_type.slug == "deep_clean" and plan.deep_clean_discount_percent > 0 ->
        div(service_type.base_price_cents * plan.deep_clean_discount_percent, 100)

      true ->
        0
    end
  end

  defp maybe_apply_referral(price_cents, discount_cents, nil), do: {price_cents, discount_cents}
  defp maybe_apply_referral(price_cents, discount_cents, ""), do: {price_cents, discount_cents}

  defp maybe_apply_referral(price_cents, discount_cents, _code),
    do: apply_referral_discount(price_cents, discount_cents)

  defp create_appointment(params, service_type, price_cents, discount_cents) do
    changeset =
      Appointment
      |> Ash.Changeset.for_create(:book, %{
        customer_id: params.customer_id,
        vehicle_id: params.vehicle_id,
        address_id: params.address_id,
        service_type_id: params.service_type_id,
        scheduled_at: params.scheduled_at,
        appointment_block_id: params[:appointment_block_id],
        notes: params[:notes],
        price_cents: price_cents,
        duration_minutes: service_type.duration_minutes,
        discount_cents: discount_cents
      })

    changeset =
      if params[:referral_code] do
        Ash.Changeset.force_change_attribute(
          changeset,
          :referral_code_used,
          params[:referral_code]
        )
      else
        changeset
      end

    Ash.create(changeset)
  end

  defp maybe_update_subscription_usage(nil, _service_type), do: :ok

  defp maybe_update_subscription_usage(subscription_id, service_type) do
    # Find or create usage record for current billing period
    case Ash.get(Subscription, subscription_id) do
      {:ok, subscription} ->
        usage = get_or_create_usage(subscription)
        update_usage_counts(usage, service_type)

      _ ->
        :ok
    end
  end

  defp get_or_create_usage(subscription) do
    today = Date.utc_today()

    existing =
      SubscriptionUsage
      |> Ash.Query.filter(
        subscription_id == ^subscription.id and
          period_start <= ^today and
          period_end >= ^today
      )
      |> Ash.read!()

    case existing do
      [usage | _] ->
        usage

      [] ->
        period_start = subscription.current_period_start || today
        period_end = subscription.current_period_end || Date.add(today, 30)

        SubscriptionUsage
        |> Ash.Changeset.for_create(:create, %{
          subscription_id: subscription.id,
          period_start: period_start,
          period_end: period_end
        })
        |> Ash.create!()
    end
  end

  defp create_payment_and_checkout(appointment, service_type, params) do
    cond do
      appointment.price_cents == 0 ->
        # Fully covered by subscription — no payment needed, auto-confirm
        {:ok, appointment} =
          appointment
          |> Ash.Changeset.for_update(:payment_confirm, %{})
          |> Ash.update()

        enqueue_confirmation_email(appointment)
        enqueue_sms_confirmation(appointment)
        enqueue_push_confirmation(appointment)
        enqueue_appointment_reminder(appointment)
        enqueue_sms_reminder(appointment)
        enqueue_push_reminder(appointment)

        {:ok, %{appointment: appointment, checkout_url: nil}}

      params[:payment_flow] == :mobile ->
        create_mobile_payment_intent(appointment, params)

      true ->
        create_web_checkout(appointment, service_type, params)
    end
  end

  defp create_mobile_payment_intent(appointment, params) do
    {:ok, payment} =
      Payment
      |> Ash.Changeset.for_create(:create, %{
        amount_cents: appointment.price_cents,
        status: :pending
      })
      |> Ash.Changeset.force_change_attribute(:customer_id, params.customer_id)
      |> Ash.Changeset.force_change_attribute(:appointment_id, appointment.id)
      |> Ash.create()

    customer = Ash.get!(MobileCarWash.Accounts.Customer, params.customer_id, authorize?: false)

    metadata = %{appointment_id: appointment.id, payment_id: payment.id}

    case StripeClient.create_payment_intent(
           appointment.price_cents,
           to_string(customer.email),
           metadata
         ) do
      {:ok, %{id: intent_id, client_secret: secret}} ->
        {:ok, _} =
          payment
          |> Ash.Changeset.for_update(:update, %{stripe_payment_intent_id: intent_id})
          |> Ash.update()

        {:ok, %{appointment: appointment, payment_intent_client_secret: secret}}

      {:error, _} ->
        {:ok, %{appointment: appointment, payment_intent_client_secret: nil}}
    end
  end

  defp create_web_checkout(appointment, service_type, params) do
    {:ok, payment} =
      Payment
      |> Ash.Changeset.for_create(:create, %{
        amount_cents: appointment.price_cents,
        status: :pending
      })
      |> Ash.Changeset.force_change_attribute(:customer_id, params.customer_id)
      |> Ash.Changeset.force_change_attribute(:appointment_id, appointment.id)
      |> Ash.create()

    customer = Ash.get!(MobileCarWash.Accounts.Customer, params.customer_id, authorize?: false)

    case StripeClient.create_checkout_session(
           appointment,
           service_type,
           to_string(customer.email)
         ) do
      {:ok, session} ->
        # Store the checkout session ID on the payment
        {:ok, _payment} =
          payment
          |> Ash.Changeset.for_update(:update, %{stripe_checkout_session_id: session.id})
          |> Ash.update()

        {:ok, %{appointment: appointment, checkout_url: session.url}}

      {:error, _stripe_error} ->
        # Stripe failed — still return the appointment but no checkout URL.
        # The customer can retry payment later.
        {:ok, %{appointment: appointment, checkout_url: nil}}
    end
  end

  defp record_payment_in_cash_flow(payment, appointment) do
    service_name =
      case Ash.get(ServiceType, appointment.service_type_id) do
        {:ok, st} -> st.name
        _ -> "Car wash"
      end

    CashFlowEngine.record_deposit(payment.amount_cents, "Wash payment — #{service_name}")
  end

  defp enqueue_confirmation_email(appointment) do
    %{appointment_id: appointment.id}
    |> MobileCarWash.Notifications.BookingConfirmationWorker.new(queue: :notifications)
    |> Oban.insert()
  end

  defp enqueue_appointment_reminder(appointment) do
    scheduled_at = DateTime.add(appointment.scheduled_at, -24 * 3600)

    %{appointment_id: appointment.id}
    |> MobileCarWash.Notifications.AppointmentReminderWorker.new(
      queue: :notifications,
      scheduled_at: scheduled_at
    )
    |> Oban.insert()
  end

  defp enqueue_sms_confirmation(appointment) do
    %{appointment_id: appointment.id}
    |> MobileCarWash.Notifications.SMSBookingConfirmationWorker.new(queue: :notifications)
    |> Oban.insert()
  end

  defp enqueue_push_confirmation(appointment) do
    %{appointment_id: appointment.id}
    |> MobileCarWash.Notifications.PushBookingConfirmationWorker.new(queue: :notifications)
    |> Oban.insert()
  end

  defp enqueue_push_reminder(appointment) do
    scheduled_at = DateTime.add(appointment.scheduled_at, -24 * 3600)

    %{appointment_id: appointment.id}
    |> MobileCarWash.Notifications.PushAppointmentReminderWorker.new(
      queue: :notifications,
      scheduled_at: scheduled_at
    )
    |> Oban.insert()
  end

  defp enqueue_sms_reminder(appointment) do
    scheduled_at = DateTime.add(appointment.scheduled_at, -24 * 3600)

    %{appointment_id: appointment.id}
    |> MobileCarWash.Notifications.SMSAppointmentReminderWorker.new(
      queue: :notifications,
      scheduled_at: scheduled_at
    )
    |> Oban.insert()
  end

  defp enqueue_payment_receipt(payment) do
    %{payment_id: payment.id}
    |> MobileCarWash.Notifications.PaymentReceiptWorker.new(queue: :notifications)
    |> Oban.insert()
  end

  @referral_discount_cents 1000

  @doc "Validates a referral code. Returns {:ok, referrer} or {:error, reason}."
  def validate_referral_code(code, customer_id) do
    case MobileCarWash.Accounts.Customer
         |> Ash.Query.for_read(:by_referral_code, %{referral_code: code})
         |> Ash.read!(authorize?: false) do
      [referrer] ->
        if referrer.id == customer_id do
          {:error, :self_referral}
        else
          {:ok, referrer}
        end

      [] ->
        {:error, :not_found}
    end
  end

  @doc "Applies $10 referral discount. Returns {new_price, new_discount}."
  def apply_referral_discount(price_cents, existing_discount_cents) do
    discount = min(@referral_discount_cents, price_cents)
    {price_cents - discount, existing_discount_cents + discount}
  end

  defp enqueue_referral_credit(appointment) do
    if appointment.referral_code_used do
      %{referral_code: appointment.referral_code_used, referee_name: "a new customer"}
      |> MobileCarWash.Notifications.ReferralCreditWorker.new(queue: :notifications)
      |> Oban.insert()
    end
  end

  defp enqueue_accounting_sync(payment) do
    %{payment_id: payment.id}
    |> MobileCarWash.Accounting.SyncWorker.new(queue: :billing)
    |> Oban.insert()
  end

  defp update_usage_counts(usage, service_type) do
    updates =
      case service_type.slug do
        "basic_wash" -> %{basic_washes_used: (usage.basic_washes_used || 0) + 1}
        "deep_clean" -> %{deep_cleans_used: (usage.deep_cleans_used || 0) + 1}
        _ -> %{}
      end

    if map_size(updates) > 0 do
      usage
      |> Ash.Changeset.for_update(:update, updates)
      |> Ash.update()
      |> case do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      :ok
    end
  end
end
