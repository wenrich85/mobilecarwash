defmodule MobileCarWash.Accounts.PushOptInTest do
  @moduledoc """
  Customer.push_opt_in is the server-side opt-out for APNs push. Unlike
  sms_opt_in (default false — TCPA-sensitive), push defaults to true because
  iOS's UNUserNotificationCenter permission prompt already gates delivery
  client-side. push_opt_in lets users revoke *in-app* without going to
  iOS Settings.
  """
  use MobileCarWash.DataCase, async: true

  alias MobileCarWash.Accounts.Customer

  describe ":push_opt_in attribute" do
    test "defaults to true on registration" do
      {:ok, customer} =
        Customer
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "push-opt-#{System.unique_integer([:positive])}@test.com",
          password: "Password123!",
          password_confirmation: "Password123!",
          name: "Push Default"
        })
        |> Ash.create()

      assert customer.push_opt_in == true
    end

    test "register action accepts an explicit push_opt_in: false" do
      {:ok, customer} =
        Customer
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "push-no-#{System.unique_integer([:positive])}@test.com",
          password: "Password123!",
          password_confirmation: "Password123!",
          name: "Opt Out",
          push_opt_in: false
        })
        |> Ash.create()

      assert customer.push_opt_in == false
    end

    test "customer can update their own push_opt_in via the default update action" do
      {:ok, customer} =
        Customer
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "push-update-#{System.unique_integer([:positive])}@test.com",
          password: "Password123!",
          password_confirmation: "Password123!",
          name: "Will Toggle"
        })
        |> Ash.create()

      {:ok, updated} =
        customer
        |> Ash.Changeset.for_update(:update, %{push_opt_in: false})
        |> Ash.update(actor: customer)

      assert updated.push_opt_in == false
    end
  end
end
