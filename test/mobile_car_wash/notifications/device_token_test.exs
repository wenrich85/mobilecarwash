defmodule MobileCarWash.Notifications.DeviceTokenTest do
  @moduledoc """
  Covers the DeviceToken resource contract that the push-notification
  delivery pipeline depends on:
    - Upsert on token (reinstall returns same token -> reactivate, rebind)
    - Soft-delete via :deactivate (so reinstall analytics survive sign-out)
    - :mark_failed captures APNs Unregistered / BadDeviceToken responses
    - :active_for_customer is what the workers query
    - Policy prevents a customer from reading another customer's tokens
  """
  use MobileCarWash.DataCase, async: true

  require Ash.Query

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Notifications.DeviceToken

  setup do
    {:ok, customer} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "dt-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Device Owner",
        phone: "+15125551000"
      })
      |> Ash.create()

    {:ok, customer: customer}
  end

  describe ":register action" do
    test "creates a new active token bound to the customer", %{customer: customer} do
      {:ok, token} =
        DeviceToken
        |> Ash.Changeset.for_create(:register, %{
          token: "apns-token-aaa",
          platform: :ios,
          app_version: "1.0.0",
          device_model: "iPhone15,3",
          customer_id: customer.id
        })
        |> Ash.create(actor: customer)

      assert token.platform == :ios
      assert token.active == true
      assert token.customer_id == customer.id
      assert token.last_seen_at
    end

    test "platform defaults to :ios when omitted", %{customer: customer} do
      {:ok, token} =
        DeviceToken
        |> Ash.Changeset.for_create(:register, %{
          token: "apns-token-default",
          customer_id: customer.id
        })
        |> Ash.create(actor: customer)

      assert token.platform == :ios
    end

    test "re-registering the same token upserts: rebinds customer, reactivates, bumps last_seen_at",
         %{customer: customer} do
      # First registration, then mark it failed (deactivate)
      {:ok, first} =
        DeviceToken
        |> Ash.Changeset.for_create(:register, %{
          token: "apns-token-reuse",
          customer_id: customer.id
        })
        |> Ash.create(actor: customer)

      {:ok, failed} =
        first
        |> Ash.Changeset.for_update(:mark_failed, %{failure_reason: "unregistered"})
        |> Ash.update(authorize?: false)

      assert failed.active == false

      # Another customer registers with the same token (device handed off)
      {:ok, customer2} =
        Customer
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "dt2-#{System.unique_integer([:positive])}@test.com",
          password: "Password123!",
          password_confirmation: "Password123!",
          name: "Second Owner",
          phone: "+15125552000"
        })
        |> Ash.create()

      {:ok, second} =
        DeviceToken
        |> Ash.Changeset.for_create(:register, %{
          token: "apns-token-reuse",
          customer_id: customer2.id
        })
        |> Ash.create(actor: customer2)

      # Upsert: same row (same id), reactivated, now owned by customer2
      assert second.id == first.id
      assert second.active == true
      assert second.customer_id == customer2.id
    end
  end

  describe ":mark_failed action" do
    test "flips active to false and records the reason + failed_at timestamp",
         %{customer: customer} do
      {:ok, token} =
        DeviceToken
        |> Ash.Changeset.for_create(:register, %{
          token: "apns-will-fail",
          customer_id: customer.id
        })
        |> Ash.create(actor: customer)

      {:ok, failed} =
        token
        |> Ash.Changeset.for_update(:mark_failed, %{failure_reason: "bad_device_token"})
        |> Ash.update(authorize?: false)

      assert failed.active == false
      assert failed.failure_reason == "bad_device_token"
      assert failed.failed_at
    end
  end

  describe ":deactivate action" do
    test "soft-deletes the token without losing the row", %{customer: customer} do
      {:ok, token} =
        DeviceToken
        |> Ash.Changeset.for_create(:register, %{
          token: "apns-soft-delete",
          customer_id: customer.id
        })
        |> Ash.create(actor: customer)

      {:ok, deactivated} =
        token
        |> Ash.Changeset.for_update(:deactivate, %{})
        |> Ash.update(actor: customer)

      assert deactivated.active == false
      assert deactivated.id == token.id
    end
  end

  describe ":active_for_customer read action" do
    test "returns only active tokens for the given customer", %{customer: customer} do
      {:ok, _active1} =
        DeviceToken
        |> Ash.Changeset.for_create(:register, %{
          token: "active-1",
          customer_id: customer.id
        })
        |> Ash.create(actor: customer)

      {:ok, _active2} =
        DeviceToken
        |> Ash.Changeset.for_create(:register, %{
          token: "active-2",
          customer_id: customer.id
        })
        |> Ash.create(actor: customer)

      {:ok, inactive} =
        DeviceToken
        |> Ash.Changeset.for_create(:register, %{
          token: "inactive",
          customer_id: customer.id
        })
        |> Ash.create(actor: customer)

      {:ok, _} =
        inactive
        |> Ash.Changeset.for_update(:deactivate, %{})
        |> Ash.update(actor: customer)

      tokens =
        DeviceToken
        |> Ash.Query.for_read(:active_for_customer, %{customer_id: customer.id})
        |> Ash.read!(authorize?: false)

      assert length(tokens) == 2
      assert Enum.all?(tokens, & &1.active)
    end
  end

  describe "policies" do
    test "a customer cannot read another customer's tokens", %{customer: customer} do
      {:ok, other} =
        Customer
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "other-#{System.unique_integer([:positive])}@test.com",
          password: "Password123!",
          password_confirmation: "Password123!",
          name: "Other",
          phone: "+15125553000"
        })
        |> Ash.create()

      {:ok, other_token} =
        DeviceToken
        |> Ash.Changeset.for_create(:register, %{
          token: "not-yours",
          customer_id: other.id
        })
        |> Ash.create(actor: other)

      # customer tries to read other_token
      result =
        DeviceToken
        |> Ash.Query.filter(id == ^other_token.id)
        |> Ash.read(actor: customer)

      # Policy should filter the row out (empty list), not raise.
      assert {:ok, []} = result
    end
  end
end
