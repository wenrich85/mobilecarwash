defmodule MobileCarWash.Accounts.CustomerSmsOptInTest do
  use MobileCarWash.DataCase, async: true

  alias MobileCarWash.Accounts.Customer

  describe "sms_opt_in attribute" do
    test "defaults to false" do
      {:ok, customer} =
        Customer
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "sms-default@test.com",
          password: "Password123!",
          password_confirmation: "Password123!",
          name: "SMS Default Test"
        })
        |> Ash.create()

      assert customer.sms_opt_in == false
    end

    test "can be set to true during registration" do
      {:ok, customer} =
        Customer
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "sms-optin@test.com",
          password: "Password123!",
          password_confirmation: "Password123!",
          name: "SMS Opt-in Test",
          sms_opt_in: true
        })
        |> Ash.create()

      assert customer.sms_opt_in == true
    end

    test "can be updated after creation" do
      {:ok, customer} =
        Customer
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "sms-update@test.com",
          password: "Password123!",
          password_confirmation: "Password123!",
          name: "SMS Update Test"
        })
        |> Ash.create()

      assert customer.sms_opt_in == false

      {:ok, updated} =
        customer
        |> Ash.Changeset.for_update(:update, %{sms_opt_in: true})
        |> Ash.update(authorize?: false)

      assert updated.sms_opt_in == true
    end
  end
end
