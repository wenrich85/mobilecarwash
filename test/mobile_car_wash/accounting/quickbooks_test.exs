defmodule MobileCarWash.Accounting.QuickBooksTest do
  @moduledoc """
  Unit tests for the QuickBooks Online accounting provider.
  Tests the module's behaviour implementation and API call structure.
  Without valid credentials, API calls return error tuples — never crash.
  """
  use ExUnit.Case, async: true

  alias MobileCarWash.Accounting.QuickBooks

  describe "behaviour implementation" do
    test "implements all Provider callbacks" do
      # Ensure module is loaded
      {:module, _} = Code.ensure_loaded(QuickBooks)

      behaviours = QuickBooks.__info__(:attributes) |> Keyword.get_values(:behaviour)
      assert MobileCarWash.Accounting.Provider in List.flatten(behaviours)
    end

    test "exports all required functions" do
      {:module, _} = Code.ensure_loaded(QuickBooks)

      assert function_exported?(QuickBooks, :create_contact, 1)
      assert function_exported?(QuickBooks, :find_contact_by_email, 1)
      assert function_exported?(QuickBooks, :create_invoice, 1)
      assert function_exported?(QuickBooks, :record_payment, 2)
      assert function_exported?(QuickBooks, :get_invoice, 1)
    end
  end

  describe "create_contact/1 — unconfigured" do
    test "returns :quickbooks_not_configured when credentials are missing" do
      result = QuickBooks.create_contact(%{name: "Test", email: "test@example.com", phone: "555"})
      assert {:error, :quickbooks_not_configured} = result
    end
  end

  describe "find_contact_by_email/1 — unconfigured" do
    test "returns :quickbooks_not_configured when credentials are missing" do
      result = QuickBooks.find_contact_by_email("test@example.com")
      assert {:error, :quickbooks_not_configured} = result
    end
  end

  describe "create_invoice/1 — unconfigured" do
    test "returns :quickbooks_not_configured when credentials are missing" do
      result =
        QuickBooks.create_invoice(%{
          contact_id: "123",
          line_items: [%{name: "Basic Wash", amount_cents: 5000, quantity: 1}],
          payment_id: "pay-1",
          notes: "Test"
        })

      assert {:error, :quickbooks_not_configured} = result
    end
  end

  describe "record_payment/2 — unconfigured" do
    test "returns :quickbooks_not_configured when credentials are missing" do
      result =
        QuickBooks.record_payment("inv-1", %{
          amount_cents: 5000,
          payment_date: ~D[2026-03-30],
          reference: "pi_test"
        })

      assert {:error, :quickbooks_not_configured} = result
    end
  end

  describe "get_invoice/1 — unconfigured" do
    test "returns :quickbooks_not_configured when credentials are missing" do
      result = QuickBooks.get_invoice("inv-1")
      assert {:error, :quickbooks_not_configured} = result
    end
  end
end
