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
  alias MobileCarWash.Scheduling.{Appointment, ServiceType, Availability}
  alias MobileCarWash.Fleet.{Vehicle, Address}
  alias MobileCarWash.Billing.{Payment, Subscription, SubscriptionUsage, StripeClient}

  require Ash.Query

  @type booking_params :: %{
          customer_id: String.t(),
          service_type_id: String.t(),
          vehicle_id: String.t(),
          address_id: String.t(),
          scheduled_at: DateTime.t(),
          notes: String.t() | nil,
          subscription_id: String.t() | nil
        }

  @doc """
  Creates a complete booking with all associated resources.

  Returns `{:ok, %{appointment: appointment, checkout_url: url}}` or `{:error, reason}`.
  The checkout_url is the Stripe Checkout URL the customer should be redirected to.
  If payment amount is 0 (fully covered by subscription), no Stripe session is created.
  """
  @spec create_booking(booking_params()) :: {:ok, map()} | {:error, term()}
  def create_booking(params) do
    Repo.transaction(fn ->
      with {:ok, service_type} <- fetch_service_type(params.service_type_id),
           {:ok, vehicle} <- verify_vehicle_ownership(params.vehicle_id, params.customer_id),
           {:ok, _address} <- verify_address_ownership(params.address_id, params.customer_id),
           :ok <- check_availability(params.scheduled_at, service_type.duration_minutes),
           {:ok, price_cents, discount_cents} <- calculate_price(service_type, vehicle.size, params[:subscription_id]),
           {:ok, appointment} <- create_appointment(params, service_type, price_cents, discount_cents),
           :ok <- maybe_update_subscription_usage(params[:subscription_id], service_type),
           {:ok, result} <- create_payment_and_checkout(appointment, service_type, params) do
        result
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
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
                |> Ash.Changeset.for_update(:confirm, %{})
                |> Ash.update()

              # Enqueue confirmation email
              enqueue_confirmation_email(appointment)
              # Schedule reminder
              enqueue_appointment_reminder(appointment)

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

  defp calculate_price(service_type, vehicle_size, nil) do
    price = MobileCarWash.Billing.Pricing.calculate(service_type.base_price_cents, vehicle_size)
    {:ok, price, 0}
  end

  defp calculate_price(service_type, vehicle_size, subscription_id) do
    sized_price = MobileCarWash.Billing.Pricing.calculate(service_type.base_price_cents, vehicle_size)

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

  defp create_appointment(params, service_type, price_cents, discount_cents) do
    Appointment
    |> Ash.Changeset.for_create(:book, %{
      customer_id: params.customer_id,
      vehicle_id: params.vehicle_id,
      address_id: params.address_id,
      service_type_id: params.service_type_id,
      scheduled_at: params.scheduled_at,
      notes: params[:notes],
      price_cents: price_cents,
      duration_minutes: service_type.duration_minutes,
      discount_cents: discount_cents
    })
    |> Ash.create()
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
    if appointment.price_cents == 0 do
      # Fully covered by subscription — no payment needed, auto-confirm
      {:ok, appointment} =
        appointment
        |> Ash.Changeset.for_update(:confirm, %{})
        |> Ash.update()

      enqueue_confirmation_email(appointment)
      enqueue_appointment_reminder(appointment)

      {:ok, %{appointment: appointment, checkout_url: nil}}
    else
      # Create payment record
      {:ok, payment} =
        Payment
        |> Ash.Changeset.for_create(:create, %{
          customer_id: params.customer_id,
          appointment_id: appointment.id,
          amount_cents: appointment.price_cents,
          status: :pending
        })
        |> Ash.create()

      # Create Stripe Checkout session
      customer = Ash.get!(MobileCarWash.Accounts.Customer, params.customer_id)

      case StripeClient.create_checkout_session(appointment, service_type, to_string(customer.email)) do
        {:ok, session} ->
          # Store the checkout session ID on the payment
          {:ok, _payment} =
            payment
            |> Ash.Changeset.for_update(:update, %{stripe_checkout_session_id: session.id})
            |> Ash.update()

          {:ok, %{appointment: appointment, checkout_url: session.url}}

        {:error, _stripe_error} ->
          # Stripe failed — still return the appointment but no checkout URL
          # The customer can retry payment later
          {:ok, %{appointment: appointment, checkout_url: nil}}
      end
    end
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
