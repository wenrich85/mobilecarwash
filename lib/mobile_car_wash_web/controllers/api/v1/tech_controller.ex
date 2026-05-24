defmodule MobileCarWashWeb.Api.V1.TechController do
  @moduledoc """
  Tech-facing profile endpoints. The signed-in `Customer` with role
  `:technician` or `:admin` maps to a `Technician` record via
  `user_account_id` (falling back to name match for legacy records).
  """
  use MobileCarWashWeb, :controller

  alias MobileCarWash.Operations.{TechEarnings, Technician}

  require Ash.Query

  plug MobileCarWashWeb.Plugs.RequireTechAuth
  action_fallback MobileCarWashWeb.Api.V1.FallbackController

  def me(conn, _params) do
    case find_tech(current_user(conn)) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "no_tech_record"})

      tech ->
        json(conn, %{data: tech_json(tech)})
    end
  end

  def update_status(conn, params) do
    user = current_user(conn)

    with tech when not is_nil(tech) <- find_tech(user),
         status_str when is_binary(status_str) <- params["status"],
         status_atom <- safe_status_atom(status_str),
         {:ok, updated} <-
           tech
           |> Ash.Changeset.for_update(:set_status, %{status: status_atom})
           |> Ash.update() do
      json(conn, %{data: tech_json(updated)})
    else
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "no_tech_record"})

      {:error, _} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "invalid_status"})

      _ ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "invalid_status"})
    end
  end

  def earnings(conn, params) do
    with tech when not is_nil(tech) <- find_tech(current_user(conn)),
         {:ok, period} <- parse_period(params["period"]),
         {:ok, ref_date} <- parse_ref_date(params["ref_date"]) do
      summary = TechEarnings.earnings_for_period(tech, period, ref_date)

      json(conn, %{
        data:
          summary
          |> earnings_json(period, tech)
      })
    else
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "no_tech_record"})

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: to_string(reason)})
    end
  end

  def history(conn, params) do
    case find_tech(current_user(conn)) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "no_tech_record"})

      tech ->
        washes =
          tech.id
          |> TechEarnings.all_completed_washes(parse_limit(params["limit"]))
          |> Enum.map(&wash_json(&1, tech))

        json(conn, %{
          data: %{
            completed_count: length(washes),
            total_earned_cents: Enum.reduce(washes, 0, &(&1.earned_cents + &2)),
            washes: washes
          }
        })
    end
  end

  # ----------------------------------------------------------------

  @valid_statuses ~w(off_duty available on_break)
  defp safe_status_atom(s) when s in @valid_statuses, do: String.to_existing_atom(s)
  defp safe_status_atom(_), do: :__invalid__

  defp parse_period(nil), do: {:ok, :week}
  defp parse_period("day"), do: {:ok, :day}
  defp parse_period("week"), do: {:ok, :week}
  defp parse_period("month"), do: {:ok, :month}
  defp parse_period("year"), do: {:ok, :year}
  defp parse_period(_), do: {:error, :invalid_period}

  defp parse_ref_date(nil), do: {:ok, nil}

  defp parse_ref_date(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      {:error, _} -> {:error, :invalid_ref_date}
    end
  end

  defp parse_limit(nil), do: 50

  defp parse_limit(value) do
    case Integer.parse(value) do
      {limit, ""} -> limit |> max(1) |> min(100)
      _ -> 50
    end
  end

  defp find_tech(user) do
    techs = Ash.read!(Technician)

    Enum.find(techs, fn t -> t.user_account_id == user.id end) ||
      Enum.find(techs, fn t -> t.name == user.name end)
  end

  defp tech_json(tech) do
    %{
      id: tech.id,
      name: tech.name,
      status: to_string(tech.status),
      zone: tech.zone && to_string(tech.zone),
      active: tech.active
    }
  end

  defp earnings_json(summary, period, tech) do
    %{
      period: to_string(period),
      period_start: summary.period_start,
      period_end: summary.period_end,
      washes_count: summary.washes_count,
      total_cents: summary.total_cents,
      rate_cents: summary.rate_cents,
      pay_rate_pct: decimal_string(summary.pay_rate_pct),
      washes: Enum.map(summary.washes, &wash_json(&1, tech))
    }
  end

  defp wash_json(wash, tech) do
    Map.merge(wash, %{
      earned_cents: TechEarnings.wash_earnings(wash, tech)
    })
  end

  defp decimal_string(nil), do: nil
  defp decimal_string(decimal), do: Decimal.to_string(decimal)

  defp current_user(conn), do: conn.assigns[:current_user] || conn.assigns[:current_customer]
end
