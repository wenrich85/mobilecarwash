defmodule MobileCarWashWeb.Admin.DispatchPresenter do
  @moduledoc """
  Pure presentation helpers for the admin dispatch command center.

  Keep DB access in DispatchLive. This module only derives display state
  from appointments, technicians, progress maps, photos, and flags that
  the LiveView has already loaded.
  """

  @active_statuses [:en_route, :on_site, :in_progress]
  @assignment_statuses [:pending, :confirmed]

  def metrics(appointments, technicians, exceptions) do
    %{
      total: length(appointments),
      in_progress: Enum.count(appointments, &(&1.status in @active_statuses)),
      ready_to_assign: Enum.count(appointments, &ready_to_assign?/1),
      completed: Enum.count(appointments, &(&1.status == :completed)),
      on_duty: Enum.count(technicians, &on_duty?/1),
      exceptions: length(exceptions)
    }
  end

  def assignment_queue(appointments) do
    appointments
    |> Enum.filter(&(&1.status in @assignment_statuses))
    |> Enum.sort_by(& &1.scheduled_at, DateTime)
  end

  def active_appointments(appointments) do
    appointments
    |> Enum.filter(&(&1.status in @active_statuses))
    |> Enum.sort_by(& &1.scheduled_at, DateTime)
  end

  defp ready_to_assign?(appointment) do
    appointment.status in @assignment_statuses and is_nil(appointment.technician_id)
  end

  defp on_duty?(%{active: true, status: :available}), do: true
  defp on_duty?(_), do: false
end
