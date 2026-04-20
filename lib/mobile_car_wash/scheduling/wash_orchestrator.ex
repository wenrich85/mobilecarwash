defmodule MobileCarWash.Scheduling.WashOrchestrator do
  @moduledoc """
  Orchestrates starting and completing a wash.
  Creates the checklist from the SOP procedure, manages appointment
  status transitions, and broadcasts to the customer.
  """

  alias MobileCarWash.Repo
  alias MobileCarWash.Booking.WashStateMachine
  alias MobileCarWash.Scheduling.Appointment
  alias MobileCarWash.Operations.{Procedure, ProcedureStep, AppointmentChecklist, ChecklistItem}

  require Ash.Query

  @doc """
  Starts a wash: creates checklist from SOP, transitions appointment to :in_progress.
  Returns {:ok, checklist} or {:error, reason}.
  """
  def start_wash(appointment_id) do
    with {:ok, appointment} <- Ash.get(Appointment, appointment_id),
         true <- WashStateMachine.can_start_wash?(appointment) || {:error, :cannot_start_wash},
         {:ok, procedure} <- find_procedure(appointment.service_type_id),
         {:ok, checklist} <- create_checklist(appointment, procedure),
         {:ok, _appointment} <- transition_appointment_to_in_progress(appointment) do
      {:ok, checklist}
    else
      {:error, reason} -> {:error, reason}
      false -> {:error, :cannot_start_wash}
    end
  end

  @doc """
  Completes a wash: marks checklist and appointment as completed.
  Called when all required checklist items are done.
  """
  def complete_wash(appointment_id) do
    with {:ok, appointment} <- Ash.get(Appointment, appointment_id),
         {:ok, checklist} <- find_checklist(appointment_id),
         true <-
           WashStateMachine.can_complete_wash?(appointment, checklist.status) ||
             {:error, :cannot_complete} do
      # Mark appointment complete (broadcasts via after_action)
      appointment
      |> Ash.Changeset.for_update(:complete, %{})
      |> Ash.update()
    else
      {:error, reason} -> {:error, reason}
      false -> {:error, :cannot_complete}
    end
  end

  # --- Private ---

  defp find_procedure(service_type_id) do
    procedures =
      Procedure
      |> Ash.Query.filter(service_type_id == ^service_type_id and active == true)
      |> Ash.read!()

    case procedures do
      [procedure | _] ->
        {:ok, procedure}

      [] ->
        # Fallback: find any active wash procedure
        fallback =
          Procedure
          |> Ash.Query.filter(category == :wash and active == true)
          |> Ash.read!()

        case fallback do
          [p | _] -> {:ok, p}
          [] -> {:error, :no_procedure_found}
        end
    end
  end

  defp create_checklist(appointment, procedure) do
    # Load procedure steps
    steps =
      ProcedureStep
      |> Ash.Query.filter(procedure_id == ^procedure.id)
      |> Ash.Query.sort(step_number: :asc)
      |> Ash.read!()

    Repo.transaction(fn ->
      # Create the checklist container
      {:ok, checklist} =
        AppointmentChecklist
        |> Ash.Changeset.for_create(:create, %{status: :not_started})
        |> Ash.Changeset.force_change_attribute(:appointment_id, appointment.id)
        |> Ash.Changeset.force_change_attribute(:procedure_id, procedure.id)
        |> Ash.create()

      # Copy steps into checklist items
      for step <- steps do
        ChecklistItem
        |> Ash.Changeset.for_create(:create, %{
          step_number: step.step_number,
          title: step.title,
          description: step.description,
          estimated_minutes: step.estimated_minutes,
          required: step.required
        })
        |> Ash.Changeset.force_change_attribute(:checklist_id, checklist.id)
        |> Ash.Changeset.force_change_attribute(:procedure_step_id, step.id)
        |> Ash.create!()
      end

      checklist
    end)
  end

  defp transition_appointment_to_in_progress(appointment) do
    appointment
    |> Ash.Changeset.for_update(:start, %{})
    |> Ash.update()
  end

  defp find_checklist(appointment_id) do
    checklists =
      AppointmentChecklist
      |> Ash.Query.filter(appointment_id == ^appointment_id)
      |> Ash.read!()

    case checklists do
      [checklist | _] -> {:ok, checklist}
      [] -> {:error, :no_checklist}
    end
  end
end
