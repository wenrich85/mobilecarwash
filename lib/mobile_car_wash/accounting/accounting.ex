defmodule MobileCarWash.Accounting do
  @moduledoc """
  Accounting facade — delegates to the configured provider.
  Change providers by setting `:accounting_provider` in config.

  ## Swapping providers
      # config/runtime.exs
      config :mobile_car_wash, :accounting_provider, MobileCarWash.Accounting.QuickBooks
  """

  require Logger

  def provider do
    Application.get_env(:mobile_car_wash, :accounting_provider, MobileCarWash.Accounting.ZohoBooks)
  end

  @doc "Find or create a contact in the accounting system."
  def find_or_create_contact(params) do
    case provider().find_contact_by_email(params.email) do
      {:ok, contact} -> {:ok, contact}
      {:error, :not_found} -> provider().create_contact(params)
      {:error, reason} -> {:error, reason}
    end
  end

  def create_invoice(params), do: provider().create_invoice(params)
  def record_payment(invoice_id, params), do: provider().record_payment(invoice_id, params)
  def get_invoice(invoice_id), do: provider().get_invoice(invoice_id)

  @doc """
  Full sync: find/create contact, create invoice, record payment.
  Called from AccountingSyncWorker. Returns :ok or logs error.
  """
  def sync_payment(customer, payment, service_name) do
    with {:ok, contact} <- find_or_create_contact(%{
           name: customer.name,
           email: to_string(customer.email),
           phone: customer.phone
         }),
         contact_id = extract_contact_id(contact),
         {:ok, invoice} <- create_invoice(%{
           contact_id: contact_id,
           line_items: [%{name: service_name, amount_cents: payment.amount_cents, quantity: 1}],
           payment_id: payment.id,
           notes: "Driveway Detail Co — #{service_name}"
         }),
         invoice_id = extract_invoice_id(invoice),
         {:ok, _} <- record_payment(invoice_id, %{
           amount_cents: payment.amount_cents,
           payment_date: if(payment.paid_at, do: DateTime.to_date(payment.paid_at), else: Date.utc_today()),
           reference: payment.stripe_payment_intent_id
         }) do
      :ok
    else
      {:error, :zoho_not_configured} ->
        Logger.debug("Accounting sync skipped — provider not configured")
        :ok

      {:error, :quickbooks_not_configured} ->
        Logger.debug("Accounting sync skipped — provider not configured")
        :ok

      {:error, :not_configured} ->
        Logger.debug("Accounting sync skipped — provider not configured")
        :ok

      {:error, reason} ->
        Logger.error("Accounting sync failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Extract contact ID from provider-specific response shapes
  defp extract_contact_id(%{"contact_id" => id}), do: id  # Zoho
  defp extract_contact_id(%{"Id" => id}), do: id          # QuickBooks
  defp extract_contact_id(contact), do: contact["id"]

  # Extract invoice ID from provider-specific response shapes
  defp extract_invoice_id(%{"invoice_id" => id}), do: id   # Zoho
  defp extract_invoice_id(%{"Id" => id}), do: id           # QuickBooks
  defp extract_invoice_id(invoice), do: invoice["id"]
end
