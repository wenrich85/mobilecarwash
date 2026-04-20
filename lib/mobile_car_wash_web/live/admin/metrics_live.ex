defmodule MobileCarWashWeb.Admin.MetricsLive do
  @moduledoc """
  Owner metrics dashboard — the validated learning command center.
  Shows KPIs, AARRR funnel, pivot signals, and revenue at a glance.
  Auto-refreshes every 60 seconds.
  """
  use MobileCarWashWeb, :live_view

  import MobileCarWashWeb.Admin.DashboardComponents

  alias MobileCarWash.Analytics.Metrics
  alias MobileCarWashWeb.Presence

  @refresh_interval :timer.seconds(60)

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      schedule_refresh()
      Phoenix.PubSub.subscribe(MobileCarWash.PubSub, Presence.topic())
    end

    socket =
      socket
      |> assign(page_title: "Metrics Dashboard", period: :last_7_days)
      |> assign(online_users: Presence.list_users())
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

  # Phoenix.Presence broadcasts presence_diff as a %Phoenix.Socket.Broadcast{} struct
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    {:noreply, assign(socket, online_users: Presence.list_users())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto py-8 px-4">
      <!-- Header -->
      <div class="flex justify-between items-center mb-8">
        <div>
          <h1 class="text-3xl font-bold">Metrics Dashboard</h1>
          <p class="text-base-content/80">Build → Measure → Learn</p>
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
      
    <!-- Who's Online -->
      <div class="mb-8">
        <div class="flex items-center gap-2 mb-3">
          <span class="w-2 h-2 rounded-full bg-success inline-block animate-pulse"></span>
          <h2 class="font-semibold text-sm text-base-content/70 uppercase tracking-wide">
            Online Now
          </h2>
          <span class="badge badge-sm badge-ghost">{length(@online_users)}</span>
        </div>

        <div :if={@online_users == []} class="text-sm text-base-content/70 italic">
          No one else is online
        </div>

        <div class="flex flex-wrap gap-2">
          <div
            :for={user <- @online_users}
            class="flex items-center gap-2 bg-base-100 shadow-sm rounded-full px-3 py-1.5 border border-base-200"
          >
            <!-- Role dot -->
            <span class={["w-2 h-2 rounded-full flex-shrink-0", presence_dot_class(user.role)]}>
            </span>
            
    <!-- Name + page -->
            <div class="min-w-0">
              <span class="text-sm font-medium">{user.name}</span>
              <span class="text-xs text-base-content/70 ml-1">· {user.page}</span>
            </div>
            
    <!-- Role badge -->
            <span class={["badge badge-xs flex-shrink-0", presence_role_badge(user.role)]}>
              {format_role(user.role)}
            </span>
            
    <!-- Time online -->
            <span class="text-xs text-base-content/70 flex-shrink-0 font-mono">
              {format_duration(System.system_time(:second) - user.online_at)}
            </span>
          </div>
        </div>
      </div>
      
    <!-- KPI Cards -->
      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mb-8">
        <div class="stat bg-base-100 shadow rounded-box">
          <div class="stat-title">Revenue</div>
          <div class="stat-value text-success">${format_cents(@kpis.revenue.total_cents)}</div>
          <div class="stat-desc">{@kpis.revenue.count} payments</div>
          <div
            :if={@period_comparison}
            class={[
              "flex items-center gap-1 text-sm font-semibold mt-2",
              @period_comparison.delta_pct >= 0 && "text-success",
              @period_comparison.delta_pct < 0 && "text-error"
            ]}
          >
            <span>{if @period_comparison.delta_pct >= 0, do: "▲", else: "▼"}</span>
            <span>{@period_comparison.delta_pct}%</span>
          </div>
        </div>
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
      
    <!-- Technician Performance -->
      <div :if={@technician_performance != []} class="card bg-base-100 shadow-xl mb-8">
        <div class="card-body">
          <h2 class="card-title mb-4">Technician Performance</h2>
          <div class="overflow-x-auto">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>Technician</th>
                  <th>Washes</th>
                  <th>Revenue</th>
                  <th>Avg Time</th>
                  <th>vs Estimated</th>
                  <th>Efficiency</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={tech <- @technician_performance}>
                  <td class="font-semibold">{tech.technician_name}</td>
                  <td>{tech.washes_count}</td>
                  <td>${format_cents(tech.total_revenue_cents)}</td>
                  <td>{trunc(tech.avg_actual_minutes || 0)} min</td>
                  <td>
                    <span class={[
                      tech.avg_estimated_minutes && tech.avg_estimated_minutes > 0 &&
                        "text-sm",
                      (tech.avg_estimated_minutes && tech.avg_estimated_minutes > 0 &&
                         (tech.avg_actual_minutes > tech.avg_estimated_minutes && "text-error")) ||
                        (tech.avg_actual_minutes <= tech.avg_estimated_minutes && "text-success")
                    ]}>
                      {if tech.avg_estimated_minutes && tech.avg_estimated_minutes > 0 do
                        "#{trunc(tech.avg_estimated_minutes)} min"
                      else
                        "—"
                      end}
                    </span>
                  </td>
                  <td>
                    <div class="flex items-center gap-2">
                      <span class={[
                        "font-semibold",
                        tech.efficiency_pct >= 90 && "text-success",
                        tech.efficiency_pct >= 75 && tech.efficiency_pct < 90 && "text-warning",
                        tech.efficiency_pct < 75 && "text-error"
                      ]}>
                        {tech.efficiency_pct}%
                      </span>
                    </div>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>
      
    <!-- Pivot Signals -->
      <div class="card bg-base-100 shadow-xl mb-8">
        <div class="card-body">
          <h2 class="card-title mb-4">Pivot Signals</h2>
          <p class="text-sm text-base-content/80 mb-4">
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
      period_comparison: Metrics.compare_revenue(period),
      funnel: Metrics.funnel(period),
      daily_revenue: Metrics.daily_revenue(period),
      booking_stats: Metrics.booking_stats(period),
      technician_performance: Metrics.technician_performance(period),
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

  # --- Presence helpers ---

  defp presence_dot_class(:admin), do: "bg-error"
  defp presence_dot_class(:technician), do: "bg-warning"
  defp presence_dot_class(_), do: "bg-success"

  defp presence_role_badge(:admin), do: "badge-error"
  defp presence_role_badge(:technician), do: "badge-warning"
  defp presence_role_badge(_), do: "badge-ghost"

  defp format_role(:admin), do: "Admin"
  defp format_role(:technician), do: "Tech"
  defp format_role(_), do: "Customer"

  defp format_duration(secs) when secs < 60, do: "#{secs}s"
  defp format_duration(secs) when secs < 3600, do: "#{div(secs, 60)}m"
  defp format_duration(secs), do: "#{div(secs, 3600)}h"
end
