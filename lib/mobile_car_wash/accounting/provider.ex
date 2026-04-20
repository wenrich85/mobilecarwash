defmodule MobileCarWash.Accounting.Provider do
  @moduledoc """
  Behaviour defining the contract for accounting integrations.
  Implement this for any provider: Zoho Books, QuickBooks, Xero, FreshBooks, etc.
  """

  @type invoice_params :: %{
          customer_name: String.t(),
          customer_email: String.t(),
          line_items: [%{name: String.t(), amount_cents: integer(), quantity: integer()}],
          payment_id: String.t(),
          notes: String.t() | nil
        }

  @type contact_params :: %{
          name: String.t(),
          email: String.t(),
          phone: String.t() | nil
        }

  @type payment_params :: %{
          amount_cents: integer(),
          payment_date: Date.t(),
          reference: String.t() | nil
        }

  @callback create_contact(contact_params()) :: {:ok, map()} | {:error, term()}
  @callback find_contact_by_email(String.t()) ::
              {:ok, map()} | {:error, :not_found} | {:error, term()}
  @callback create_invoice(invoice_params()) :: {:ok, map()} | {:error, term()}
  @callback record_payment(invoice_id :: String.t(), payment_params()) ::
              {:ok, map()} | {:error, term()}
  @callback get_invoice(invoice_id :: String.t()) :: {:ok, map()} | {:error, term()}
end
