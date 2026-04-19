defmodule MobileCarWashWeb.PhotoController do
  @moduledoc """
  Serves appointment photos with authorization.

  Only the customer who owns the appointment, the assigned technician,
  or an admin can view photos. Prevents direct public URL access to
  sensitive before/after and problem-area photos.

  Local dev: serves files from priv/uploads/ (not priv/static/).
  Production: redirects to presigned S3 URLs.
  """
  use MobileCarWashWeb, :controller

  alias MobileCarWash.Scheduling.Appointment

  require Ash.Query

  @local_upload_dir "priv/uploads"

  def show(conn, %{"appointment_id" => appointment_id, "filename" => filename}) do
    with {:ok, current_customer} <- require_auth(conn),
         {:ok, appointment} <- load_appointment(appointment_id),
         :ok <- authorize_access(current_customer, appointment) do
      serve_photo(conn, appointment_id, filename)
    else
      {:error, :unauthenticated} ->
        conn |> put_status(401) |> text("Authentication required")

      {:error, :not_found} ->
        conn |> put_status(404) |> text("Not found")

      {:error, :forbidden} ->
        conn |> put_status(403) |> text("Forbidden")
    end
  end

  # --- Private ---

  defp require_auth(conn) do
    session = get_session(conn)

    case session do
      %{"customer_token" => token} when is_binary(token) ->
        case AshAuthentication.Jwt.verify(token, :mobile_car_wash) do
          {:ok, %{"sub" => subject}, _} ->
            case AshAuthentication.subject_to_user(subject, MobileCarWash.Accounts.Customer) do
              {:ok, customer} -> {:ok, customer}
              _ -> {:error, :unauthenticated}
            end

          _ ->
            {:error, :unauthenticated}
        end

      _ ->
        {:error, :unauthenticated}
    end
  end

  defp load_appointment(appointment_id) do
    case Ash.get(Appointment, appointment_id) do
      {:ok, appt} -> {:ok, appt}
      _ -> {:error, :not_found}
    end
  end

  defp authorize_access(customer, appointment) do
    cond do
      customer.role == :admin -> :ok
      appointment.customer_id == customer.id -> :ok
      appointment.technician_id != nil and assigned_technician?(customer, appointment) -> :ok
      true -> {:error, :forbidden}
    end
  end

  defp assigned_technician?(customer, appointment) do
    alias MobileCarWash.Operations.Technician
    require Ash.Query

    techs =
      Technician
      |> Ash.Query.filter(user_account_id == ^customer.id)
      |> Ash.read!()

    Enum.any?(techs, fn t -> t.id == appointment.technician_id end)
  end

  defp serve_photo(conn, appointment_id, filename) do
    case MobileCarWash.Operations.PhotoUpload.storage_backend() do
      :s3 ->
        serve_s3_photo(conn, appointment_id, filename)

      _ ->
        serve_local_photo(conn, appointment_id, filename)
    end
  end

  defp serve_local_photo(conn, appointment_id, filename) do
    # URL-decoded + basename-ed to prevent path traversal
    safe_filename = filename |> URI.decode() |> Path.basename()
    path = Path.join([@local_upload_dir, "appointments", appointment_id, safe_filename])

    if File.exists?(path) do
      content_type = MIME.from_path(safe_filename)

      conn
      |> put_resp_content_type(content_type)
      |> send_file(200, path)
    else
      conn |> put_status(404) |> text("Photo not found")
    end
  end

  defp serve_s3_photo(conn, appointment_id, filename) do
    bucket = MobileCarWash.Operations.PhotoUpload.s3_bucket()
    s3_key = "appointments/#{appointment_id}/#{Path.basename(filename)}"
    region = Application.get_env(:mobile_car_wash, :s3_region, "us-east-1")

    # Generate presigned URL valid for 5 minutes
    case ExAws.S3.presigned_url(ExAws.Config.new(:s3, region: region), :get, bucket, s3_key,
           expires_in: 300
         ) do
      {:ok, url} ->
        redirect(conn, external: url)

      {:error, _} ->
        conn |> put_status(500) |> text("Could not generate photo URL")
    end
  end
end
