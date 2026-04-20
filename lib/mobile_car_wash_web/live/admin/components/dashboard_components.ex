defmodule MobileCarWashWeb.Admin.DashboardComponents do
  @moduledoc """
  Function components for the admin metrics dashboard.
  DaisyUI-based cards, charts, and signal indicators.
  """
  use Phoenix.Component

  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :subtitle, :string, default: nil
  attr :color, :string, default: "primary"

  def kpi_card(assigns) do
    ~H"""
    <div class="stat bg-base-100 shadow rounded-box">
      <div class="stat-title">{@label}</div>
      <div class={"stat-value text-#{@color}"}>{@value}</div>
      <div :if={@subtitle} class="stat-desc">{@subtitle}</div>
    </div>
    """
  end

  attr :steps, :list, required: true

  def funnel_chart(assigns) do
    max_count = Enum.max_by(assigns.steps, & &1.count, fn -> %{count: 1} end).count
    max_count = max(max_count, 1)
    assigns = assign(assigns, max_count: max_count)

    ~H"""
    <div class="space-y-3">
      <div :for={step <- @steps} class="flex items-center gap-4">
        <div class="w-40 text-sm font-medium text-right">{step.name}</div>
        <div class="flex-1">
          <div class="flex items-center gap-2">
            <div
              class="bg-primary h-8 rounded-r-lg transition-all duration-500 flex items-center justify-end pr-2"
              style={"width: #{max(step.count / @max_count * 100, 2)}%"}
            >
              <span class="text-primary-content text-xs font-bold">
                {step.count}
              </span>
            </div>
            <span class="text-xs text-base-content/70">
              {step.rate}%
            </span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :signals, :list, required: true

  def pivot_signals(assigns) do
    ~H"""
    <div class="space-y-3">
      <div
        :for={signal <- @signals}
        class="flex items-center gap-4 p-3 bg-base-100 rounded-lg shadow-sm"
      >
        <div class={[
          "badge badge-lg",
          status_badge_class(signal.status)
        ]}>
          {status_icon(signal.status)}
        </div>
        <div class="flex-1">
          <div class="font-semibold">{signal.name}</div>
          <div class="text-sm text-base-content/80">
            Current: <span class="font-mono">{signal.metric}{signal.unit}</span>
            · Threshold: {signal.threshold}{signal.unit}
          </div>
        </div>
        <div :if={signal.status == :red} class="text-sm text-error font-medium">
          {signal.action}
        </div>
      </div>
    </div>
    """
  end

  attr :events, :list, required: true

  def event_feed(assigns) do
    ~H"""
    <div class="overflow-x-auto">
      <table class="table table-sm">
        <thead>
          <tr>
            <th>Time</th>
            <th>Event</th>
            <th>Session</th>
            <th>Properties</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={event <- @events} class="hover">
            <td class="text-xs font-mono whitespace-nowrap">
              {format_time(event.inserted_at)}
            </td>
            <td>
              <span class={["badge badge-sm", event_badge_class(event.event_name)]}>
                {event.event_name}
              </span>
            </td>
            <td class="text-xs font-mono text-base-content/70">
              {String.slice(event.session_id || "", 0..12)}
            </td>
            <td class="text-xs max-w-xs truncate">
              {format_properties(event.properties)}
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  attr :data, :list, required: true
  attr :period, :atom, required: true

  def revenue_chart(assigns) do
    max_cents =
      Enum.max_by(assigns.data, & &1.total_cents, fn -> %{total_cents: 100} end).total_cents

    max_cents = max(max_cents, 100)
    assigns = assign(assigns, max_cents: max_cents)

    ~H"""
    <div :if={@data == []} class="text-center py-8 text-base-content/70">
      No revenue data for this period
    </div>
    <div :if={@data != []} class="flex items-end gap-1 h-40">
      <div :for={day <- @data} class="flex-1 flex flex-col items-center gap-1">
        <div
          class="w-full bg-success rounded-t transition-all duration-500"
          style={"height: #{max(day.total_cents / @max_cents * 100, 2)}%"}
          title={"$#{div(day.total_cents, 100)} (#{day.count} payments)"}
        >
        </div>
        <span class="text-[10px] text-base-content/70 -rotate-45">
          {format_chart_date(day.date)}
        </span>
      </div>
    </div>
    """
  end

  # --- Helpers ---

  defp status_badge_class(:green), do: "badge-success"
  defp status_badge_class(:yellow), do: "badge-warning"
  defp status_badge_class(:red), do: "badge-error"

  defp status_icon(:green), do: "✓"
  defp status_icon(:yellow), do: "!"
  defp status_icon(:red), do: "✕"

  defp event_badge_class("page." <> _), do: "badge-ghost"
  defp event_badge_class("booking." <> _), do: "badge-primary"
  defp event_badge_class("payment." <> _), do: "badge-success"
  defp event_badge_class("signup." <> _), do: "badge-info"
  defp event_badge_class(_), do: "badge-ghost"

  defp format_time(%NaiveDateTime{} = dt) do
    Calendar.strftime(dt, "%H:%M:%S")
  end

  defp format_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%H:%M:%S")
  end

  defp format_time(_), do: "-"

  defp format_properties(nil), do: "-"
  defp format_properties(props) when map_size(props) == 0, do: "-"

  defp format_properties(props) do
    props
    |> Enum.take(3)
    |> Enum.map(fn {k, v} -> "#{k}=#{v}" end)
    |> Enum.join(", ")
  end

  defp format_chart_date(%Date{} = d), do: Calendar.strftime(d, "%m/%d")
  defp format_chart_date(_), do: ""
end
