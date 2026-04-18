defmodule MobileCarWashWeb.Admin.EventsLive do
  @moduledoc """
  Event explorer — paginated view of all analytics events.
  Filter by event name for debugging and understanding user behavior.
  """
  use MobileCarWashWeb, :live_view

  import MobileCarWashWeb.Admin.DashboardComponents

  alias MobileCarWash.Analytics.Metrics

  @page_size 50

  @impl true
  def mount(_params, _session, socket) do
    event_names = Metrics.event_names()
    total = Metrics.event_total()

    socket =
      socket
      |> assign(
        page_title: "Event Explorer",
        events: Metrics.recent_events(@page_size, 0),
        event_names: event_names,
        selected_event: nil,
        page: 0,
        total: total,
        page_size: @page_size
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("filter_event", %{"event_name" => ""}, socket) do
    events = Metrics.recent_events(@page_size, 0)
    total = Metrics.event_total()

    {:noreply, assign(socket, events: events, selected_event: nil, page: 0, total: total)}
  end

  def handle_event("filter_event", %{"event_name" => name}, socket) do
    events = Metrics.events_by_name(name, @page_size, 0)

    {:noreply, assign(socket, events: events, selected_event: name, page: 0)}
  end

  def handle_event("next_page", _params, socket) do
    page = socket.assigns.page + 1
    offset = page * @page_size

    events =
      if socket.assigns.selected_event do
        Metrics.events_by_name(socket.assigns.selected_event, @page_size, offset)
      else
        Metrics.recent_events(@page_size, offset)
      end

    {:noreply, assign(socket, events: events, page: page)}
  end

  def handle_event("prev_page", _params, socket) do
    page = max(socket.assigns.page - 1, 0)
    offset = page * @page_size

    events =
      if socket.assigns.selected_event do
        Metrics.events_by_name(socket.assigns.selected_event, @page_size, offset)
      else
        Metrics.recent_events(@page_size, offset)
      end

    {:noreply, assign(socket, events: events, page: page)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto py-8 px-4">
      <div class="flex justify-between items-center mb-8">
        <div>
          <h1 class="text-3xl font-bold">Event Explorer</h1>
          <p class="text-base-content/80">{@total} total events</p>
        </div>
        <.link navigate={~p"/admin/metrics"} class="btn btn-outline btn-sm">
          ← Dashboard
        </.link>
      </div>

      <!-- Filters -->
      <div class="flex gap-4 mb-6">
        <select
          class="select select-bordered"
          phx-change="filter_event"
          name="event_name"
        >
          <option value="">All Events</option>
          <option
            :for={name <- @event_names}
            value={name}
            selected={@selected_event == name}
          >
            {name}
          </option>
        </select>

        <div :if={@selected_event} class="badge badge-primary badge-lg self-center">
          Filtering: {@selected_event}
        </div>
      </div>

      <!-- Events Table -->
      <div class="card bg-base-100 shadow-xl">
        <div class="card-body p-0">
          <.event_feed events={@events} />
        </div>
      </div>

      <!-- Pagination -->
      <div class="flex justify-between items-center mt-4">
        <button
          class="btn btn-outline btn-sm"
          phx-click="prev_page"
          disabled={@page == 0}
        >
          ← Previous
        </button>
        <span class="text-sm text-base-content/80">
          Page {@page + 1}
        </span>
        <button
          class="btn btn-outline btn-sm"
          phx-click="next_page"
          disabled={length(@events) < @page_size}
        >
          Next →
        </button>
      </div>
    </div>
    """
  end
end
