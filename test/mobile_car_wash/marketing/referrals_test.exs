defmodule MobileCarWash.Marketing.ReferralsTest do
  @moduledoc """
  Marketing Phase 2E / Slice 1: the Referrals module unifies the
  existing `referral_code` / `referred_by` fields on Customer with
  a reward-issuance engine.

  Contract pinned:
    * share_link_for/1 returns a UTM-tagged landing URL containing
      the customer's referral_code
    * issue_reward/1 credits the referrer's referral_credit_cents
      exactly once per referee (idempotent on repeated calls)
    * Customers with no `referred_by_id` are silently skipped
    * The reward amount comes from :referral_reward_cents app env
      (default $10 = 1000 cents)
  """
  use MobileCarWash.DataCase, async: false

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Marketing.Referrals

  defp register! do
    {:ok, c} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "ref-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Ref Test",
        phone:
          "+15125557#{:rand.uniform(999) |> Integer.to_string() |> String.pad_leading(3, "0")}"
      })
      |> Ash.create()

    c
  end

  defp register_with_referrer!(referrer) do
    {:ok, c} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "ref-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Referred",
        phone:
          "+15125557#{:rand.uniform(999) |> Integer.to_string() |> String.pad_leading(3, "0")}"
      })
      |> Ash.Changeset.force_change_attribute(:referred_by_id, referrer.id)
      |> Ash.create()

    c
  end

  defp reload!(customer) do
    {:ok, c} = Ash.get(Customer, customer.id, authorize?: false)
    c
  end

  describe "share_link_for/1" do
    test "builds a UTM-tagged URL with the customer's referral code" do
      customer = register!()
      link = Referrals.share_link_for(customer)

      assert link =~ customer.referral_code
      assert link =~ "utm_source=referral"
      assert link =~ "utm_medium=share"
      assert link =~ "ref=#{customer.referral_code}"
    end

    test "uses the configured external_base_url" do
      original = Application.get_env(:mobile_car_wash, :external_base_url)

      Application.put_env(:mobile_car_wash, :external_base_url, "https://example.com")

      on_exit(fn ->
        if original do
          Application.put_env(:mobile_car_wash, :external_base_url, original)
        else
          Application.delete_env(:mobile_car_wash, :external_base_url)
        end
      end)

      customer = register!()
      link = Referrals.share_link_for(customer)

      assert String.starts_with?(link, "https://example.com/")
    end
  end

  describe "issue_reward/1" do
    test "credits the referrer and stamps the referee" do
      referrer = register!()
      referee = register_with_referrer!(referrer)

      assert {:ok, :rewarded} = Referrals.issue_reward(referee.id)

      updated_referrer = reload!(referrer)
      assert updated_referrer.referral_credit_cents == 1_000

      updated_referee = reload!(referee)
      assert updated_referee.referral_reward_issued_at != nil
    end

    test "is idempotent — second call is a silent no-op" do
      referrer = register!()
      referee = register_with_referrer!(referrer)

      assert {:ok, :rewarded} = Referrals.issue_reward(referee.id)
      assert {:ok, :already_rewarded} = Referrals.issue_reward(referee.id)

      assert reload!(referrer).referral_credit_cents == 1_000
    end

    test "silently skips customers with no referred_by_id" do
      customer = register!()

      assert {:ok, :not_referred} = Referrals.issue_reward(customer.id)
    end

    test "uses the configured reward amount" do
      original = Application.get_env(:mobile_car_wash, :referral_reward_cents)

      Application.put_env(:mobile_car_wash, :referral_reward_cents, 2_500)

      on_exit(fn ->
        if original do
          Application.put_env(:mobile_car_wash, :referral_reward_cents, original)
        else
          Application.delete_env(:mobile_car_wash, :referral_reward_cents)
        end
      end)

      referrer = register!()
      referee = register_with_referrer!(referrer)

      assert {:ok, :rewarded} = Referrals.issue_reward(referee.id)
      assert reload!(referrer).referral_credit_cents == 2_500
    end

    test "returns {:error, :not_found} for an unknown customer_id" do
      assert {:error, :not_found} = Referrals.issue_reward(Ecto.UUID.generate())
    end
  end
end
