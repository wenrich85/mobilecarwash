defmodule MobileCarWashWeb.Presence do
  @moduledoc """
  Phoenix Presence for tracking online users across all authenticated LiveViews.

  Each connected LiveView process registers its user once on mount.
  The metrics dashboard subscribes to the presence topic and shows who is
  online in real time — name, role, current page, and time connected.
  """
  use Phoenix.Presence,
    otp_app: :mobile_car_wash,
    pubsub_server: MobileCarWash.PubSub

  @topic "presence:users"

  def topic, do: @topic

  @doc """
  Track a user process in the global presence list.
  Called from the TrackPresence on_mount hook when the socket is connected.
  """
  def track_user(pid, user, page) do
    track(pid, @topic, user.id, %{
      name: user.name || to_string(user.email),
      email: to_string(user.email),
      role: user.role,
      page: page,
      online_at: System.system_time(:second)
    })
  end

  @doc """
  Returns a flat list of currently online users, one entry per user
  (using the first meta if the same user has multiple tabs open).
  Sorted by role priority then name.
  """
  def list_users do
    @topic
    |> list()
    |> Enum.map(fn {_id, %{metas: [meta | _]}} -> meta end)
    |> Enum.sort_by(fn u -> {role_order(u.role), u.name} end)
  end

  defp role_order(:admin), do: 0
  defp role_order(:technician), do: 1
  defp role_order(_), do: 2
end
