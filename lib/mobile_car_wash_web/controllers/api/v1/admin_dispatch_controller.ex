defmodule MobileCarWashWeb.Api.V1.AdminDispatchController do
  @moduledoc """
  Admin native dispatch command center endpoints.
  """
  use MobileCarWashWeb, :controller

  import Ecto.Query

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Fleet.{Address, Vehicle}
  alias MobileCarWash.Operations.{Photo, Technician}
  alias MobileCarWash.Repo
  alias MobileCarWash.Scheduling.{Appointment, AppointmentTracker, Dispatch, ServiceType}
  alias MobileCarWashWeb.Admin.DispatchPresenter

  require Ash.Query

  plug MobileCarWashWeb.Plugs.RequireApiAuth
  plug :require_admin
  action_fallback MobileCarWashWeb.Api.V1.FallbackController

  def index(conn, params) do
    with {:ok, date} <- dispatch_date(params["date"]) do
      appointments = appointments_for_date(date)
      maps = preload_maps(appointments)
      progress_by_appointment = progress_by_appointment(appointments)

      photo_counts_by_appointment =
        load_photo_counts_by_appointment(Enum.map(appointments, & &1.id))

      technicians = active_technicians()

      exceptions =
        DispatchPresenter.exceptions(appointments,
          flagged_customer_ids:
            booking_flagged_customer_ids(Enum.map(appointments, & &1.customer_id)),
          tech_requests: %{},
          progress_by_appointment: progress_by_appointment,
          photo_counts_by_appointment: photo_counts_by_appointment
        )

      current_appointment_by_tech = current_appointments_by_tech(technicians, maps.customers)

      data = %{
        generated_at: DateTime.utc_now(),
        date: Date.to_iso8601(date),
        metrics: DispatchPresenter.metrics(appointments, technicians, exceptions),
        active_services:
          appointments
          |> DispatchPresenter.active_appointments()
          |> Enum.map(
            &dispatch_appointment_json(
              &1,
              maps,
              progress_by_appointment,
              photo_counts_by_appointment
            )
          ),
        assignment_queue:
          appointments
          |> DispatchPresenter.assignment_queue()
          |> Enum.map(
            &dispatch_appointment_json(
              &1,
              maps,
              progress_by_appointment,
              photo_counts_by_appointment
            )
          ),
        exceptions: Enum.map(exceptions, &exception_json/1),
        technician_workload:
          technicians
          |> DispatchPresenter.technician_workload(appointments, current_appointment_by_tech)
          |> Enum.map(&technician_workload_json/1)
      }

      json(conn, %{data: data})
    else
      :error ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "invalid_filter"})
    end
  end

  def assign(conn, %{"appointment_id" => id} = params) do
    technician_id = blank_to_nil(params["technician_id"])

    case Dispatch.assign_technician(id, technician_id) do
      {:ok, appointment} ->
        json(conn, %{data: appointment_response_json(appointment)})

      _ ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "not_found"})
    end
  end

  def confirm(conn, %{"appointment_id" => id}) do
    with {:ok, appointment} <- Ash.get(Appointment, id, authorize?: false),
         {:ok, confirmed} <-
           appointment
           |> Ash.Changeset.for_update(:confirm, %{})
           |> Ash.update(authorize?: false) do
      AppointmentTracker.broadcast_assignment_changed(id)
      AppointmentTracker.broadcast_assigned_to_tech(id, confirmed.technician_id)
      json(conn, %{data: appointment_response_json(confirmed)})
    else
      {:error, %Ash.Error.Invalid{}} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "not_transitionable"})

      _ ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "not_found"})
    end
  end

  defp require_admin(conn, _opts) do
    case current_user(conn) do
      %{role: :admin} ->
        conn

      _ ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "forbidden", message: "Admin role required"})
        |> halt()
    end
  end

  defp dispatch_date(nil), do: {:ok, Date.utc_today()}
  defp dispatch_date(""), do: {:ok, Date.utc_today()}

  defp dispatch_date(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      _ -> :error
    end
  end

  defp appointments_for_date(date) do
    {:ok, day_start} = DateTime.new(date, ~T[00:00:00])
    {:ok, day_end} = DateTime.new(Date.add(date, 1), ~T[00:00:00])

    Appointment
    |> Ash.Query.filter(
      scheduled_at >= ^day_start and scheduled_at < ^day_end and status != :cancelled
    )
    |> Ash.Query.sort(scheduled_at: :asc)
    |> Ash.read!(authorize?: false)
  end

  defp progress_by_appointment(appointments) do
    appointments
    |> Enum.filter(&(&1.status == :in_progress))
    |> Enum.map(fn appointment -> {appointment, Dispatch.checklist_progress(appointment.id)} end)
    |> DispatchPresenter.progress_by_appointment()
  end

  defp preload_maps(appointments) do
    customer_ids = appointments |> Enum.map(& &1.customer_id) |> Enum.uniq()

    technician_ids =
      appointments |> Enum.map(& &1.technician_id) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    address_ids = appointments |> Enum.map(& &1.address_id) |> Enum.uniq()
    vehicle_ids = appointments |> Enum.map(& &1.vehicle_id) |> Enum.uniq()
    service_ids = appointments |> Enum.map(& &1.service_type_id) |> Enum.uniq()

    %{
      customers: load_map(Customer, customer_ids),
      technicians: load_map(Technician, technician_ids),
      addresses: load_map(Address, address_ids),
      vehicles: load_map(Vehicle, vehicle_ids),
      services: load_map(ServiceType, service_ids)
    }
  end

  defp load_map(_resource, []), do: %{}

  defp load_map(resource, ids) do
    resource
    |> Ash.Query.filter(id in ^ids)
    |> Ash.read!(authorize?: false)
    |> Map.new(&{&1.id, &1})
  end

  defp active_technicians do
    Technician
    |> Ash.read!(authorize?: false)
    |> Enum.filter(& &1.active)
  end

  defp current_appointments_by_tech(technicians, customer_map) do
    tech_ids = Enum.map(technicians, & &1.id)

    Appointment
    |> Ash.Query.filter(
      technician_id in ^tech_ids and status in [:en_route, :on_site, :in_progress]
    )
    |> Ash.read!(authorize?: false)
    |> Enum.reduce(%{}, fn appointment, acc ->
      customer = Map.get(customer_map, appointment.customer_id)

      summary = %{
        appointment_id: appointment.id,
        status: appointment.status,
        scheduled_at: appointment.scheduled_at,
        customer_name: if(customer, do: customer.name, else: "Customer")
      }

      Map.update(acc, appointment.technician_id, summary, fn existing ->
        if state_order(summary.status) < state_order(existing.status), do: summary, else: existing
      end)
    end)
  end

  defp load_photo_counts_by_appointment([]), do: %{}

  defp load_photo_counts_by_appointment(appointment_ids) do
    Photo
    |> Ash.Query.filter(appointment_id in ^appointment_ids and is_nil(deleted_at))
    |> Ash.read!(authorize?: false)
    |> Enum.group_by(& &1.appointment_id)
    |> Map.new(fn {appointment_id, photos} ->
      counts =
        photos
        |> Enum.group_by(& &1.photo_type)
        |> Map.new(fn {type, typed_photos} -> {type, length(typed_photos)} end)

      {appointment_id,
       %{
         before: Map.get(counts, :before, 0),
         after: Map.get(counts, :after, 0)
       }}
    end)
  end

  defp booking_flagged_customer_ids([]), do: MapSet.new()

  defp booking_flagged_customer_ids(customer_ids) do
    uuids = customer_ids |> Enum.uniq() |> Enum.map(&Ecto.UUID.dump!/1)

    rows =
      from(customer_tag in "customer_tags",
        join: tag in "tags",
        on: customer_tag.tag_id == tag.id,
        where: tag.affects_booking == true,
        where: customer_tag.customer_id in ^uuids,
        select: type(customer_tag.customer_id, Ecto.UUID),
        distinct: true
      )
      |> Repo.all()

    MapSet.new(rows)
  end

  defp appointment_response_json(appointment) do
    maps = preload_maps([appointment])
    dispatch_appointment_json(appointment, maps, %{}, %{})
  end

  defp dispatch_appointment_json(
         appointment,
         maps,
         progress_by_appointment,
         photo_counts_by_appointment
       ) do
    customer = Map.get(maps.customers, appointment.customer_id)
    technician = Map.get(maps.technicians, appointment.technician_id)
    address = Map.get(maps.addresses, appointment.address_id)
    vehicle = Map.get(maps.vehicles, appointment.vehicle_id)
    service = Map.get(maps.services, appointment.service_type_id)
    counts = Map.get(photo_counts_by_appointment, appointment.id, %{before: 0, after: 0})

    %{
      id: appointment.id,
      status: to_string(appointment.status),
      scheduled_at: appointment.scheduled_at,
      duration_minutes: appointment.duration_minutes,
      price_cents: appointment.price_cents,
      customer_id: appointment.customer_id,
      customer_name: customer && customer.name,
      service_type_id: appointment.service_type_id,
      service_name: service && service.name,
      technician_id: appointment.technician_id,
      technician_name: technician && technician.name,
      address_line: address_line(address),
      vehicle_name: vehicle_name(vehicle),
      progress: progress_json(Map.get(progress_by_appointment, appointment.id)),
      before_photo_count: Map.get(counts, :before, 0),
      after_photo_count: Map.get(counts, :after, 0)
    }
  end

  defp progress_json(nil), do: nil

  defp progress_json(progress) do
    %{
      current_step: progress.current_step,
      current_step_number: nil,
      steps_done: progress.steps_done,
      completed_steps: progress.steps_done,
      steps_total: progress.steps_total,
      eta_minutes: progress.eta_minutes,
      photo_type: nil,
      car_part: nil
    }
  end

  defp exception_json(exception) do
    %{
      id: "#{exception.appointment_id}:#{exception.kind}",
      appointment_id: exception.appointment_id,
      customer_id: exception.customer_id,
      severity: to_string(exception.severity),
      kind: to_string(exception.kind),
      reason: exception.reason,
      action: exception.action,
      scheduled_at: exception.scheduled_at
    }
  end

  defp technician_workload_json(workload) do
    %{
      id: workload.id,
      name: workload.name,
      status: to_string(workload.status),
      zone: workload.zone && to_string(workload.zone),
      assigned_count: workload.assigned_count,
      active: workload.active?,
      pressure: to_string(workload.pressure),
      current_appointment_id: workload.current && workload.current.appointment_id
    }
  end

  defp address_line(nil), do: nil

  defp address_line(address) do
    "#{address.street}, #{address.city}, #{address.state} #{address.zip}"
  end

  defp vehicle_name(nil), do: nil

  defp vehicle_name(vehicle) do
    [vehicle.year, vehicle.color, vehicle.make, vehicle.model]
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&to_string/1)
    |> Enum.join(" ")
  end

  defp state_order(:en_route), do: 0
  defp state_order(:on_site), do: 1
  defp state_order(:in_progress), do: 2
  defp state_order(_status), do: 99

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp current_user(conn), do: conn.assigns[:current_user] || conn.assigns[:current_customer]
end
