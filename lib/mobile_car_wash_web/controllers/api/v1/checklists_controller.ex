defmodule MobileCarWashWeb.Api.V1.ChecklistsController do
  use MobileCarWashWeb, :controller

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Fleet.Vehicle
  alias MobileCarWash.Operations.{AppointmentChecklist, ChecklistItem, Photo}
  alias MobileCarWash.Operations.Technician
  alias MobileCarWash.Scheduling.{Appointment, AppointmentTracker, ServiceType}

  require Ash.Query

  plug MobileCarWashWeb.Plugs.RequireTechAuth
  action_fallback MobileCarWashWeb.Api.V1.FallbackController

  def show(conn, %{"id" => id}) do
    with {:ok, checklist} <- fetch_checklist(conn, id) do
      json(conn, %{data: checklist_json(checklist)})
    else
      {:error, :not_found} -> conn |> put_status(:not_found) |> json(%{error: "not_found"})
    end
  end

  def start_item(conn, %{"id" => id, "item_id" => item_id}) do
    update_item(conn, id, item_id, :start_step)
  end

  def complete_item(conn, %{"id" => id, "item_id" => item_id}) do
    with {:ok, item} <- update_item_record(conn, id, item_id, :check),
         {:ok, checklist} <- Ash.get(AppointmentChecklist, id, authorize?: false) do
      broadcast_step_update(checklist)
      json(conn, %{data: item_json(item)})
    else
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "not_found"})

      {:error, _} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "not_transitionable"})
    end
  end

  defp update_item(conn, id, item_id, action) do
    case update_item_record(conn, id, item_id, action) do
      {:ok, item} ->
        json(conn, %{data: item_json(item)})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "not_found"})

      {:error, _} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "not_transitionable"})
    end
  end

  defp update_item_record(conn, checklist_id, item_id, action) do
    with {:ok, _checklist} <- fetch_checklist(conn, checklist_id),
         {:ok, %{checklist_id: ^checklist_id} = item} <-
           Ash.get(ChecklistItem, item_id, authorize?: false) do
      item
      |> Ash.Changeset.for_update(action, %{})
      |> Ash.update(authorize?: false)
    else
      _ -> {:error, :not_found}
    end
  end

  defp fetch_checklist(conn, id) do
    with {:ok, checklist} <- Ash.get(AppointmentChecklist, id, authorize?: false),
         {:ok, appointment} <- Ash.get(Appointment, checklist.appointment_id, authorize?: false),
         true <- can_access?(current_user(conn), appointment) do
      {:ok, checklist}
    else
      _ -> {:error, :not_found}
    end
  end

  defp can_access?(%{role: :admin}, _appointment), do: true

  defp can_access?(user, %{technician_id: technician_id}) do
    case find_tech(user) do
      %Technician{id: ^technician_id} -> true
      _ -> false
    end
  end

  defp checklist_json(checklist) do
    appointment = Ash.get!(Appointment, checklist.appointment_id, authorize?: false)
    items = checklist_items(checklist.id)

    customer =
      appointment.customer_id && Ash.get!(Customer, appointment.customer_id, authorize?: false)

    vehicle =
      appointment.vehicle_id && Ash.get!(Vehicle, appointment.vehicle_id, authorize?: false)

    service =
      appointment.service_type_id &&
        Ash.get!(ServiceType, appointment.service_type_id, authorize?: false)

    %{
      id: checklist.id,
      appointment_id: checklist.appointment_id,
      appointment: %{
        id: appointment.id,
        customer_name: customer && customer.name,
        vehicle: vehicle && %{make: vehicle.make, model: vehicle.model, year: vehicle.year},
        scheduled_at: appointment.scheduled_at,
        service_name: service && service.name
      },
      items: Enum.map(items, &item_json/1),
      photo_summary: photo_summary(appointment.id)
    }
  end

  defp checklist_items(checklist_id) do
    ChecklistItem
    |> Ash.Query.filter(checklist_id == ^checklist_id)
    |> Ash.Query.sort(step_number: :asc)
    |> Ash.read!(authorize?: false)
  end

  defp item_json(item) do
    %{
      id: item.id,
      step_number: item.step_number,
      title: item.title,
      estimated_seconds: (item.estimated_minutes || 1) * 60,
      started_at: item.started_at,
      completed: item.completed,
      actual_seconds: item.actual_seconds,
      notes: item.notes
    }
  end

  defp photo_summary(appointment_id) do
    parts = Photo.key_car_parts()

    photos =
      Photo
      |> Ash.Query.filter(appointment_id == ^appointment_id and is_nil(deleted_at))
      |> Ash.read!(authorize?: false)

    count = fn type ->
      photos
      |> Enum.filter(&(&1.photo_type == type and &1.car_part in parts))
      |> Enum.map(& &1.car_part)
      |> Enum.uniq()
      |> length()
    end

    %{
      before: %{done: count.(:before), total: length(parts)},
      after: %{done: count.(:after), total: length(parts)}
    }
  end

  defp broadcast_step_update(checklist) do
    items = checklist_items(checklist.id)
    done = Enum.count(items, & &1.completed)
    current = Enum.find(items, &(not &1.completed))

    AppointmentTracker.broadcast_step_progress(checklist.appointment_id, %{
      current_step: current && current.title,
      steps_done: done,
      steps_total: length(items),
      items: items
    })
  end

  defp find_tech(user) do
    Technician
    |> Ash.read!(authorize?: false)
    |> Enum.find(fn t -> t.user_account_id == user.id || t.name == user.name end)
  end

  defp current_user(conn), do: conn.assigns[:current_user] || conn.assigns[:current_customer]
end
