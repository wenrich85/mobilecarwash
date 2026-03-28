defmodule MobileCarWash.Operations.PhotoUpload do
  @moduledoc """
  Handles photo file storage for appointments.
  MVP: saves to priv/static/uploads/ (move to S3 for production).
  """

  alias MobileCarWash.Operations.Photo

  @upload_dir "priv/static/uploads"

  @doc """
  Saves an uploaded file and creates a Photo record.

  Accepts a Phoenix LiveView upload entry and saves the file,
  then creates the database record.
  """
  def save_upload(appointment_id, entry, photo_type, opts \\ []) do
    uploaded_by = Keyword.get(opts, :uploaded_by, :technician)
    caption = Keyword.get(opts, :caption)
    checklist_item_id = Keyword.get(opts, :checklist_item_id)

    # Create directory
    dir = Path.join([@upload_dir, "appointments", appointment_id])
    File.mkdir_p!(dir)

    # Generate unique filename
    ext = Path.extname(entry.client_name) |> String.downcase()
    filename = "#{photo_type}_#{Ash.UUID.generate()}#{ext}"
    dest = Path.join(dir, filename)

    # The entry is a temp file path from LiveView uploads
    File.cp!(entry.path, dest)

    # Public URL path
    url_path = "/uploads/appointments/#{appointment_id}/#{filename}"

    # Create photo record
    attrs = %{
      file_path: url_path,
      original_filename: entry.client_name,
      content_type: entry.client_type,
      photo_type: photo_type,
      caption: caption,
      uploaded_by: uploaded_by
    }

    Photo
    |> Ash.Changeset.for_create(:upload, attrs)
    |> Ash.Changeset.force_change_attribute(:appointment_id, appointment_id)
    |> then(fn cs ->
      if checklist_item_id do
        Ash.Changeset.force_change_attribute(cs, :checklist_item_id, checklist_item_id)
      else
        cs
      end
    end)
    |> Ash.create()
  end

  @doc """
  Saves a photo from a raw file path (for non-LiveView upload contexts).
  """
  def save_file(appointment_id, source_path, original_filename, photo_type, opts \\ []) do
    uploaded_by = Keyword.get(opts, :uploaded_by, :technician)
    caption = Keyword.get(opts, :caption)

    dir = Path.join([@upload_dir, "appointments", appointment_id])
    File.mkdir_p!(dir)

    ext = Path.extname(original_filename) |> String.downcase()
    filename = "#{photo_type}_#{Ash.UUID.generate()}#{ext}"
    dest = Path.join(dir, filename)

    File.cp!(source_path, dest)

    url_path = "/uploads/appointments/#{appointment_id}/#{filename}"

    attrs = %{
      file_path: url_path,
      original_filename: original_filename,
      content_type: MIME.from_path(original_filename),
      photo_type: photo_type,
      caption: caption,
      uploaded_by: uploaded_by
    }

    Photo
    |> Ash.Changeset.for_create(:upload, attrs)
    |> Ash.Changeset.force_change_attribute(:appointment_id, appointment_id)
    |> Ash.create()
  end
end
