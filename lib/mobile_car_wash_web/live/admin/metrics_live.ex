defmodule MobileCarWashWeb.Admin.MetricsLive do
  @moduledoc """
  Owner metrics dashboard — the validated learning command center.
  Shows KPIs, AARRR funnel, pivot signals, and revenue at a glance.
  Auto-refreshes every 60 seconds.
  """
  use MobileCarWashWeb, :live_view

  import MobileCarWashWeb.Admin.DashboardComponents

  alias MobileCarWash.Analytics.Metrics

  @refresh_interval :timer.seconds(60)

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: schedule_refresh()

    socket =
      socket
      |> assign(page_title: "Metrics Dashboard", period: :last_7_days)
      |> load_all_metrics()

    {:ok, socket}
  end

  @impl true
  def handle_event("change_period", %{"period" => period_str}, socket) do
    period = String.to_existing_atom(period_str)

    socket =
      socket
      |> assign(period: period)
      |> load_all_metrics()

    {:noreply, socket}
  end

  @impl true
  def handle_info(:refresh, socket) do
    schedule_refresh()
    {:noreply, load_all_metrics(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto py-8 px-4">
      <!-- Header -->
      <div class="flex justify-between items-center mb-8">
        <div>
          <h1 class="text-3xl font-bold">Metrics Dashboard</h1>
          <p class="text-base-content/60">Build → Measure → Learn</p>
        </div>
        <div class="flex items-center gap-4">
          <select
            class="select select-bordered select-sm"
            phx-change="change_period"
            name="period"
          >
            <option value="this_week" selected={@period == :this_week}>This Week</option>
            <option value="last_7_days" selected={@period == :last_7_days}>Last 7 Days</option>
            <option value="last_30_days" selected={@period == :last_30_days}>Last 30 Days</option>
          </select>
          <.link navigate={~p"/admin/events"} class="btn btn-outline btn-sm">
            Event Explorer
          </.link>
        </div>
      </div>

      <!-- KPI Cards -->
      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mb-8">
        <.kpi_card
          label="Revenue"
          value={"$#{format_cents(@kpis.revenue.total_cents)}"}
          subtitle={"#{@kpis.revenue.count} payments"}
          color="success"
        />
        <.kpi_card
          label="Active Subscribers"
          value={to_string(@kpis.active_subscribers)}
          subtitle="all time"
          color="primary"
        />
        <.kpi_card
          label="Bookings"
          value={to_string(@kpis.bookings)}
          subtitle={"#{period_label(@period)}"}
          color="info"
        />
        <.kpi_card
          label="Conversion Rate"
          value={"#{@kpis.conversion_rate}%"}
          subtitle="visit → booking"
          color="warning"
        />
      </div>

      <!-- Main Content Grid -->
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-8 mb-8">
        <!-- AARRR Funnel -->
        <div class="card bg-base-100 shadow-xl">
          <div class="card-body">
            <h2 class="card-title">AARRR Funnel</h2>
            <.funnel_chart steps={@funnel.steps} />
          </div>
        </div>

        <!-- Revenue Chart -->
        <div class="card bg-base-100 shadow-xl">
          <div class="card-body">
            <h2 class="card-title">Daily Revenue</h2>
            <.revenue_chart data={@daily_revenue} period={@period} />
          </div>
        </div>
      </div>

      <!-- Booking Stats -->
      <div class="card bg-base-100 shadow-xl mb-8">
        <div class="card-body">
          <h2 class="card-title mb-4">Booking Flow</h2>
          <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
            <div class="stat bg-base-200 rounded-box p-4">
              <div class="stat-title text-sm">Started</div>
              <div class="stat-value text-lg">{@booking_stats.started}</div>
            </div>
            <div class="stat bg-base-200 rounded-box p-4">
              <div class="stat-title text-sm">Completed</div>
              <div class="stat-value text-lg text-success">{@booking_stats.completed}</div>
            </div>
            <div class="stat bg-base-200 rounded-box p-4">
              <div class="stat-title text-sm">Abandoned</div>
              <div class="stat-value text-lg text-error">{@booking_stats.abandoned}</div>
            </div>
            <div class="stat bg-base-200 rounded-box p-4">
              <div class="stat-title text-sm">Abandonment Rate</div>
              <div class="stat-value text-lg">{@booking_stats.abandonment_rate}%</div>
            </div>
          </div>

          <div :if={@booking_stats.by_step != []} class="mt-4">
            <h3 class="font-semibold mb-2">Completions by Step</h3>
            <div class="flex flex-wrap gap-2">
              <div :for={step <- @booking_stats.by_step} class="badge badge-outline">
                {step.step}: {step.count}
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Pivot Signals -->
      <div class="card bg-base-100 shadow-xl mb-8">
        <div class="card-body">
          <h2 class="card-title mb-4">Pivot Signals</h2>
          <p class="text-sm text-base-content/60 mb-4">
            Red = needs attention now. Yellow = watch closely. Green = on track.
          </p>
          <.pivot_signals signals={@signals} />
        </div>
      </div>

      <!-- Recent Events -->
      <div class="card bg-base-100 shadow-xl">
        <div class="card-body">
          <div class="flex justify-between items-center mb-4">
            <h2 class="card-title">Recent Events</h2>
            <.link navigate={~p"/admin/events"} class="btn btn-ghost btn-sm">
              View All →
            </.link>
          </div>
          <.event_feed events={@recent_events} />
        </div>
      </div>
    </div>
    """
  end

  # --- Private ---

  defp load_all_metrics(socket) do
    period = socket.assigns.period

    assign(socket,
      kpis: Metrics.kpis(period),
      funnel: Metrics.funnel(period),
      daily_revenue: Metrics.daily_revenue(period),
      booking_stats: Metrics.booking_stats(period),
      signals: Metrics.pivot_signals(),
      recent_events: Metrics.recent_events(10)
    )
  end

  defp schedule_refresh do
    Process.send_after(self(), :refresh, @refresh_interval)
  end

  defp format_cents(%Decimal{} = d), do: d |> Decimal.to_integer() |> div(100) |> to_string()
  defp format_cents(n) when is_integer(n), do: to_string(div(n, 100))
  defp format_cents(_), do: "0"

  defp period_label(:this_week), do: "this week"
  defp period_label(:last_7_days), do: "last 7 days"
  defp period_label(:last_30_days), do: "last 30 days"
end
