defmodule MobileCarWash.Scheduling.BookingReferralTest do
  use MobileCarWash.DataCase, async: true

  alias MobileCarWash.Scheduling.Booking
  alias MobileCarWash.Accounts.Customer

  describe "validate_referral_code/2" do
    test "returns {:ok, referrer} for a valid code" do
      {:ok, referrer} =
        Customer
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "referrer-#{System.unique_integer([:positive])}@test.com",
          password: "Password123!",
          password_confirmation: "Password123!",
          name: "Referrer"
        })
        |> Ash.create()

      {:ok, found} = Booking.validate_referral_code(referrer.referral_code, Ash.UUID.generate())
      assert found.id == referrer.id
    end

    test "returns {:error, :not_found} for invalid code" do
      assert {:error, :not_found} =
               Booking.validate_referral_code("BADCODE1", Ash.UUID.generate())
    end

    test "returns {:error, :self_referral} if customer uses own code" do
      {:ok, customer} =
        Customer
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "self-ref-#{System.unique_integer([:positive])}@test.com",
          password: "Password123!",
          password_confirmation: "Password123!",
          name: "Self Referrer"
        })
        |> Ash.create()

      assert {:error, :self_referral} =
               Booking.validate_referral_code(customer.referral_code, customer.id)
    end
  end

  describe "apply_referral_discount/2" do
    test "subtracts $10 from price" do
      assert {4000, 1000} = Booking.apply_referral_discount(5000, 0)
    end

    test "does not go below zero" do
      assert {0, 500} = Booking.apply_referral_discount(500, 0)
    end

    test "adds to existing discount" do
      assert {4000, 1500} = Booking.apply_referral_discount(5000, 500)
    end
  end
end
