defmodule MobileCarWashWeb.PhotoUploader do
  @moduledoc """
  Shared photo-upload UI used by the booking flow (problem-area photos
  step) and the appointments-list modal. Renders:

    * a prominent drop zone that wraps `.live_file_input`
    * a 2-col mobile / 3-col desktop preview grid with per-photo
      delete buttons
    * a car-part chip row (six common parts + a collapsible "More…")
    * a caption input

  Auto-upload is handled by the parent LiveView via a `handle_progress`
  callback on the upload config — this component doesn't own the
  upload-consume lifecycle.
  """
  use Phoenix.Component

  @common_parts [
    {"Scratch", :exterior},
    {"Dent", :bumper},
    {"Stain", :interior},
    {"Wheels", :wheels},
    {"Windows", :windows},
    {"Interior", :interior}
  ]

  @all_parts [
    {"Exterior", :exterior},
    {"Bumper", :bumper},
    {"Windows", :windows},
    {"Wheels", :wheels},
    {"Interior", :interior},
    {"Trunk", :trunk},
    {"Engine bay", :engine_bay},
    {"Undercarriage", :undercarriage},
    {"Mirrors", :mirrors},
    {"Headlights / taillights", :headlights_taillights},
    {"Roof", :roof},
    {"Sunroof", :sunroof}
  ]

  @doc """
  Full uploader — drop zone + in-progress previews + chip row + caption.

  Expected assigns:
    * `:upload` — `%Phoenix.LiveView.UploadConfig{}` (required)
    * `:uploaded_photos` — list of already-saved photo maps
    * `:selected_car_part` — atom or nil
    * `:show_all_parts` — boolean, whether the full chip list is expanded
  """
  attr :upload, :any, required: true
  attr :uploaded_photos, :list, default: []
  attr :selected_car_part, :atom, default: nil
  attr :show_all_parts, :boolean, default: false

  def uploader(assigns) do
    ~H"""
    <div class="space-y-5">
      <.drop_zone upload={@upload} />

      <!-- In-flight entries with per-entry progress + cancel -->
      <div :if={@upload.entries != []} class="grid grid-cols-2 md:grid-cols-3 gap-3">
        <div :for={entry <- @upload.entries} class="relative">
          <.live_img_preview entry={entry} class="w-full aspect-square object-cover rounded-2xl shadow-sm" />
          <div class="absolute inset-x-2 bottom-2">
            <progress class="progress progress-primary w-full h-1.5" value={entry.progress} max="100" />
          </div>
          <button
            type="button"
            class="absolute top-2 right-2 btn btn-circle btn-xs bg-base-100 border border-base-300 text-base-content"
            phx-click="cancel_photo_upload"
            phx-value-ref={entry.ref}
            aria-label="Cancel upload"
          >
            ✕
          </button>
        </div>
      </div>

      <.preview_grid photos={@uploaded_photos} />

      <.car_part_chips selected={@selected_car_part} show_all={@show_all_parts} />

      <input
        type="text"
        name="caption"
        class="input input-bordered w-full"
        placeholder="Describe the issue (optional)"
      />
    </div>
    """
  end

  @doc """
  Big tap-target drop zone wrapping a `.live_file_input`. On mobile
  this opens the native picker with Camera / Photos / Files options.
  """
  attr :upload, :any, required: true

  def drop_zone(assigns) do
    ~H"""
    <label
      for={@upload.ref}
      phx-drop-target={@upload.ref}
      class="block w-full h-48 rounded-2xl border-2 border-dashed border-base-300 hover:border-primary transition-colors bg-base-200/50 hover:bg-base-200 cursor-pointer flex flex-col items-center justify-center gap-2 px-4 text-center"
    >
      <span class="text-4xl" aria-hidden="true">📷</span>
      <span class="font-semibold">Tap to add photo</span>
      <span class="text-sm text-base-content/80">or drag files here</span>
      <.live_file_input upload={@upload} class="sr-only" />
    </label>
    """
  end

  @doc """
  Simpler variant used where only the drop zone matters (e.g. tests,
  possibly future empty-state use).
  """
  def drop_zone_only(assigns) do
    # Component tests exercise this without needing an UploadConfig.
    ~H"""
    <div class="w-full h-48 rounded-2xl border-2 border-dashed border-base-300 flex flex-col items-center justify-center gap-2 px-4 text-center">
      <span class="text-4xl" aria-hidden="true">📷</span>
      <span class="font-semibold">Tap to add photo</span>
      <span class="text-sm text-base-content/80">or drag files here</span>
    </div>
    """
  end

  @doc """
  Grid of previously-uploaded photos. Each card carries a persistent
  corner delete button (not a tiny `×` in a detached list).
  """
  attr :photos, :list, default: []

  def preview_grid(assigns) do
    ~H"""
    <div :if={@photos != []} class="grid grid-cols-2 md:grid-cols-3 gap-3">
      <div :for={photo <- @photos} class="relative group">
        <img
          src={photo.file_path}
          class="w-full aspect-square object-cover rounded-2xl shadow-sm"
          alt={photo.caption || "Problem area photo"}
        />
        <button
          type="button"
          class="absolute top-2 right-2 btn btn-circle btn-sm bg-base-100 border border-base-300 text-error opacity-90 hover:opacity-100"
          phx-click="delete_uploaded_photo"
          phx-value-url={photo.file_path}
          aria-label="Delete photo"
        >
          🗑
        </button>
        <p :if={photo.caption} class="text-xs text-base-content/80 mt-1 truncate">
          {photo.caption}
        </p>
      </div>
    </div>
    """
  end

  @doc """
  Horizontal chip row for car-part tagging. Six common parts are
  always visible; tapping "More…" expands to the full list.
  """
  attr :selected, :atom, default: nil
  attr :show_all, :boolean, default: false

  def car_part_chips(assigns) do
    assigns =
      assign(assigns,
        common_parts: @common_parts,
        all_parts: @all_parts
      )

    ~H"""
    <div class="space-y-2">
      <span class="text-xs font-semibold uppercase tracking-wide text-base-content/70">
        Tag
      </span>
      <div class="flex flex-wrap gap-2">
        <button
          :for={{label, atom} <- (if @show_all, do: @all_parts, else: @common_parts)}
          type="button"
          class={[
            "btn btn-sm rounded-full",
            if(@selected == atom, do: "btn-primary", else: "btn-outline")
          ]}
          phx-click="select_car_part"
          phx-value-part={atom}
        >
          {label}
        </button>

        <button
          :if={!@show_all}
          type="button"
          class="btn btn-sm btn-ghost rounded-full"
          phx-click="toggle_all_parts"
        >
          More…
        </button>

        <button
          :if={@show_all}
          type="button"
          class="btn btn-sm btn-ghost rounded-full"
          phx-click="toggle_all_parts"
        >
          Less
        </button>
      </div>
    </div>
    """
  end
end
