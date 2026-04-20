defmodule MobileCarWash.Billing.SubscriptionStateMachine do
  @moduledoc """
  Pure functional state machine for the subscription signup flow.
  No dependencies on Phoenix, LiveView, or Ash.

  Steps: select_plan → auth → review → checkout
  Auth is auto-skipped when customer is already logged in.
  No guest mode — subscriptions require a real account.
  """

  @steps [:select_plan, :auth, :review, :checkout]

  @type step :: :select_plan | :auth | :review | :checkout

  @type context :: %{
          selected_plan: term(),
          current_customer: term()
        }

  def steps, do: @steps

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

  @spec can_be_on?(step(), context()) :: boolean()
  def can_be_on?(:select_plan, _ctx), do: true
  def can_be_on?(:auth, ctx), do: present?(ctx, :selected_plan)

  def can_be_on?(:review, ctx),
    do: present?(ctx, :selected_plan) and present?(ctx, :current_customer)

  def can_be_on?(:checkout, ctx), do: can_be_on?(:review, ctx)

  @spec resolve_step(step(), context()) :: step()
  def resolve_step(claimed_step, context) do
    if can_be_on?(claimed_step, context) do
      case claimed_step do
        :auth when context.current_customer != nil -> :review
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
        |> Enum.find(:select_plan, &can_be_on?(&1, context))

      case resolved do
        :auth when context.current_customer != nil -> :review
        other -> other
      end
    end
  end

  # --- Forward guards ---

  defp validate_forward_guard(:select_plan, ctx), do: require_present(ctx, :selected_plan)
  defp validate_forward_guard(:auth, ctx), do: require_present(ctx, :current_customer)
  defp validate_forward_guard(:review, _ctx), do: :ok
  defp validate_forward_guard(:checkout, _ctx), do: {:error, :already_at_checkout}

  # --- Skip logic: auth skipped when customer present ---

  defp maybe_skip(:auth, :forward, ctx) when ctx.current_customer != nil, do: {:ok, :review}
  defp maybe_skip(:auth, :back, ctx) when ctx.current_customer != nil, do: {:ok, :select_plan}
  defp maybe_skip(step, _direction, _ctx), do: {:ok, step}

  # --- Raw next/prev ---

  defp raw_next(:select_plan), do: {:ok, :auth}
  defp raw_next(:auth), do: {:ok, :review}
  defp raw_next(:review), do: {:ok, :checkout}
  defp raw_next(:checkout), do: {:error, :no_next_step}

  defp raw_prev(:select_plan), do: {:error, :no_prev_step}
  defp raw_prev(:auth), do: {:ok, :select_plan}
  defp raw_prev(:review), do: {:ok, :auth}
  defp raw_prev(:checkout), do: {:ok, :review}

  defp require_present(ctx, key) do
    if Map.get(ctx, key) != nil, do: :ok, else: {:error, :"missing_#{key}"}
  end

  defp present?(ctx, key), do: Map.get(ctx, key) != nil
end
