defmodule MobileCarWash.Accounts.CustomerReferralTest do
  use MobileCarWash.DataCase, async: true

  alias MobileCarWash.Accounts.Customer

  describe "referral code generation" do
    test "auto-generates a referral_code on registration" do
      {:ok, customer} =
        Customer
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "ref-gen-#{System.unique_integer([:positive])}@test.com",
          password: "Password123!",
          password_confirmation: "Password123!",
          name: "Referral Gen Test"
        })
        |> Ash.create()

      assert customer.referral_code != nil
      assert String.length(customer.referral_code) == 8
      assert customer.referral_code =~ ~r/^[A-Z0-9]+$/
    end

    test "referral codes are unique across customers" do
      codes =
        for i <- 1..5 do
          {:ok, c} =
            Customer
            |> Ash.Changeset.for_create(:register_with_password, %{
              email: "ref-uniq-#{i}-#{System.unique_integer([:positive])}@test.com",
              password: "Password123!",
              password_confirmation: "Password123!",
              name: "Unique #{i}"
            })
            |> Ash.create()

          c.referral_code
        end

      assert length(Enum.uniq(codes)) == 5
    end

    test "referral_credit_cents defaults to 0" do
      {:ok, customer} =
        Customer
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "ref-credit-#{System.unique_integer([:positive])}@test.com",
          password: "Password123!",
          password_confirmation: "Password123!",
          name: "Credit Test"
        })
        |> Ash.create()

      assert customer.referral_credit_cents == 0
    end

    test "can look up customer by referral code" do
      {:ok, customer} =
        Customer
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "ref-lookup-#{System.unique_integer([:positive])}@test.com",
          password: "Password123!",
          password_confirmation: "Password123!",
          name: "Lookup Test"
        })
        |> Ash.create()

      [found] =
        Customer
        |> Ash.Query.for_read(:by_referral_code, %{referral_code: customer.referral_code})
        |> Ash.read!(authorize?: false)

      assert found.id == customer.id
    end
  end
end
