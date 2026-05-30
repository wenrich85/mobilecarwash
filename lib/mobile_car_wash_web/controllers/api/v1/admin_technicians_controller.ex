defmodule MobileCarWashWeb.Api.V1.AdminTechniciansController do
  @moduledoc """
  Admin technician rows for native command center clients.
  """
  use MobileCarWashWeb, :controller

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Operations.Technician

  require Ash.Query

  plug MobileCarWashWeb.Plugs.RequireApiAuth
  plug :require_admin
  action_fallback MobileCarWashWeb.Api.V1.FallbackController

  def index(conn, _params) do
    technicians =
      Technician
      |> Ash.Query.sort([{:active, :desc}, :name])
      |> Ash.read!(authorize?: false)

    accounts = load_accounts(technicians)

    json(conn, %{data: Enum.map(technicians, &technician_json(&1, accounts))})
  end

  defp require_admin(conn, _opts) do
    case current_user(conn) do
      %{role: :admin} ->
        conn

      _ ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "forbidden", message: "Admin role required"})
        |> halt()
    end
  end

  defp load_accounts(technicians) do
    ids =
      technicians
      |> Enum.map(& &1.user_account_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    Customer
    |> Ash.Query.filter(id in ^ids)
    |> Ash.read!(authorize?: false)
    |> Map.new(&{&1.id, &1})
  end

  defp technician_json(technician, accounts) do
    account = Map.get(accounts, technician.user_account_id)

    %{
      id: technician.id,
      name: technician.name,
      email: account && to_string(account.email),
      phone: technician.phone,
      active: technician.active,
      status: to_string(technician.status),
      zone: technician.zone && to_string(technician.zone),
      pay_rate_cents: technician.pay_rate_cents,
      pay_rate_pct: decimal_to_string(technician.pay_rate_pct)
    }
  end

  defp decimal_to_string(nil), do: nil
  defp decimal_to_string(%Decimal{} = decimal), do: Decimal.to_string(decimal, :normal)

  defp current_user(conn), do: conn.assigns[:current_user] || conn.assigns[:current_customer]
end
