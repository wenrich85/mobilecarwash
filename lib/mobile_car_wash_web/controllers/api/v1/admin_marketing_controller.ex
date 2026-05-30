defmodule MobileCarWashWeb.Api.V1.AdminMarketingController do
  @moduledoc """
  Admin marketing rollups for native command center clients.
  """
  use MobileCarWashWeb, :controller

  alias MobileCarWash.Marketing.{CAC, Referrals}

  plug MobileCarWashWeb.Plugs.RequireApiAuth
  plug :require_admin
  action_fallback MobileCarWashWeb.Api.V1.FallbackController

  def show(conn, params) do
    period = period(params["period"])
    {from, to} = period_range(period)

    data = %{
      period: Atom.to_string(period),
      from: Date.to_iso8601(from),
      to: Date.to_iso8601(to),
      summary: CAC.summary(from, to),
      channels: Enum.map(CAC.per_channel(from, to), &channel_json/1),
      leaderboard: Referrals.leaderboard(10)
    }

    json(conn, %{data: data})
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

  defp period("last_7"), do: :last_7
  defp period("last_90"), do: :last_90
  defp period("mtd"), do: :mtd
  defp period(_), do: :last_30

  defp period_range(:last_7), do: days_back(7)
  defp period_range(:last_30), do: days_back(30)
  defp period_range(:last_90), do: days_back(90)

  defp period_range(:mtd) do
    today = Date.utc_today()
    {Date.beginning_of_month(today), today}
  end

  defp days_back(days) do
    today = Date.utc_today()
    {Date.add(today, -days + 1), today}
  end

  defp channel_json(row) do
    %{
      channel_id: row.channel_id,
      channel_slug: row.channel_slug,
      channel_name: row.channel_name,
      category: to_string(row.category),
      spend_cents: row.spend_cents,
      new_customers: row.new_customers,
      cac_cents: row.cac_cents,
      revenue_cents: row.revenue_cents,
      avg_revenue_cents: row.avg_revenue_cents,
      roi_pct: row.roi_pct
    }
  end

  defp current_user(conn), do: conn.assigns[:current_user] || conn.assigns[:current_customer]
end
