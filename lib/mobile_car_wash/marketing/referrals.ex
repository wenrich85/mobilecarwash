defmodule MobileCarWash.Marketing.Referrals do
  @moduledoc """
  Referral rewards engine. Builds share links and issues one-time
  credits when a referred customer becomes a paying customer.

  The reward amount is read from `:referral_reward_cents` app env
  (default $10 = 1000 cents). The landing URL base comes from
  `:external_base_url` (same setting the email verification worker
  uses).

  Idempotency is enforced by stamping `referral_reward_issued_at`
  on the *referee*. The first `issue_reward/1` credits the referrer
  and stamps the referee; subsequent calls return `:already_rewarded`.
  """

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Repo

  import Ecto.Query

  @default_reward_cents 1_000
  @default_base_url "https://drivewaydetailcosa.com"

  @doc """
  The reward amount expressed in dollars, for display in the share
  card ("Earn $10 when a friend books").
  """
  @spec default_reward_dollars() :: integer()
  def default_reward_dollars do
    cents = Application.get_env(:mobile_car_wash, :referral_reward_cents, @default_reward_cents)
    div(cents, 100)
  end

  @doc """
  Builds a UTM-tagged landing URL with the customer's referral code
  embedded as `?ref=CODE`. Carries UTM source/medium so the
  attribution plug can bucket the lead correctly.
  """
  @spec share_link_for(Customer.t()) :: String.t()
  def share_link_for(%Customer{referral_code: code}) when is_binary(code) do
    base = Application.get_env(:mobile_car_wash, :external_base_url, @default_base_url)

    "#{base}/?utm_source=referral&utm_medium=share&ref=#{URI.encode_www_form(code)}"
  end

  @doc """
  Issues a one-time referral reward for the given customer. Looks up
  the customer, finds their referrer (if any), credits the referrer's
  `referral_credit_cents`, and stamps the referee's
  `referral_reward_issued_at` to prevent re-crediting.

  Returns:
    * `{:ok, :rewarded}`         — new credit issued
    * `{:ok, :already_rewarded}` — idempotent no-op on repeat calls
    * `{:ok, :not_referred}`     — customer has no referrer
    * `{:error, :not_found}`     — unknown customer_id
  """
  @spec issue_reward(binary()) ::
          {:ok, :rewarded | :already_rewarded | :not_referred} | {:error, :not_found}
  def issue_reward(customer_id) when is_binary(customer_id) do
    case Ash.get(Customer, customer_id, authorize?: false) do
      {:ok, customer} -> handle(customer)
      {:error, _} -> {:error, :not_found}
    end
  end

  defp handle(%Customer{referred_by_id: nil}), do: {:ok, :not_referred}

  defp handle(%Customer{referral_reward_issued_at: %DateTime{}}),
    do: {:ok, :already_rewarded}

  defp handle(%Customer{referred_by_id: referrer_id} = referee) do
    reward_cents =
      Application.get_env(:mobile_car_wash, :referral_reward_cents, @default_reward_cents)

    with {:ok, referrer} <- Ash.get(Customer, referrer_id, authorize?: false),
         {:ok, _referrer} <- credit_referrer(referrer, reward_cents),
         {:ok, _referee} <- stamp_referee(referee) do
      {:ok, :rewarded}
    else
      _ -> {:error, :not_found}
    end
  end

  defp credit_referrer(%Customer{} = referrer, reward_cents) do
    new_balance = (referrer.referral_credit_cents || 0) + reward_cents

    referrer
    |> Ash.Changeset.for_update(:update, %{})
    |> Ash.Changeset.force_change_attribute(:referral_credit_cents, new_balance)
    |> Ash.update(authorize?: false)
  end

  @doc """
  Top referrers ranked by count of successful referrals (referees
  whose referral_reward_issued_at is set). Returns a list of maps:

      [%{
        customer_id: uuid,
        name: "Alice",
        referral_count: 3,
        credit_cents: 3000
      }, ...]
  """
  @spec leaderboard(pos_integer()) :: [map()]
  def leaderboard(limit) when is_integer(limit) and limit > 0 do
    query =
      from referee in "customers",
        where: not is_nil(referee.referral_reward_issued_at),
        where: not is_nil(referee.referred_by_id),
        join: referrer in "customers",
        on: referrer.id == referee.referred_by_id,
        group_by: [referrer.id, referrer.name, referrer.referral_credit_cents],
        select: %{
          customer_id: type(referrer.id, Ecto.UUID),
          name: referrer.name,
          referral_count: count(referee.id),
          credit_cents: referrer.referral_credit_cents
        },
        order_by: [desc: count(referee.id), asc: referrer.name],
        limit: ^limit

    Repo.all(query)
  end

  defp stamp_referee(%Customer{} = referee) do
    referee
    |> Ash.Changeset.for_update(:update, %{})
    |> Ash.Changeset.force_change_attribute(:referral_reward_issued_at, DateTime.utc_now())
    |> Ash.update(authorize?: false)
  end
end
