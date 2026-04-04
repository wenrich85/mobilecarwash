defmodule MobileCarWash.Scheduling.Dispatch do
  @moduledoc """
  Dispatch operations — assign technicians to appointments,
  query appointments by date/status for the dispatch dashboard.
  """

  alias MobileCarWash.Repo
  alias MobileCarWash.Scheduling.{Appointment, AppointmentTracker}
  alias MobileCarWash.Operations.{AppointmentChecklist, ChecklistItem}

  import Ecto.Query
  require Ash.Query

  @doc "Assign a technician to an appointment."
  def assign_technician(appointment_id, technician_id) do
    tech_uuid = if technician_id, do: Ecto.UUID.dump!(technician_id), else: nil

    Repo.update_all(
      from(a in "appointments", where: a.id == type(^appointment_id, :binary_id)),
      set: [technician_id: tech_uuid]
    )

    AppointmentTracker.broadcast_assignment_changed(appointment_id)
    AppointmentTracker.broadcast_assigned_to_tech(appointment_id, technician_id)
    Ash.get(Appointment, appointment_id)
  end

  @doc "Unassign a technician from an appointment."
  def unassign_technician(appointment_id) do
    Repo.update_all(
      from(a in "appointments", where: a.id == type(^appointment_id, :binary_id)),
      set: [technician_id: nil]
    )

    AppointmentTracker.broadcast_assignment_changed(appointment_id)
    Ash.get(Appointment, appointment_id)
  end

  @doc "Load appointments for a given date with related data."
  def appointments_for_date(date) do
    {:ok, day_start} = DateTime.new(date, ~T[00:00:00])
    {:ok, day_end} = DateTime.new(Date.add(date, 1), ~T[00:00:00])

    Appointment
    |> Ash.Query.filter(scheduled_at >= ^day_start and scheduled_at < ^day_end and status != :cancelled)
    |> Ash.Query.sort(scheduled_at: :asc)
    |> Ash.read!()
  end

  @doc "Load checklist progress for an appointment. Returns {steps_done, steps_total, current_step}."
  def checklist_progress(appointment_id) do
    checklists =
      AppointmentChecklist
      |> Ash.Query.filter(appointment_id == ^appointment_id)
      |> Ash.read!()

    case checklists do
      [checklist | _] ->
        items =
          ChecklistItem
          |> Ash.Query.filter(checklist_id == ^checklist.id)
          |> Ash.Query.sort(step_number: :asc)
          |> Ash.read!()

        total = length(items)
        done = Enum.count(items, & &1.completed)
        active = Enum.find(items, &(&1.started_at && !&1.completed))
        next = Enum.find(items, &(!&1.completed))
        current = active || next
        eta = items |> Enum.reject(& &1.completed) |> Enum.reduce(0, fn i, acc -> acc + (i.estimated_minutes || 5) end)

        %{
          checklist_id: checklist.id,
          steps_done: done,
          steps_total: total,
          current_step: current && current.title,
          eta_minutes: eta,
          checklist_status: checklist.status
        }

      [] ->
        %{checklist_id: nil, steps_done: 0, steps_total: 0, current_step: nil, eta_minutes: nil, checklist_status: nil}
    end
  end
end
