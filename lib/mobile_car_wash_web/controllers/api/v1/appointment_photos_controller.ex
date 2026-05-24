defmodule MobileCarWashWeb.Api.V1.AppointmentPhotosController do
  use MobileCarWashWeb, :controller

  alias MobileCarWash.Operations.{Photo, PhotoUpload, Technician}
  alias MobileCarWash.Scheduling.{Appointment, AppointmentTracker}

  require Ash.Query

  plug MobileCarWashWeb.Plugs.RequireTechAuth
  action_fallback MobileCarWashWeb.Api.V1.FallbackController

  @photo_types ~w(before after step_completion)
  @required_car_part_photo_types ~w(before after)
  @max_bytes 10_000_000

  def index(conn, %{"id" => appointment_id}) do
    with {:ok, appointment} <- fetch_appointment(conn, appointment_id) do
      photos =
        Photo
        |> Ash.Query.filter(appointment_id == ^appointment.id and is_nil(deleted_at))
        |> Ash.Query.sort(inserted_at: :desc)
        |> Ash.read!(authorize?: false)
        |> Enum.map(&photo_json/1)

      json(conn, %{data: photos})
    else
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "not_found"})
    end
  end

  def create(conn, %{"id" => appointment_id, "file" => %Plug.Upload{} = upload} = params) do
    with {:ok, appointment} <- fetch_appointment(conn, appointment_id),
         {:ok, photo_type} <- atom_param(params["photo_type"], @photo_types),
         {:ok, car_part} <- car_part_param(params["car_part"], params["photo_type"]),
         {:ok, idempotency_key} <- required_string(params["idempotency_key"]),
         :ok <- validate_size(upload.path),
         {:ok, photo} <-
           PhotoUpload.save_file(appointment.id, upload.path, upload.filename, photo_type,
             uploaded_by: :technician,
             car_part: car_part,
             idempotency_key: idempotency_key,
             checklist_item_id: params["checklist_item_id"]
           ) do
      photo_payload = photo_json(photo)

      AppointmentTracker.broadcast_photo(
        appointment.id,
        photo.photo_type,
        photo.car_part,
        photo_payload
      )

      conn
      |> put_status(:created)
      |> json(%{data: photo_payload})
    else
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "not_found"})

      {:error, :too_large} ->
        conn |> put_status(:request_entity_too_large) |> json(%{error: "file_too_large"})

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: to_string(reason)})
    end
  end

  def create(conn, _params) do
    conn |> put_status(:unprocessable_entity) |> json(%{error: "file_required"})
  end

  def delete(conn, %{"id" => appointment_id, "photo_id" => photo_id}) do
    with {:ok, appointment} <- fetch_appointment(conn, appointment_id),
         {:ok, %{appointment_id: appt_id} = photo} when appt_id == appointment.id <-
           Ash.get(Photo, photo_id, authorize?: false),
         {:ok, _photo} <-
           photo
           |> Ash.Changeset.for_update(:soft_delete, %{})
           |> Ash.update(authorize?: false) do
      json(conn, %{ok: true})
    else
      _ -> conn |> put_status(:not_found) |> json(%{error: "not_found"})
    end
  end

  defp fetch_appointment(conn, id) do
    with {:ok, appointment} <- Ash.get(Appointment, id, authorize?: false),
         true <- can_access?(current_user(conn), appointment) do
      {:ok, appointment}
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

  defp atom_param(value, allowed) when is_binary(value) do
    if value in allowed do
      {:ok, String.to_existing_atom(value)}
    else
      {:error, :invalid_param}
    end
  end

  defp atom_param(_value, _allowed), do: {:error, :invalid_param}

  defp car_part_param(value, photo_type) when photo_type in @required_car_part_photo_types do
    atom_param(value, Enum.map(Photo.key_car_parts(), &to_string/1))
  end

  defp car_part_param(nil, "step_completion"), do: {:ok, nil}

  defp car_part_param(value, "step_completion") do
    atom_param(value, Enum.map(Photo.key_car_parts(), &to_string/1))
  end

  defp car_part_param(_value, _photo_type), do: {:error, :invalid_param}

  defp required_string(value) when is_binary(value) and value != "", do: {:ok, value}
  defp required_string(_), do: {:error, :invalid_param}

  defp validate_size(path) do
    case File.stat(path) do
      {:ok, %{size: size}} when size <= @max_bytes -> :ok
      {:ok, _} -> {:error, :too_large}
      {:error, reason} -> {:error, reason}
    end
  end

  defp photo_json(photo) do
    %{url: url, url_expires_at: expires_at} = PhotoUpload.signed_url_for(photo)

    %{
      id: photo.id,
      appointment_id: photo.appointment_id,
      photo_type: to_string(photo.photo_type),
      car_part: photo.car_part && to_string(photo.car_part),
      url: url,
      uploaded_at: photo.inserted_at,
      url_expires_at: expires_at,
      caption: photo.caption,
      uploaded_by: to_string(photo.uploaded_by),
      checklist_item_id: photo.checklist_item_id
    }
  end

  defp find_tech(user) do
    Technician
    |> Ash.read!(authorize?: false)
    |> Enum.find(fn t -> t.user_account_id == user.id || t.name == user.name end)
  end

  defp current_user(conn), do: conn.assigns[:current_user] || conn.assigns[:current_customer]
end
