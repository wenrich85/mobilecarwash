defmodule MobileCarWashWeb.TrackPresence do
  @moduledoc """
  LiveView on_mount hook that registers the current user in Phoenix Presence.

  Added as the last hook in each authenticated live_session so that
  `socket.assigns.current_customer` is already set by the auth hook before
  this runs.

  Only fires when the socket is connected (WebSocket phase); the static
  render phase is ignored.
  """

  import Phoenix.LiveView

  def on_mount(:track, _params, _session, socket) do
    if connected?(socket) do
      user = socket.assigns[:current_customer]

      if user do
        page = page_name(socket.view)
        MobileCarWashWeb.Presence.track_user(self(), user, page)
      end
    end

    {:cont, socket}
  end

  # Human-readable page names keyed by LiveView module.
  # Falls back to a formatted version of the module's last segment.
  @page_names %{
    MobileCarWashWeb.Admin.MetricsLive => "Metrics",
    MobileCarWashWeb.Admin.DispatchLive => "Dispatch",
    MobileCarWashWeb.Admin.CashFlowLive => "Cash Flow",
    MobileCarWashWeb.Admin.FormationLive => "Formation",
    MobileCarWashWeb.Admin.OrgChartLive => "Org Chart",
    MobileCarWashWeb.Admin.ProceduresLive => "SOPs",
    MobileCarWashWeb.Admin.EventsLive => "Events",
    MobileCarWashWeb.Admin.SettingsLive => "Settings",
    MobileCarWashWeb.Admin.VansLive => "Vans",
    MobileCarWashWeb.Admin.SuppliesLive => "Supplies",
    MobileCarWashWeb.Admin.TechnicianProfileLive => "Tech Profile",
    MobileCarWashWeb.Admin.StyleGuideLive => "Style Guide",
    MobileCarWashWeb.TechDashboardLive => "Tech Dashboard",
    MobileCarWashWeb.ChecklistLive => "Checklist",
    MobileCarWashWeb.AppointmentsLive => "My Appointments",
    MobileCarWashWeb.AppointmentStatusLive => "Appointment Status",
    MobileCarWashWeb.SubscriptionManageLive => "Subscription",
    MobileCarWashWeb.BookingLive => "Booking",
    MobileCarWashWeb.SubscriptionLive => "Subscribe"
  }

  defp page_name(view_module) do
    Map.get(@page_names, view_module) ||
      view_module
      |> Module.split()
      |> List.last()
      |> String.replace("Live", "")
      |> then(&Regex.replace(~r/(?<=[a-z])(?=[A-Z])/, &1, " "))
      |> String.trim()
  end
end
