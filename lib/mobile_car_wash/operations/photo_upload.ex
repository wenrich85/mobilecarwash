defmodule MobileCarWash.Operations.PhotoUpload do
  @moduledoc """
  Handles photo file storage for appointments.
  Supports two backends:
  - :local — saves to priv/static/uploads/ (development)
  - :s3 — uploads to AWS S3 bucket (production)

  S3 bucket is configurable per client via app config for multi-tenant support.
  """

  alias MobileCarWash.Operations.Photo

  @local_upload_dir "priv/static/uploads"

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

        case Photo
             |> Ash.Changeset.for_create(:upload, changeset_attrs)
             |> Ash.Changeset.force_change_attribute(:appointment_id, appointment_id)
             |> then(fn cs ->
               if checklist_item_id do
                 Ash.Changeset.force_change_attribute(cs, :checklist_item_id, checklist_item_id)
               else
                 cs
               end
             end)
             |> Ash.create() do
          {:ok, photo} = ok ->
            maybe_enqueue_ai_analysis(photo)
            ok

          other ->
            other
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Only :problem_area photos uploaded by the customer trigger the
  # vision-model analyzer. Tech-uploaded :before / :after / :step_completion
  # photos are handled by a separate before/after QA worker (not yet built).
  defp maybe_enqueue_ai_analysis(%{photo_type: :problem_area, uploaded_by: :customer, id: id}) do
    %{photo_id: id}
    |> MobileCarWash.AI.PhotoAnalyzerWorker.new(queue: :notifications)
    |> Oban.insert()
  end

  defp maybe_enqueue_ai_analysis(_photo), do: :ok

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

  @doc """
  Returns a display URL for a photo.
  - Local: returns `file_path` as-is — already a `/uploads/...` path served by Plug.Static.
  - S3: generates a presigned GET URL valid for 4 hours. The stored `file_path` is the
    S3 object key (e.g. `appointments/<id>/before_<uuid>.jpg`). Legacy records that stored
    the full `https://...` URL are handled transparently.

  Call this when loading photos into LiveView assigns, not in render loops.
  """
  def url_for(%{file_path: path}) do
    case storage_backend() do
      :s3 -> presign_url(path)
      _ -> path
    end
  end

  @doc "Returns the photo with `file_path` replaced by its display URL. Useful for Enum.map."
  def apply_url(photo), do: %{photo | file_path: url_for(photo)}

  @doc """
  Deletes the photo file from storage (local disk or S3).
  Does not touch the database record — callers are responsible for that.
  Returns `:ok` even if the file no longer exists (idempotent).
  """
  def delete_file(%{file_path: path}) do
    case storage_backend() do
      :s3 ->
        bucket = s3_bucket()
        region = Application.get_env(:mobile_car_wash, :s3_region, "us-east-1")
        key = normalize_s3_key(path, bucket, region)

        case ExAws.S3.delete_object(bucket, key) |> ExAws.request() do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, reason}
        end

      _ ->
        # path is like /uploads/appointments/<id>/filename
        local = Path.join("priv/static", path)

        case File.rm(local) do
          :ok -> :ok
          {:error, :enoent} -> :ok  # already gone — treat as success
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp presign_url(path) do
    bucket = s3_bucket()
    region = Application.get_env(:mobile_car_wash, :s3_region, "us-east-1")
    key = normalize_s3_key(path, bucket, region)
    config = ExAws.Config.new(:s3, region: region)

    case ExAws.S3.presigned_url(config, :get, bucket, key, expires_in: 14_400) do
      {:ok, url} -> url
      _ -> path  # fallback — will 403 in browser but won't crash the app
    end
  end

  # Handles both storage formats:
  #   Legacy full URL: "https://bucket.s3.region.amazonaws.com/appointments/id/file.jpg"
  #   Current key:     "appointments/id/file.jpg"
  defp normalize_s3_key(path, bucket, region) do
    prefix = "https://#{bucket}.s3.#{region}.amazonaws.com/"

    if String.starts_with?(path, prefix) do
      String.replace_prefix(path, prefix, "")
    else
      path
    end
  end

  # --- Local Storage ---

  defp save_to_local(appointment_id, source_path, filename) do
    dir = Path.join([@local_upload_dir, "appointments", appointment_id])
    File.mkdir_p!(dir)

    dest = Path.join(dir, filename)
    File.cp!(source_path, dest)

    url_path = "/uploads/appointments/#{appointment_id}/#{filename}"
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
            # Store the S3 key, not the full URL. url_for/1 generates presigned URLs at display time.
            {:ok, s3_key}

          {:error, reason} ->
            {:error, "S3 upload failed: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, "Could not read file: #{inspect(reason)}"}
    end
  end
end
