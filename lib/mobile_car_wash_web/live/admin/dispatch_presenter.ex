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

  def exceptions(appointments, opts) do
    flagged_customer_ids = Keyword.fetch!(opts, :flagged_customer_ids)
    tech_requests = Keyword.fetch!(opts, :tech_requests)
    progress_by_appointment = Keyword.fetch!(opts, :progress_by_appointment)
    photo_counts_by_appointment = Keyword.fetch!(opts, :photo_counts_by_appointment)

    appointments
    |> Enum.flat_map(fn appointment ->
      []
      |> maybe_add_unassigned(appointment)
      |> maybe_add_unconfirmed(appointment)
      |> maybe_add_booking_flag(appointment, flagged_customer_ids)
      |> maybe_add_tech_request(appointment, tech_requests)
      |> maybe_add_stalled_checklist(appointment, progress_by_appointment)
      |> maybe_add_missing_required_photos(appointment, photo_counts_by_appointment)
    end)
    |> Enum.sort(fn left, right ->
      {severity_order(left.severity), left.scheduled_at} <=
        {severity_order(right.severity), right.scheduled_at}
    end)
  end

  def technician_workload(technicians, appointments, current_appointment_by_tech) do
    Enum.map(technicians, fn tech ->
      assigned =
        Enum.filter(appointments, &(&1.technician_id == tech.id and &1.status != :completed))

      current = Map.get(current_appointment_by_tech, tech.id)

      %{
        id: tech.id,
        name: tech.name,
        status: tech.status,
        zone: Map.get(tech, :zone),
        assigned_count: length(assigned),
        active?: not is_nil(current),
        current: current,
        pressure: workload_pressure(length(assigned), current)
      }
    end)
  end

  def progress_by_appointment(active) do
    Map.new(active, fn {appointment, progress} -> {appointment.id, progress} end)
  end

  defp ready_to_assign?(appointment) do
    appointment.status in @assignment_statuses and is_nil(appointment.technician_id)
  end

  defp on_duty?(%{active: true, status: :available}), do: true
  defp on_duty?(_), do: false

  defp maybe_add_unassigned(exceptions, %{status: status, technician_id: nil} = appointment)
       when status in [:pending, :confirmed] do
    [
      exception(appointment, :unassigned, :high, "Needs technician", "Assign a technician")
      | exceptions
    ]
  end

  defp maybe_add_unassigned(exceptions, _appointment), do: exceptions

  defp maybe_add_unconfirmed(
         exceptions,
         %{status: :pending, technician_id: tech_id} = appointment
       )
       when not is_nil(tech_id) do
    [
      exception(
        appointment,
        :unconfirmed,
        :medium,
        "Assigned but not confirmed",
        "Confirm appointment"
      )
      | exceptions
    ]
  end

  defp maybe_add_unconfirmed(exceptions, _appointment), do: exceptions

  defp maybe_add_booking_flag(exceptions, appointment, flagged_customer_ids) do
    if MapSet.member?(flagged_customer_ids, appointment.customer_id) do
      [
        exception(
          appointment,
          :booking_flag,
          :high,
          "Customer booking flag",
          "Review customer record"
        )
        | exceptions
      ]
    else
      exceptions
    end
  end

  defp maybe_add_tech_request(exceptions, appointment, tech_requests) do
    if Map.has_key?(tech_requests, appointment.id) do
      [
        exception(
          appointment,
          :tech_request,
          :medium,
          "Technician requested this job",
          "Review request"
        )
        | exceptions
      ]
    else
      exceptions
    end
  end

  defp maybe_add_stalled_checklist(
         exceptions,
         %{status: :in_progress} = appointment,
         progress_by_appointment
       ) do
    progress = Map.get(progress_by_appointment, appointment.id)

    if progress && progress.steps_total > 0 && progress.steps_done == 0 do
      [
        exception(
          appointment,
          :stalled_checklist,
          :medium,
          "Checklist has not advanced",
          "Check service progress"
        )
        | exceptions
      ]
    else
      exceptions
    end
  end

  defp maybe_add_stalled_checklist(exceptions, _appointment, _progress_by_appointment),
    do: exceptions

  defp maybe_add_missing_required_photos(
         exceptions,
         %{status: :in_progress} = appointment,
         photo_counts_by_appointment
       ) do
    counts = Map.get(photo_counts_by_appointment, appointment.id, %{before: 0, after: 0})

    if Map.get(counts, :before, 0) == 0 do
      [
        exception(
          appointment,
          :missing_before_photos,
          :medium,
          "Before photos missing",
          "Ask tech to upload proof"
        )
        | exceptions
      ]
    else
      exceptions
    end
  end

  defp maybe_add_missing_required_photos(exceptions, _appointment, _photo_counts_by_appointment),
    do: exceptions

  defp exception(appointment, kind, severity, reason, action) do
    %{
      appointment_id: appointment.id,
      customer_id: appointment.customer_id,
      scheduled_at: appointment.scheduled_at,
      kind: kind,
      severity: severity,
      reason: reason,
      action: action
    }
  end

  defp workload_pressure(count, current) when count >= 4 or not is_nil(current), do: :high
  defp workload_pressure(count, _current) when count >= 2, do: :medium
  defp workload_pressure(_count, _current), do: :normal

  defp severity_order(:high), do: 0
  defp severity_order(:medium), do: 1
  defp severity_order(:low), do: 2
end
