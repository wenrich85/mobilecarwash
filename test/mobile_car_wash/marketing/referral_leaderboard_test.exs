defmodule MobileCarWash.Marketing.ReferralLeaderboardTest do
  @moduledoc """
  Marketing Phase 2E / Slice 4: `Referrals.leaderboard/1` returns the
  top referrers ranked by count of successful referrals (referees
  whose `referral_reward_issued_at` is set).

  Drives the leaderboard section on /admin/marketing.
  """
  use MobileCarWash.DataCase, async: false

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Marketing.Referrals

  defp register! do
    {:ok, c} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "lb-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "LB Test",
        phone: "+15125554#{:rand.uniform(999) |> Integer.to_string() |> String.pad_leading(3, "0")}"
      })
      |> Ash.create()

    c
  end

  defp referee_of!(referrer) do
    {:ok, c} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "ee-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "EE",
        phone: "+15125553#{:rand.uniform(999) |> Integer.to_string() |> String.pad_leading(3, "0")}"
      })
      |> Ash.Changeset.force_change_attribute(:referred_by_id, referrer.id)
      |> Ash.create()

    c
  end

  test "ranks referrers by successful-referral count, descending" do
    top = register!()
    middle = register!()
    bottom = register!()

    # top brings in 3 successful referrals
    for _ <- 1..3 do
      referee = referee_of!(top)
      {:ok, :rewarded} = Referrals.issue_reward(referee.id)
    end

    # middle brings in 2
    for _ <- 1..2 do
      referee = referee_of!(middle)
      {:ok, :rewarded} = Referrals.issue_reward(referee.id)
    end

    # bottom brings in 1
    referee = referee_of!(bottom)
    {:ok, :rewarded} = Referrals.issue_reward(referee.id)

    # Also seed an unrewarded referee (doesn't count)
    _ = referee_of!(top)

    rows = Referrals.leaderboard(5)

    ids = Enum.map(rows, & &1.customer_id)
    assert ids == [top.id, middle.id, bottom.id]

    top_row = Enum.find(rows, &(&1.customer_id == top.id))
    assert top_row.referral_count == 3
    assert top_row.name == top.name
    assert top_row.credit_cents == 3_000
  end

  test "respects the limit argument" do
    for _ <- 1..5 do
      referrer = register!()
      referee = referee_of!(referrer)
      {:ok, :rewarded} = Referrals.issue_reward(referee.id)
    end

    rows = Referrals.leaderboard(3)
    assert length(rows) == 3
  end

  test "returns [] when no rewards have fired" do
    # Register some customers without referral activity
    for _ <- 1..3, do: register!()

    assert Referrals.leaderboard(10) == []
  end
end
