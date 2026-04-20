defmodule MobileCarWash.Accounting.ZohoBooks do
  @moduledoc """
  Zoho Books accounting integration.
  Implements the AccountingProvider behaviour using Zoho Books REST API v3.

  Handles OAuth2 token refresh automatically.
  Swap this module for QuickBooks, Xero, etc. by implementing the same behaviour.
  """
  @behaviour MobileCarWash.Accounting.Provider

  require Logger

  # === Provider Callbacks ===

  @impl true
  def create_contact(params) do
    body = %{
      "contact_name" => params.name,
      "email" => params.email,
      "phone" => params[:phone],
      "contact_type" => "customer"
    }

    case api_post("/contacts", %{"JSONString" => Jason.encode!(body)}) do
      {:ok, %{"contact" => contact}} -> {:ok, contact}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def find_contact_by_email(email) do
    case api_get("/contacts", email: email) do
      {:ok, %{"contacts" => [contact | _]}} -> {:ok, contact}
      {:ok, %{"contacts" => []}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def create_invoice(params) do
    contact_id = params[:contact_id] || params[:zoho_contact_id]

    line_items =
      Enum.map(params.line_items, fn item ->
        %{
          "name" => item.name,
          "rate" => item.amount_cents / 100,
          "quantity" => item[:quantity] || 1
        }
      end)

    body = %{
      "customer_id" => contact_id,
      "line_items" => line_items,
      "notes" => params[:notes] || "Driveway Detail Co — Thank you for your business!",
      "reference_number" => params[:payment_id]
    }

    case api_post("/invoices", %{"JSONString" => Jason.encode!(body)}) do
      {:ok, %{"invoice" => invoice}} -> {:ok, invoice}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def record_payment(invoice_id, params) do
    body = %{
      "amount" => params.amount_cents / 100,
      "date" => Date.to_iso8601(params.payment_date),
      "payment_mode" => "creditcard",
      "reference_number" => params[:reference]
    }

    case api_post("/invoices/#{invoice_id}/payments", %{"JSONString" => Jason.encode!(body)}) do
      {:ok, %{"payment" => payment}} -> {:ok, payment}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def get_invoice(invoice_id) do
    case api_get("/invoices/#{invoice_id}") do
      {:ok, %{"invoice" => invoice}} -> {:ok, invoice}
      {:error, reason} -> {:error, reason}
    end
  end

  # === OAuth2 Token Management ===

  defp get_access_token do
    # Check for cached token first
    case :persistent_term.get({__MODULE__, :access_token}, nil) do
      {token, expires_at} when is_binary(token) ->
        if DateTime.compare(expires_at, DateTime.utc_now()) == :gt do
          {:ok, token}
        else
          refresh_access_token()
        end

      _ ->
        refresh_access_token()
    end
  end

  defp refresh_access_token do
    config = Application.get_env(:mobile_car_wash, :zoho_books, [])
    client_id = config[:client_id]
    client_secret = config[:client_secret]
    refresh_token = config[:refresh_token]

    if is_nil(client_id) or is_nil(refresh_token) do
      {:error, :zoho_not_configured}
    else
      url = "https://accounts.zoho.com/oauth/v2/token"

      body =
        URI.encode_query(%{
          "grant_type" => "refresh_token",
          "client_id" => client_id,
          "client_secret" => client_secret,
          "refresh_token" => refresh_token
        })

      case Req.post(url,
             body: body,
             headers: [{"content-type", "application/x-www-form-urlencoded"}]
           ) do
        {:ok, %{status: 200, body: %{"access_token" => token}}} ->
          expires_at = DateTime.add(DateTime.utc_now(), 3000, :second)
          :persistent_term.put({__MODULE__, :access_token}, {token, expires_at})
          {:ok, token}

        {:ok, resp} ->
          Logger.error("Zoho token refresh failed: #{inspect(resp.body)}")
          {:error, :token_refresh_failed}

        {:error, reason} ->
          Logger.error("Zoho token refresh error: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  # === HTTP Helpers ===

  defp config do
    Application.get_env(:mobile_car_wash, :zoho_books, [])
  end

  defp api_url, do: config()[:api_url] || "https://www.zohoapis.com/books/v3"
  defp org_id, do: config()[:organization_id]

  defp api_get(path, params \\ []) do
    with {:ok, token} <- get_access_token() do
      url = "#{api_url()}#{path}"
      params = Keyword.put(params, :organization_id, org_id())

      case Req.get(url, params: params, headers: auth_headers(token)) do
        {:ok, %{status: 200, body: body}} -> {:ok, body}
        {:ok, %{body: body}} -> {:error, body}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp api_post(path, body) do
    with {:ok, token} <- get_access_token() do
      url = "#{api_url()}#{path}?organization_id=#{org_id()}"

      case Req.post(url, form: body, headers: auth_headers(token)) do
        {:ok, %{status: status, body: body}} when status in [200, 201] -> {:ok, body}
        {:ok, %{body: body}} -> {:error, body}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp auth_headers(token) do
    [{"authorization", "Zoho-oauthtoken #{token}"}]
  end
end
