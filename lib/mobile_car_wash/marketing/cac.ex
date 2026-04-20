defmodule MobileCarWash.Marketing.CAC do
  @moduledoc """
  Customer Acquisition Cost + lifetime revenue rollups per channel.

  Drives the /admin/marketing dashboard. All amounts are cents.

  "New customers in window" = customers whose acquired_at falls in
  [from, to] and whose acquired_channel_id points at the channel.

  Revenue for a customer = sum of all their succeeded Payments (all
  time, not clipped to the window) — we want LTV-to-date, not
  window-revenue.
  """

  alias MobileCarWash.Marketing
  alias MobileCarWash.Marketing.AcquisitionChannel
  alias MobileCarWash.Repo

  import Ecto.Query

  @doc """
  One row per AcquisitionChannel (including zero-activity channels).

  Each row:
      %{
        channel_id: uuid,
        channel_slug: "meta_paid",
        channel_name: "Meta (Facebook + Instagram)",
        category: :paid,
        spend_cents: integer,
        new_customers: integer,
        cac_cents: integer | nil,
        revenue_cents: integer,
        avg_revenue_cents: integer | nil,
        roi_pct: integer | nil
      }
  """
  @spec per_channel(Date.t(), Date.t()) :: [map()]
  def per_channel(from, to) do
    # Customers.acquired_at is a naive_datetime column. Use
    # NaiveDateTime bounds so Ecto doesn't silently cast DateTime
    # and fail the comparison.
    from_dt = NaiveDateTime.new!(from, ~T[00:00:00])
    to_dt = NaiveDateTime.new!(to, ~T[23:59:59])

    channels =
      AcquisitionChannel
      |> Ash.Query.for_read(:active)
      |> Ash.read!(authorize?: false)

    spend_by_channel = Marketing.spend_cents_by_channel_in_range(from, to)
    customers_by_channel = new_customers_by_channel(from_dt, to_dt)
    revenue_by_customer = revenue_by_customer()

    Enum.map(channels, fn chan ->
      customers = Map.get(customers_by_channel, chan.id, [])
      spend = Map.get(spend_by_channel, chan.id, 0)
      new_customers = length(customers)

      revenue =
        Enum.reduce(customers, 0, fn cid, acc ->
          acc + Map.get(revenue_by_customer, cid, 0)
        end)

      %{
        channel_id: chan.id,
        channel_slug: chan.slug,
        channel_name: chan.display_name,
        category: chan.category,
        spend_cents: spend,
        new_customers: new_customers,
        # CAC is nil for zero-spend channels — "$0 per customer" is
        # misleading for organic/referral/word-of-mouth rows.
        cac_cents: cac_cents(spend, new_customers),
        revenue_cents: revenue,
        avg_revenue_cents: safe_div(revenue, new_customers),
        roi_pct: roi_pct(revenue, spend)
      }
    end)
    |> Enum.sort_by(& &1.spend_cents, :desc)
  end

  @doc """
  Blended KPIs across all channels for the tile row at the top of
  the dashboard.
  """
  @spec summary(Date.t(), Date.t()) :: map()
  def summary(from, to) do
    rows = per_channel(from, to)

    total_spend = Enum.reduce(rows, 0, &(&1.spend_cents + &2))
    total_revenue = Enum.reduce(rows, 0, &(&1.revenue_cents + &2))
    total_new = Enum.reduce(rows, 0, &(&1.new_customers + &2))

    %{
      total_spend_cents: total_spend,
      total_revenue_cents: total_revenue,
      new_customers: total_new,
      blended_cac_cents: cac_cents(total_spend, total_new),
      roi_pct: roi_pct(total_revenue, total_spend)
    }
  end

  # --- Private ---

  defp new_customers_by_channel(from_dt, to_dt) do
    query =
      from c in "customers",
        where: c.acquired_at >= ^from_dt,
        where: c.acquired_at <= ^to_dt,
        where: not is_nil(c.acquired_channel_id),
        select: %{
          channel_id: type(c.acquired_channel_id, Ecto.UUID),
          customer_id: type(c.id, Ecto.UUID)
        }

    query
    |> Repo.all()
    |> Enum.group_by(& &1.channel_id, & &1.customer_id)
  end

  defp revenue_by_customer do
    query =
      from p in "payments",
        where: p.status == "succeeded",
        where: not is_nil(p.customer_id),
        group_by: p.customer_id,
        select: %{
          customer_id: type(p.customer_id, Ecto.UUID),
          total: sum(p.amount_cents)
        }

    query
    |> Repo.all()
    |> Map.new(fn %{customer_id: cid, total: t} -> {cid, to_int(t)} end)
  end

  defp to_int(nil), do: 0
  defp to_int(%Decimal{} = d), do: Decimal.to_integer(d)
  defp to_int(n) when is_integer(n), do: n

  defp safe_div(_num, 0), do: nil
  defp safe_div(num, denom), do: div(num, denom)

  # Distinct from safe_div — CAC is undefined (nil) both when there's
  # no paid spend AND when there are no new customers.
  defp cac_cents(0, _), do: nil
  defp cac_cents(_, 0), do: nil
  defp cac_cents(spend, customers), do: div(spend, customers)

  defp roi_pct(_revenue, 0), do: nil
  defp roi_pct(revenue, spend), do: div((revenue - spend) * 100, spend)
end
