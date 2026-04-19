defmodule MobileCarWash.Accounts.CustomerInputValidationTest do
  @moduledoc """
  SECURITY_AUDIT_REPORT MEDIUM #3 + #4: neither email nor phone had
  format validation at the resource level. Customers could register
  with "not-an-email" or "haha" as a phone number, and downstream
  integrations (Twilio SMS, Swoosh email) would be the first to
  actually catch the malformed value — by then it's already in the DB
  and failing jobs somewhere.

  These tests pin the resource-level validation:

    * email must contain an @ with non-empty parts on each side and at
      least one dot in the domain. Permissive enough to accept the
      valid shapes developers test with, strict enough to block
      obvious garbage.
    * phone is optional. When present, it must be digits + optional
      separators + optional leading + so Twilio-compatible formats
      pass (E.164, US with dashes, US with parens) and arbitrary text
      fails.
  """
  use MobileCarWash.DataCase, async: true

  alias MobileCarWash.Accounts.Customer

  defp register(attrs) do
    defaults = %{
      password: "Password123!",
      password_confirmation: "Password123!",
      name: "Input Validator"
    }

    Customer
    |> Ash.Changeset.for_create(:register_with_password, Map.merge(defaults, attrs))
    |> Ash.create()
  end

  describe "email format" do
    test "accepts plain valid emails" do
      assert {:ok, _} =
               register(%{
                 email: "customer-#{System.unique_integer([:positive])}@example.com",
                 phone: "+15125551000"
               })
    end

    test "accepts emails with plus addressing" do
      assert {:ok, _} =
               register(%{
                 email: "customer+promo-#{System.unique_integer([:positive])}@example.com",
                 phone: "+15125551001"
               })
    end

    test "rejects a string with no @" do
      assert {:error, _} = register(%{email: "notanemail", phone: "+15125551002"})
    end

    test "rejects an address without a domain dot" do
      assert {:error, _} = register(%{email: "user@localhost", phone: "+15125551003"})
    end

    test "rejects an empty local part" do
      assert {:error, _} = register(%{email: "@example.com", phone: "+15125551004"})
    end

    test "rejects a string with embedded whitespace" do
      assert {:error, _} = register(%{email: "user name@example.com", phone: "+15125551005"})
    end
  end

  describe "phone format" do
    test "is optional — registration succeeds with no phone" do
      assert {:ok, _} =
               register(%{
                 email: "nophone-#{System.unique_integer([:positive])}@example.com"
               })
    end

    test "accepts E.164 (+15125551234)" do
      assert {:ok, _} =
               register(%{
                 email: "e164-#{System.unique_integer([:positive])}@example.com",
                 phone: "+15125551234"
               })
    end

    test "accepts US dashes (512-555-1234)" do
      assert {:ok, _} =
               register(%{
                 email: "dash-#{System.unique_integer([:positive])}@example.com",
                 phone: "512-555-1234"
               })
    end

    test "accepts US parens ((512) 555-1234)" do
      assert {:ok, _} =
               register(%{
                 email: "paren-#{System.unique_integer([:positive])}@example.com",
                 phone: "(512) 555-1234"
               })
    end

    test "rejects letters" do
      assert {:error, _} =
               register(%{
                 email: "alpha-#{System.unique_integer([:positive])}@example.com",
                 phone: "haha"
               })
    end

    test "rejects a too-short number" do
      assert {:error, _} =
               register(%{
                 email: "short-#{System.unique_integer([:positive])}@example.com",
                 phone: "123"
               })
    end
  end
end
