defmodule MobileCarWashWeb.Admin.MarketingLive do
  @moduledoc """
  Marketing Phase 1 / Slice 5: the CAC + spend dashboard.

  One page:
    * Blended KPI tiles (spend, new customers, blended CAC, revenue)
    * Per-channel table (every active channel, even zero-activity)
    * Log-spend form (channel dropdown + date + dollars + notes)
    * Period selector (last 7 / 30 / 90 / this month)
  """
  use MobileCarWashWeb, :live_view

  alias MobileCarWash.Marketing
  alias MobileCarWash.Marketing.{AcquisitionChannel, CAC, MarketingSpend}

  @periods [last_7: "Last 7 Days", last_30: "Last 30 Days", last_90: "Last 90 Days", mtd: "Month to Date"]

  @impl true
  def mount(_params, _session, socket) do
    channels =
      AcquisitionChannel
      |> Ash.Query.for_read(:active)
      |> Ash.read!(authorize?: false)

    socket =
      socket
      |> assign(page_title: "Marketing")
      |> assign(channels: channels)
      |> assign(period: :last_30)
      |> assign(spend_error: nil)
      |> load_rollups()

    {:ok, socket}
  end

  @impl true
  def handle_event("change_period", %{"period" => period_str}, socket) do
    period = String.to_existing_atom(period_str)
    {:noreply, socket |> assign(period: period) |> load_rollups()}
  end

  def handle_event("log_spend", %{"spend" => params}, socket) do
    with {:ok, cents} <- parse_dollars(params["amount_dollars"]),
         {:ok, date} <- parse_date(params["spent_on"]),
         attrs = %{
           channel_id: params["channel_id"],
           spent_on: date,
           amount_cents: cents,
           notes: params["notes"]
         },
         {:ok, _row} <-
           MarketingSpend
           |> Ash.Changeset.for_create(:record, attrs)
           |> Ash.create(authorize?: false) do
      {:noreply, socket |> assign(spend_error: nil) |> load_rollups()}
    else
      {:error, :bad_amount} ->
        {:noreply, assign(socket, spend_error: "Amount must be a non-negative number")}

      {:error, :bad_date} ->
        {:noreply, assign(socket, spend_error: "Invalid date")}

      {:error, %Ash.Error.Invalid{} = e} ->
        {:noreply, assign(socket, spend_error: Exception.message(e))}

      _ ->
        {:noreply, assign(socket, spend_error: "Could not record spend")}
    end
  end

  # --- Private ---

  defp load_rollups(socket) do
    {from, to} = period_range(socket.assigns.period)
    rows = CAC.per_channel(from, to)
    summary = CAC.summary(from, to)

    socket
    |> assign(rows: rows, summary: summary, from: from, to: to)
  end

  defp period_range(period) do
    today = Date.utc_today()

    case period do
      :last_7 -> {Date.add(today, -6), today}
      :last_30 -> {Date.add(today, -29), today}
      :last_90 -> {Date.add(today, -89), today}
      :mtd -> {Date.beginning_of_month(today), today}
    end
  end

  defp parse_dollars(nil), do: {:error, :bad_amount}
  defp parse_dollars(""), do: {:error, :bad_amount}

  defp parse_dollars(str) when is_binary(str) do
    case Float.parse(String.trim(str)) do
      {f, ""} when f >= 0 -> {:ok, round(f * 100)}
      _ -> {:error, :bad_amount}
    end
  end

  defp parse_date(nil), do: {:error, :bad_date}

  defp parse_date(str) when is_binary(str) do
    case Date.from_iso8601(str) do
      {:ok, d} -> {:ok, d}
      _ -> {:error, :bad_date}
    end
  end

  defp fmt_cents(nil), do: "—"
  defp fmt_cents(0), do: "$0"
  defp fmt_cents(cents) when is_integer(cents), do: "$#{:erlang.float_to_binary(cents / 100, decimals: 2)}"

  defp fmt_pct(nil), do: "—"
  defp fmt_pct(n), do: "#{n}%"

  @impl true
  def render(assigns) do
    assigns = assign(assigns, periods: @periods)

    ~H"""
    <div class="max-w-7xl mx-auto py-8 px-4">
      <div class="flex justify-between items-center mb-8">
        <div>
          <h1 class="text-3xl font-bold">Marketing</h1>
          <p class="text-base-content/80">CAC and revenue by acquisition channel.</p>
        </div>

        <select
          id="period-select"
          phx-change="change_period"
          name="period"
          class="select select-bordered select-sm"
        >
          <option :for={{key, label} <- @periods} value={key} selected={@period == key}>
            {label}
          </option>
        </select>
      </div>

      <!-- KPI tiles -->
      <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 mb-8">
        <div class="stat bg-base-200 rounded-lg">
          <div class="stat-title">Total Spend</div>
          <div class="stat-value text-primary">{fmt_cents(@summary.total_spend_cents)}</div>
        </div>
        <div class="stat bg-base-200 rounded-lg">
          <div class="stat-title">New Customers</div>
          <div class="stat-value">{@summary.new_customers}</div>
        </div>
        <div class="stat bg-base-200 rounded-lg">
          <div class="stat-title">Blended CAC</div>
          <div class="stat-value text-secondary">{fmt_cents(@summary.blended_cac_cents)}</div>
        </div>
        <div class="stat bg-base-200 rounded-lg">
          <div class="stat-title">Revenue (from new)</div>
          <div class="stat-value text-success">{fmt_cents(@summary.total_revenue_cents)}</div>
        </div>
      </div>

      <!-- Per-channel table -->
      <div class="overflow-x-auto mb-8 bg-base-100 rounded-lg border border-base-300">
        <table class="table">
          <thead>
            <tr>
              <th>Channel</th>
              <th>Category</th>
              <th class="text-right">Spend</th>
              <th class="text-right">New Customers</th>
              <th class="text-right">CAC</th>
              <th class="text-right">Revenue</th>
              <th class="text-right">Avg Rev / Cust</th>
              <th class="text-right">ROI</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={row <- @rows} class="hover">
              <td class="font-medium">{row.channel_name}</td>
              <td>
                <span class={"badge badge-sm " <> category_class(row.category)}>
                  {row.category}
                </span>
              </td>
              <td class="text-right">{fmt_cents(row.spend_cents)}</td>
              <td class="text-right">{row.new_customers}</td>
              <td class="text-right">{fmt_cents(row.cac_cents)}</td>
              <td class="text-right">{fmt_cents(row.revenue_cents)}</td>
              <td class="text-right">{fmt_cents(row.avg_revenue_cents)}</td>
              <td class="text-right">{fmt_pct(row.roi_pct)}</td>
            </tr>
          </tbody>
        </table>
      </div>

      <!-- Log spend form -->
      <div class="card bg-base-200">
        <div class="card-body">
          <h2 class="card-title">Log Spend</h2>
          <p class="text-sm text-base-content/70">Record ad spend per channel per day. Sums appear in the table above immediately.</p>

          <form id="log-spend" phx-submit="log_spend" class="grid grid-cols-1 md:grid-cols-4 gap-4 mt-4">
            <label class="form-control">
              <span class="label-text">Channel</span>
              <select name="spend[channel_id]" class="select select-bordered" required>
                <option :for={chan <- @channels} value={chan.id}>{chan.display_name}</option>
              </select>
            </label>

            <label class="form-control">
              <span class="label-text">Date</span>
              <input type="date" name="spend[spent_on]" class="input input-bordered" required />
            </label>

            <label class="form-control">
              <span class="label-text">Amount (USD)</span>
              <input
                type="number"
                step="0.01"
                min="0"
                name="spend[amount_dollars]"
                class="input input-bordered"
                required
              />
            </label>

            <label class="form-control">
              <span class="label-text">Notes</span>
              <input type="text" name="spend[notes]" class="input input-bordered" placeholder="Campaign note" />
            </label>

            <div :if={@spend_error} class="md:col-span-4 alert alert-error">
              <span>{@spend_error}</span>
            </div>

            <div class="md:col-span-4 flex justify-end">
              <button type="submit" class="btn btn-primary">Save spend</button>
            </div>
          </form>
        </div>
      </div>
    </div>
    """
  end

  defp category_class(:paid), do: "badge-primary"
  defp category_class(:organic), do: "badge-success"
  defp category_class(:referral), do: "badge-info"
  defp category_class(:offline), do: "badge-warning"
  defp category_class(_), do: "badge-ghost"
end
