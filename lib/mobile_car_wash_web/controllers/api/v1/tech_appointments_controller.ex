defmodule MobileCarWashWeb.Api.V1.TechAppointmentsController do
  @moduledoc """
  Tech-facing appointment endpoints. The tech only ever sees their own
  appointments (filtered by `technician_id`). Transitions go through the
  corresponding Ash actions, which handle the customer-facing notification
  fanout and PubSub broadcasts automatically.
  """
  use MobileCarWashWeb, :controller

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Fleet.{Address, Vehicle}
  alias MobileCarWash.Operations.Technician
  alias MobileCarWash.Scheduling.{Appointment, ServiceType, WashOrchestrator}

  require Ash.Query

  plug MobileCarWashWeb.Plugs.RequireTechAuth
  action_fallback MobileCarWashWeb.Api.V1.FallbackController

  def index(conn, _params) do
    case find_tech(current_user(conn)) do
      nil ->
        json(conn, %{data: []})

      tech ->
        now = DateTime.utc_now()
        day_end = DateTime.add(now, 24 * 3600, :second)

        appts =
          Appointment
          |> Ash.Query.filter(
            technician_id == ^tech.id and
              status != :cancelled and
              scheduled_at >= ^now and
              scheduled_at < ^day_end
          )
          |> Ash.Query.sort(scheduled_at: :asc)
          |> Ash.read!(authorize?: false)

        maps = preload_maps(appts)

        json(conn, %{data: Enum.map(appts, &appointment_json(&1, maps))})
    end
  end

  # Allowed source statuses for each transition. Prevents the tech from
  # accidentally flipping a :completed or :cancelled appointment back
  # through the state machine via a stale client request.
  @depart_from [:confirmed]
  @arrive_from [:en_route]
  @complete_from [:in_progress]

  def depart(conn, params), do: transition(conn, params, :depart, @depart_from)
  def arrive(conn, params), do: transition(conn, params, :arrive, @arrive_from)
  def complete(conn, params), do: transition(conn, params, :complete, @complete_from)

  def start(conn, %{"id" => id}) do
    with {:ok, appt} <- fetch_own_appointment(current_user(conn), id),
         {:ok, checklist} <- WashOrchestrator.start_wash(appt.id),
         {:ok, reloaded} <- Ash.get(Appointment, appt.id, authorize?: false) do
      maps = preload_maps([reloaded])

      json(conn, %{
        data: %{
          appointment: appointment_json(reloaded, maps),
          checklist_id: checklist.id
        }
      })
    else
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "not_found"})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "not_transitionable", reason: inspect(reason)})
    end
  end

  # ----------------------------------------------------------------

  defp transition(conn, %{"id" => id}, action, allowed_from) do
    with {:ok, appt} <- fetch_own_appointment(current_user(conn), id),
         true <- appt.status in allowed_from,
         {:ok, updated} <-
           appt
           |> Ash.Changeset.for_update(action, %{})
           |> Ash.update(authorize?: false) do
      maps = preload_maps([updated])
      json(conn, %{data: appointment_json(updated, maps)})
    else
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "not_found"})

      false ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          error: "not_transitionable",
          message: "Appointment is not in a valid state for that action."
        })

      {:error, _} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "not_transitionable"})
    end
  end

  # Fetches an appointment and enforces that it belongs to the signed-in
  # tech. Non-owner attempts surface as :not_found so existence isn't
  # leaked to callers who shouldn't see the row.
  defp fetch_own_appointment(user, id) do
    tech = find_tech(user)

    with %Technician{id: tech_id} <- tech,
         {:ok, %{technician_id: ^tech_id} = appt} <-
           Ash.get(Appointment, id, authorize?: false) do
      {:ok, appt}
    else
      _ -> {:error, :not_found}
    end
  end

  defp preload_maps(appts) do
    customer_ids = Enum.map(appts, & &1.customer_id) |> Enum.uniq()
    address_ids = Enum.map(appts, & &1.address_id) |> Enum.uniq()
    vehicle_ids = Enum.map(appts, & &1.vehicle_id) |> Enum.uniq()
    service_ids = Enum.map(appts, & &1.service_type_id) |> Enum.uniq()

    %{
      customers: load_map(Customer, customer_ids),
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

  defp appointment_json(a, maps) do
    customer = Map.get(maps.customers, a.customer_id)
    address = Map.get(maps.addresses, a.address_id)
    vehicle = Map.get(maps.vehicles, a.vehicle_id)
    service = Map.get(maps.services, a.service_type_id)

    %{
      id: a.id,
      status: to_string(a.status),
      scheduled_at: a.scheduled_at,
      duration_minutes: a.duration_minutes,
      price_cents: a.price_cents,
      notes: a.notes,
      service_name: service && service.name,
      customer_name: customer && customer.name,
      customer_phone: customer && customer.phone,
      address:
        address &&
          %{
            street: address.street,
            city: address.city,
            state: address.state,
            zip: address.zip,
            latitude: address.latitude,
            longitude: address.longitude
          },
      vehicle:
        vehicle &&
          %{
            make: vehicle.make,
            model: vehicle.model,
            year: Map.get(vehicle, :year),
            color: Map.get(vehicle, :color)
          }
    }
  end

  defp find_tech(user) do
    techs = Ash.read!(Technician)

    Enum.find(techs, fn t -> t.user_account_id == user.id end) ||
      Enum.find(techs, fn t -> t.name == user.name end)
  end

  defp current_user(conn), do: conn.assigns[:current_user] || conn.assigns[:current_customer]
end
