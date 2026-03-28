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
  alias MobileCarWash.Billing.{Subscription, SubscriptionUsage}

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

  Returns `{:ok, appointment}` or `{:error, reason}`.
  """
  @spec create_booking(booking_params()) :: {:ok, map()} | {:error, term()}
  def create_booking(params) do
    Repo.transaction(fn ->
      with {:ok, service_type} <- fetch_service_type(params.service_type_id),
           {:ok, _vehicle} <- verify_vehicle_ownership(params.vehicle_id, params.customer_id),
           {:ok, _address} <- verify_address_ownership(params.address_id, params.customer_id),
           :ok <- check_availability(params.scheduled_at, service_type.duration_minutes),
           {:ok, price_cents, discount_cents} <- calculate_price(service_type, params[:subscription_id]),
           {:ok, appointment} <- create_appointment(params, service_type, price_cents, discount_cents),
           :ok <- maybe_update_subscription_usage(params[:subscription_id], service_type) do
        appointment
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
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

  defp calculate_price(service_type, nil), do: {:ok, service_type.base_price_cents, 0}

  defp calculate_price(service_type, subscription_id) do
    case Ash.get(Subscription, subscription_id, load: [:plan]) do
      {:ok, %{status: :active, plan: plan}} ->
        discount = calculate_subscription_discount(service_type, plan)
        price = max(service_type.base_price_cents - discount, 0)
        {:ok, price, discount}

      _ ->
        {:ok, service_type.base_price_cents, 0}
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
