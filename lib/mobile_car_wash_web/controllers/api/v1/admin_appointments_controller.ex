defmodule MobileCarWashWeb.Api.V1.AdminAppointmentsController do
  @moduledoc """
  Admin-facing appointment endpoints for native command center clients.
  """
  use MobileCarWashWeb, :controller

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Fleet.{Address, Vehicle}
  alias MobileCarWash.Operations.Technician
  alias MobileCarWash.Scheduling.{Appointment, ServiceType}

  require Ash.Query

  plug MobileCarWashWeb.Plugs.RequireApiAuth
  plug :require_admin
  action_fallback MobileCarWashWeb.Api.V1.FallbackController

  @statuses ~w(pending confirmed en_route on_site in_progress completed cancelled)

  def index(conn, params) do
    with {:ok, date_range} <- date_range(params["date"]),
         {:ok, status} <- status_filter(params["status"]) do
      appointments =
        Appointment
        |> maybe_filter_date(date_range)
        |> maybe_filter_status(status)
        |> maybe_filter_technician(params["technician_id"])
        |> Ash.Query.sort(scheduled_at: :asc)
        |> Ash.read!(authorize?: false)

      maps = preload_maps(appointments)

      json(conn, %{data: Enum.map(appointments, &appointment_json(&1, maps))})
    else
      :error ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "invalid_filter"})
    end
  end

  def show(conn, %{"id" => id}) do
    case Ash.get(Appointment, id, authorize?: false) do
      {:ok, appointment} ->
        maps = preload_maps([appointment])
        json(conn, %{data: appointment_json(appointment, maps)})

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

  defp date_range(nil), do: {:ok, nil}
  defp date_range(""), do: {:ok, nil}

  defp date_range(value) do
    with {:ok, date} <- Date.from_iso8601(value),
         {:ok, starts_at} <- DateTime.new(date, ~T[00:00:00]),
         {:ok, ends_at} <- DateTime.new(Date.add(date, 1), ~T[00:00:00]) do
      {:ok, {starts_at, ends_at}}
    else
      _ -> :error
    end
  end

  defp status_filter(nil), do: {:ok, nil}
  defp status_filter(""), do: {:ok, nil}
  defp status_filter(value) when value in @statuses, do: {:ok, String.to_existing_atom(value)}
  defp status_filter(_value), do: :error

  defp maybe_filter_date(query, nil), do: query

  defp maybe_filter_date(query, {starts_at, ends_at}) do
    Ash.Query.filter(query, scheduled_at >= ^starts_at and scheduled_at < ^ends_at)
  end

  defp maybe_filter_status(query, nil), do: query

  defp maybe_filter_status(query, status) do
    Ash.Query.filter(query, status == ^status)
  end

  defp maybe_filter_technician(query, value) when value in [nil, ""], do: query

  defp maybe_filter_technician(query, "unassigned") do
    Ash.Query.filter(query, is_nil(technician_id))
  end

  defp maybe_filter_technician(query, technician_id) do
    Ash.Query.filter(query, technician_id == ^technician_id)
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

  defp appointment_json(appointment, maps) do
    customer = Map.get(maps.customers, appointment.customer_id)
    technician = Map.get(maps.technicians, appointment.technician_id)
    address = Map.get(maps.addresses, appointment.address_id)
    vehicle = Map.get(maps.vehicles, appointment.vehicle_id)
    service = Map.get(maps.services, appointment.service_type_id)

    %{
      id: appointment.id,
      status: to_string(appointment.status),
      scheduled_at: appointment.scheduled_at,
      duration_minutes: appointment.duration_minutes,
      price_cents: appointment.price_cents,
      discount_cents: appointment.discount_cents || 0,
      appointment_block_id: appointment.appointment_block_id,
      service_type_id: appointment.service_type_id,
      vehicle_id: appointment.vehicle_id,
      address_id: appointment.address_id,
      route_position: appointment.route_position,
      customer_id: appointment.customer_id,
      customer_name: customer && customer.name,
      technician_id: appointment.technician_id,
      technician_name: technician && technician.name,
      service_name: service && service.name,
      address_line: address_line(address),
      vehicle_name: vehicle_name(vehicle)
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

  defp current_user(conn), do: conn.assigns[:current_user] || conn.assigns[:current_customer]
end
