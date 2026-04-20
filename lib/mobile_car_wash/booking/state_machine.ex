defmodule MobileCarWash.Booking.StateMachine do
  @moduledoc """
  Pure functional state machine for the booking flow.
  No dependencies on Phoenix, LiveView, or Ash.
  Operates on a context map and returns results.
  """

  @steps [:select_service, :auth, :vehicle, :address, :photos, :schedule, :review, :confirmed]

  @type step ::
          :select_service
          | :auth
          | :vehicle
          | :address
          | :photos
          | :schedule
          | :review
          | :confirmed

  @type context :: %{
          selected_service: term(),
          current_customer: term(),
          guest_mode: boolean(),
          selected_vehicle: term(),
          selected_address: term(),
          selected_slot: term(),
          appointment: term()
        }

  def steps, do: @steps

  @doc "Forward or backward transition with guard validation."
  @spec transition(:forward | :back, step(), context()) :: {:ok, step()} | {:error, atom()}
  def transition(:forward, step, context) do
    with :ok <- validate_forward_guard(step, context),
         {:ok, raw_next} <- raw_next(step) do
      maybe_skip(raw_next, :forward, context)
    end
  end

  def transition(:back, step, context) do
    case raw_prev(step) do
      {:ok, raw_prev_step} -> maybe_skip(raw_prev_step, :back, context)
      error -> error
    end
  end

  @doc "Check if a user can validly be on a given step."
  @spec can_be_on?(step(), context()) :: boolean()
  def can_be_on?(:select_service, _ctx), do: true
  def can_be_on?(:auth, ctx), do: present?(ctx, :selected_service)

  def can_be_on?(:vehicle, ctx),
    do: present?(ctx, :selected_service) and present?(ctx, :current_customer)

  def can_be_on?(:address, ctx),
    do: can_be_on?(:vehicle, ctx) and present?(ctx, :selected_vehicle)

  def can_be_on?(:photos, ctx), do: can_be_on?(:address, ctx) and present?(ctx, :selected_address)
  def can_be_on?(:schedule, ctx), do: can_be_on?(:photos, ctx)
  def can_be_on?(:review, ctx), do: can_be_on?(:schedule, ctx) and present?(ctx, :selected_slot)
  def can_be_on?(:confirmed, ctx), do: present?(ctx, :appointment)

  @doc "Given a claimed step, find the highest valid step. Used for reconnection recovery."
  @spec resolve_step(step(), context()) :: step()
  def resolve_step(claimed_step, context) do
    if can_be_on?(claimed_step, context) do
      case claimed_step do
        :auth when context.current_customer != nil -> :vehicle
        _ -> claimed_step
      end
    else
      steps_up_to =
        @steps
        |> Enum.take_while(&(&1 != claimed_step))
        |> Kernel.++([claimed_step])

      resolved =
        steps_up_to
        |> Enum.reverse()
        |> Enum.find(:select_service, &can_be_on?(&1, context))

      case resolved do
        :auth when context.current_customer != nil -> :vehicle
        other -> other
      end
    end
  end

  # --- Forward guards: what must be true to LEAVE the step ---

  defp validate_forward_guard(:select_service, ctx), do: require_present(ctx, :selected_service)
  defp validate_forward_guard(:auth, ctx), do: require_present(ctx, :current_customer)
  defp validate_forward_guard(:vehicle, ctx), do: require_present(ctx, :selected_vehicle)
  defp validate_forward_guard(:address, ctx), do: require_present(ctx, :selected_address)
  # Optional — always passes
  defp validate_forward_guard(:photos, _ctx), do: :ok
  defp validate_forward_guard(:schedule, ctx), do: require_present(ctx, :selected_slot)
  defp validate_forward_guard(:review, _ctx), do: :ok
  defp validate_forward_guard(:confirmed, _ctx), do: {:error, :already_confirmed}

  # --- Skip logic: auth is skipped when customer already present ---

  defp maybe_skip(:auth, :forward, ctx) when ctx.current_customer != nil, do: {:ok, :vehicle}
  defp maybe_skip(:auth, :back, ctx) when ctx.current_customer != nil, do: {:ok, :select_service}
  defp maybe_skip(step, _direction, _ctx), do: {:ok, step}

  # --- Raw next/prev (no skipping) ---

  defp raw_next(:select_service), do: {:ok, :auth}
  defp raw_next(:auth), do: {:ok, :vehicle}
  defp raw_next(:vehicle), do: {:ok, :address}
  defp raw_next(:address), do: {:ok, :photos}
  defp raw_next(:photos), do: {:ok, :schedule}
  defp raw_next(:schedule), do: {:ok, :review}
  defp raw_next(:review), do: {:ok, :confirmed}
  defp raw_next(:confirmed), do: {:error, :no_next_step}

  defp raw_prev(:select_service), do: {:error, :no_prev_step}
  defp raw_prev(:auth), do: {:ok, :select_service}
  defp raw_prev(:vehicle), do: {:ok, :auth}
  defp raw_prev(:address), do: {:ok, :vehicle}
  defp raw_prev(:photos), do: {:ok, :address}
  defp raw_prev(:schedule), do: {:ok, :photos}
  defp raw_prev(:review), do: {:ok, :schedule}
  defp raw_prev(:confirmed), do: {:error, :cannot_go_back}

  defp require_present(ctx, key) do
    if Map.get(ctx, key) != nil, do: :ok, else: {:error, :"missing_#{key}"}
  end

  defp present?(ctx, key), do: Map.get(ctx, key) != nil
end
