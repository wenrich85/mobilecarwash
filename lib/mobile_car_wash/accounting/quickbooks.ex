defmodule MobileCarWash.Accounting.QuickBooks do
  @moduledoc """
  QuickBooks Online accounting integration.
  Implements the AccountingProvider behaviour using QuickBooks REST API v3.

  Handles OAuth2 token refresh automatically.
  """
  @behaviour MobileCarWash.Accounting.Provider

  require Logger

  # === Provider Callbacks ===

  @impl true
  def create_contact(params) do
    body = %{
      "DisplayName" => params.name,
      "PrimaryEmailAddr" => %{"Address" => params.email},
      "PrimaryPhone" => %{"FreeFormNumber" => params[:phone] || ""}
    }

    case api_post("/customer", body) do
      {:ok, %{"Customer" => customer}} -> {:ok, customer}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def find_contact_by_email(email) do
    query = "SELECT * FROM Customer WHERE PrimaryEmailAddr = '#{sanitize(email)}'"

    case api_get("/query", query: query) do
      {:ok, %{"QueryResponse" => %{"Customer" => [customer | _]}}} -> {:ok, customer}
      {:ok, %{"QueryResponse" => %{"Customer" => []}}} -> {:error, :not_found}
      {:ok, %{"QueryResponse" => %{}}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def create_invoice(params) do
    contact_id = params[:contact_id]

    line_items =
      Enum.with_index(params.line_items, 1)
      |> Enum.map(fn {item, idx} ->
        %{
          "LineNum" => idx,
          "Amount" => item.amount_cents / 100,
          "DetailType" => "SalesItemLineDetail",
          "Description" => item.name,
          "SalesItemLineDetail" => %{
            "Qty" => item[:quantity] || 1,
            "UnitPrice" => item.amount_cents / 100
          }
        }
      end)

    body = %{
      "CustomerRef" => %{"value" => contact_id},
      "Line" => line_items,
      "CustomerMemo" => %{"value" => params[:notes] || "Driveway Detail Co — Thank you for your business!"},
      "DocNumber" => params[:payment_id]
    }

    case api_post("/invoice", body) do
      {:ok, %{"Invoice" => invoice}} -> {:ok, invoice}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def record_payment(invoice_id, params) do
    body = %{
      "TotalAmt" => params.amount_cents / 100,
      "TxnDate" => Date.to_iso8601(params.payment_date),
      "Line" => [
        %{
          "Amount" => params.amount_cents / 100,
          "LinkedTxn" => [
            %{"TxnId" => invoice_id, "TxnType" => "Invoice"}
          ]
        }
      ],
      "CustomerRef" => %{"value" => ""},
      "PaymentMethodRef" => %{"value" => ""},
      "PrivateNote" => params[:reference] || ""
    }

    case api_post("/payment", body) do
      {:ok, %{"Payment" => payment}} -> {:ok, payment}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def get_invoice(invoice_id) do
    case api_get("/invoice/#{invoice_id}") do
      {:ok, %{"Invoice" => invoice}} -> {:ok, invoice}
      {:error, reason} -> {:error, reason}
    end
  end

  # === OAuth2 Token Management ===

  defp get_access_token do
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
    config = config()
    client_id = config[:client_id]
    client_secret = config[:client_secret]
    refresh_token = config[:refresh_token]

    if is_nil(client_id) or is_nil(refresh_token) do
      {:error, :quickbooks_not_configured}
    else
      url = "https://oauth.platform.intuit.com/oauth2/v1/tokens/bearer"

      credentials = Base.encode64("#{client_id}:#{client_secret}")

      body =
        URI.encode_query(%{
          "grant_type" => "refresh_token",
          "refresh_token" => refresh_token
        })

      headers = [
        {"content-type", "application/x-www-form-urlencoded"},
        {"authorization", "Basic #{credentials}"},
        {"accept", "application/json"}
      ]

      case Req.post(url, body: body, headers: headers) do
        {:ok, %{status: 200, body: %{"access_token" => token} = resp}} ->
          # QuickBooks also returns a new refresh_token — log for rotation
          if new_refresh = resp["refresh_token"] do
            Logger.info("QuickBooks issued new refresh token — update QUICKBOOKS_REFRESH_TOKEN")
            Logger.debug("New QB refresh token: #{String.slice(new_refresh, 0, 8)}...")
          end

          expires_in = resp["expires_in"] || 3600
          expires_at = DateTime.add(DateTime.utc_now(), expires_in - 60, :second)
          :persistent_term.put({__MODULE__, :access_token}, {token, expires_at})
          {:ok, token}

        {:ok, resp} ->
          Logger.error("QuickBooks token refresh failed: #{inspect(resp.body)}")
          {:error, :token_refresh_failed}

        {:error, reason} ->
          Logger.error("QuickBooks token refresh error: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  # === HTTP Helpers ===

  defp config do
    Application.get_env(:mobile_car_wash, :quickbooks, [])
  end

  defp api_url do
    base = config()[:api_url] || "https://quickbooks.api.intuit.com"
    company_id = config()[:company_id]
    "#{base}/v3/company/#{company_id}"
  end

  defp api_get(path, params \\ []) do
    with {:ok, token} <- get_access_token() do
      url = "#{api_url()}#{path}"

      case Req.get(url, params: params, headers: auth_headers(token)) do
        {:ok, %{status: 200, body: body}} -> {:ok, body}
        {:ok, %{body: body}} -> {:error, body}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp api_post(path, body) do
    with {:ok, token} <- get_access_token() do
      url = "#{api_url()}#{path}"

      case Req.post(url, json: body, headers: auth_headers(token)) do
        {:ok, %{status: status, body: body}} when status in [200, 201] -> {:ok, body}
        {:ok, %{body: body}} -> {:error, body}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp auth_headers(token) do
    [
      {"authorization", "Bearer #{token}"},
      {"accept", "application/json"}
    ]
  end

  defp sanitize(str) do
    String.replace(str, "'", "\\'")
  end
end
