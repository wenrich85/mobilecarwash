defmodule MobileCarWash.Operations.PhotoUpload do
  @moduledoc """
  Handles photo file storage for appointments.
  Supports two backends:
  - :local — saves to priv/static/uploads/ (development)
  - :s3 — uploads to AWS S3 bucket (production)

  S3 bucket is configurable per client via app config for multi-tenant support.
  """

  alias MobileCarWash.Operations.Photo

  @local_upload_dir "priv/uploads"

  @doc """
  Saves an uploaded file and creates a Photo record.
  Uses the configured storage backend (:local or :s3).
  """
  # Allowed image magic bytes
  @magic_bytes %{
    <<0xFF, 0xD8, 0xFF>> => "image/jpeg",
    <<0x89, 0x50, 0x4E, 0x47>> => "image/png",
    <<0x52, 0x49, 0x46, 0x46>> => "image/webp"
  }

  def save_file(appointment_id, source_path, original_filename, photo_type, opts \\ []) do
    uploaded_by = Keyword.get(opts, :uploaded_by, :technician)
    caption = Keyword.get(opts, :caption)
    checklist_item_id = Keyword.get(opts, :checklist_item_id)
    car_part = Keyword.get(opts, :car_part)
    client_id = Keyword.get(opts, :client_id, "default")

    ext = Path.extname(original_filename) |> String.downcase()

    # Validate file content matches claimed extension
    with :ok <- validate_file_content(source_path, ext) do
      save_file_validated(appointment_id, source_path, original_filename, ext, photo_type,
        uploaded_by: uploaded_by, caption: caption, checklist_item_id: checklist_item_id,
        car_part: car_part, client_id: client_id)
    end
  end

  defp validate_file_content(source_path, ext) do
    case File.read(source_path) do
      {:ok, <<header::binary-size(4), _rest::binary>>} ->
        valid? = Enum.any?(@magic_bytes, fn {magic, _mime} ->
          byte_size(magic) <= byte_size(header) and :binary.match(header, magic) != :nomatch
        end)
        if valid? or ext in ~w(.jpg .jpeg .png .webp), do: :ok, else: {:error, "Invalid image file"}

      {:ok, _} -> {:error, "File too small to validate"}
      {:error, _} -> {:error, "Cannot read uploaded file"}
    end
  end

  defp save_file_validated(appointment_id, source_path, original_filename, ext, photo_type, opts) do
    uploaded_by = Keyword.get(opts, :uploaded_by, :technician)
    caption = Keyword.get(opts, :caption)
    checklist_item_id = Keyword.get(opts, :checklist_item_id)
    car_part = Keyword.get(opts, :car_part)
    client_id = Keyword.get(opts, :client_id, "default")

    filename = "#{photo_type}_#{Ash.UUID.generate()}#{ext}"
    content_type = MIME.from_path(original_filename)

    # Upload to storage backend
    case storage_backend() do
      :s3 ->
        save_to_s3(appointment_id, source_path, filename, content_type, client_id)

      _ ->
        save_to_local(appointment_id, source_path, filename)
    end
    |> case do
      {:ok, url_path} ->
        # Create photo record
        changeset_attrs = %{
          file_path: url_path,
          original_filename: original_filename,
          content_type: content_type,
          photo_type: photo_type,
          caption: caption,
          uploaded_by: uploaded_by
        }

        changeset_attrs =
          if car_part, do: Map.put(changeset_attrs, :car_part, car_part), else: changeset_attrs

        Photo
        |> Ash.Changeset.for_create(:upload, changeset_attrs)
        |> Ash.Changeset.force_change_attribute(:appointment_id, appointment_id)
        |> then(fn cs ->
          if checklist_item_id do
            Ash.Changeset.force_change_attribute(cs, :checklist_item_id, checklist_item_id)
          else
            cs
          end
        end)
        |> Ash.create()

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Returns the configured storage backend."
  def storage_backend do
    Application.get_env(:mobile_car_wash, :photo_storage, :local)
  end

  @doc "Returns the S3 bucket name (configurable per client)."
  def s3_bucket(client_id \\ "default") do
    base_bucket = Application.get_env(:mobile_car_wash, :s3_bucket, "mobile-car-wash-photos")

    if client_id == "default" do
      base_bucket
    else
      "#{base_bucket}-#{client_id}"
    end
  end

  # --- Local Storage ---

  defp save_to_local(appointment_id, source_path, filename) do
    dir = Path.join([@local_upload_dir, "appointments", appointment_id])
    File.mkdir_p!(dir)

    dest = Path.join(dir, filename)
    File.cp!(source_path, dest)

    url_path = "/photos/appointments/#{appointment_id}/#{filename}"
    {:ok, url_path}
  rescue
    e -> {:error, Exception.message(e)}
  end

  # --- S3 Storage ---

  defp save_to_s3(appointment_id, source_path, filename, content_type, client_id) do
    bucket = s3_bucket(client_id)
    s3_key = "appointments/#{appointment_id}/#{filename}"

    case File.read(source_path) do
      {:ok, file_contents} ->
        request =
          ExAws.S3.put_object(bucket, s3_key, file_contents,
            content_type: content_type,
            acl: :private
          )

        case ExAws.request(request) do
          {:ok, _response} ->
            region = Application.get_env(:mobile_car_wash, :s3_region, "us-east-1")
            url = "https://#{bucket}.s3.#{region}.amazonaws.com/#{s3_key}"
            {:ok, url}

          {:error, reason} ->
            {:error, "S3 upload failed: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, "Could not read file: #{inspect(reason)}"}
    end
  end
end
