defmodule MobileCarWashWeb.Live.Helpers.EventTracker do
  @moduledoc """
  Helper module for tracking analytics events from LiveViews.

  Extracts session_id from socket assigns and fires events asynchronously
  to avoid blocking the LiveView process.

  Usage in a LiveView:

      import MobileCarWashWeb.Live.Helpers.EventTracker

      def mount(_params, _session, socket) do
        socket = assign_session_id(socket)
        track_event(socket, "page.viewed", %{path: "/booking"})
        {:ok, socket}
      end
  """

  alias MobileCarWash.Analytics.Event

  @doc """
  Assigns a session_id to the socket if not already present.
  Call this in mount/3.
  """
  def assign_session_id(socket) do
    if Phoenix.LiveView.connected?(socket) do
      session_id = Phoenix.Component.assign(socket, :session_id, nil).assigns[:session_id]

      if session_id do
        socket
      else
        Phoenix.Component.assign(socket, :session_id, generate_session_id())
      end
    else
      Phoenix.Component.assign(socket, :session_id, generate_session_id())
    end
  end

  @doc """
  Tracks an analytics event asynchronously.
  Does not block the LiveView process.
  """
  def track_event(socket, event_name, properties \\ %{}) do
    session_id = socket.assigns[:session_id] || "unknown"
    customer_id =
      case socket.assigns[:current_customer] do
        %{id: id} -> id
        _ -> nil
      end

    # Fire and forget — don't block the LiveView
    Task.start(fn ->
      Event
      |> Ash.Changeset.for_create(:track, %{
        session_id: session_id,
        event_name: event_name,
        source: "web",
        properties: properties,
        customer_id: customer_id
      })
      |> Ash.create()
    end)

    :ok
  end

  defp generate_session_id do
    "sess_" <> Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
  end
end
