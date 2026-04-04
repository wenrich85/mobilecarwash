defmodule MobileCarWash.Loyalty do
  @moduledoc """
  Loyalty punch card system.
  Every completed wash earns 1 punch. Every 10 punches = 1 free wash.
  """
  use Ash.Domain

  alias MobileCarWash.Loyalty.LoyaltyCard

  require Ash.Query

  resources do
    resource LoyaltyCard
  end

  @punches_per_reward 10

  @doc "Get or create a loyalty card for a customer."
  def get_or_create_card(customer_id) do
    case LoyaltyCard
         |> Ash.Query.filter(customer_id == ^customer_id)
         |> Ash.read_one(authorize?: false) do
      {:ok, nil} ->
        LoyaltyCard
        |> Ash.Changeset.for_create(:create, %{customer_id: customer_id})
        |> Ash.create(authorize?: false)

      {:ok, card} ->
        {:ok, card}

      error ->
        error
    end
  end

  @doc "Award one punch for a completed wash. Idempotent on repeated calls."
  def add_punch(customer_id) do
    case get_or_create_card(customer_id) do
      {:ok, card} ->
        card
        |> Ash.Changeset.for_update(:add_punch, %{})
        |> Ash.update(authorize?: false)

      error ->
        error
    end
  end

  @doc """
  Redeem one free wash. Returns {:error, :no_free_washes} if balance is zero.
  """
  def redeem(customer_id) do
    case get_or_create_card(customer_id) do
      {:ok, card} ->
        if available_free_washes(card) > 0 do
          card
          |> Ash.Changeset.for_update(:redeem, %{})
          |> Ash.update(authorize?: false)
        else
          {:error, :no_free_washes}
        end

      error ->
        error
    end
  end

  @doc "Number of free washes available to redeem."
  def available_free_washes(nil), do: 0
  def available_free_washes(%{punch_count: p, redeemed_count: r}),
    do: Kernel.max(div(p, @punches_per_reward) - r, 0)

  @doc "How many punches into the current (incomplete) cycle."
  def punches_in_cycle(nil), do: 0
  def punches_in_cycle(%{punch_count: p}), do: rem(p, @punches_per_reward)

  @doc "Total punches needed per reward."
  def punches_per_reward, do: @punches_per_reward
end
