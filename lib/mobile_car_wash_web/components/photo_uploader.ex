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
  Full uploader — action buttons + in-progress previews + chip row + caption.

  Expected assigns:
    * `:camera_upload` — `%UploadConfig{}` bound to a `capture="environment"`
      input so mobile tapping opens the rear camera directly.
    * `:library_upload` — `%UploadConfig{}` bound to a regular file input;
      also serves as the drag-and-drop target on desktop.
    * `:uploaded_photos` — list of already-saved photo maps.
    * `:selected_car_part` — atom or nil.
    * `:show_all_parts` — boolean, whether the full chip list is expanded.
  """
  attr :camera_upload, :any, required: true
  attr :library_upload, :any, required: true
  attr :uploaded_photos, :list, default: []
  attr :selected_car_part, :atom, default: nil
  attr :show_all_parts, :boolean, default: false
  attr :caption, :string, default: nil

  def uploader(assigns) do
    ~H"""
    <div class="space-y-5">
      <.action_buttons camera_upload={@camera_upload} library_upload={@library_upload} />

      <!-- In-flight entries across both inputs, shown in a single grid -->
      <div
        :if={@camera_upload.entries != [] or @library_upload.entries != []}
        class="grid grid-cols-2 md:grid-cols-3 gap-3"
      >
        <.entry_preview :for={entry <- @camera_upload.entries} entry={entry} source="camera" />
        <.entry_preview :for={entry <- @library_upload.entries} entry={entry} source="library" />
      </div>

      <.preview_grid photos={@uploaded_photos} />

      <.car_part_chips selected={@selected_car_part} show_all={@show_all_parts} />

      <!-- Value-bound so ✨ AI auto-fill populates the input directly. -->
      <input
        type="text"
        name="caption"
        value={@caption}
        class="input input-bordered w-full"
        placeholder="Describe the issue (optional)"
      />
    </div>
    """
  end

  @doc """
  Two stacked CTAs on mobile, side-by-side on desktop. The primary button
  fires the camera input (`capture="environment"` → opens the rear camera
  directly, no picker in between). The secondary button fires a plain
  file input which opens the library/file picker and also serves as the
  drag-and-drop target on desktop.
  """
  attr :camera_upload, :any, required: true
  attr :library_upload, :any, required: true

  def action_buttons(assigns) do
    ~H"""
    <div class="flex flex-col sm:flex-row gap-3">
      <!-- Take Photo (camera direct on mobile) -->
      <label
        for={@camera_upload.ref}
        class="btn btn-primary btn-lg flex-1 rounded-2xl gap-2 h-20"
      >
        <span class="text-2xl" aria-hidden="true">📷</span>
        <span class="flex flex-col items-start leading-tight">
          <span class="font-bold">Take Photo</span>
          <span class="text-xs font-normal opacity-80">Opens your camera</span>
        </span>
        <.live_file_input upload={@camera_upload} capture="environment" class="sr-only" />
      </label>

      <!-- Upload from library (also the desktop drag target) -->
      <label
        for={@library_upload.ref}
        phx-drop-target={@library_upload.ref}
        class="btn btn-outline btn-lg flex-1 rounded-2xl gap-2 h-20 border-dashed hover:border-solid"
      >
        <span class="text-2xl" aria-hidden="true">🖼️</span>
        <span class="flex flex-col items-start leading-tight">
          <span class="font-bold">Upload</span>
          <span class="text-xs font-normal opacity-80 hidden sm:inline">or drag from desktop</span>
          <span class="text-xs font-normal opacity-80 sm:hidden">Pick from library</span>
        </span>
        <.live_file_input upload={@library_upload} class="sr-only" />
      </label>
    </div>
    """
  end

  @doc """
  Big tap-target drop zone wrapping a `.live_file_input`. Kept for the
  one-config appointments-list modal; the full booking-flow uploader
  uses `action_buttons/1` instead.
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

  # In-flight preview with progress bar + cancel button. Source tag lets
  # the parent know which upload config to cancel against.
  attr :entry, :any, required: true
  attr :source, :string, required: true

  defp entry_preview(assigns) do
    ~H"""
    <div class="relative">
      <.live_img_preview entry={@entry} class="w-full aspect-square object-cover rounded-2xl shadow-sm" />
      <div class="absolute inset-x-2 bottom-2">
        <progress class="progress progress-primary w-full h-1.5" value={@entry.progress} max="100" />
      </div>
      <button
        type="button"
        class="absolute top-2 right-2 btn btn-circle btn-xs bg-base-100 border border-base-300 text-base-content"
        phx-click="cancel_photo_upload"
        phx-value-ref={@entry.ref}
        phx-value-source={@source}
        aria-label="Cancel upload"
      >
        ✕
      </button>
    </div>
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
  corner delete button (not a tiny `×` in a detached list) and an
  AI-state pill:
    * "Analyzing…" while the vision model is still running
    * "✨ Bumper · Scratch" once tags land (or nothing at all if the
      feature flag is off / photo isn't a vehicle).
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

        <.ai_pill photo={photo} />

        <p :if={photo.caption} class="text-xs text-base-content/80 mt-1 truncate">
          {photo.caption}
        </p>
      </div>
    </div>
    """
  end

  # AI-analysis pill shown in the bottom-left of each photo preview.
  # Only renders once tags have arrived AND the photo looks like a vehicle
  # with a classifiable body part. Feature-off / non-vehicle / low-confidence
  # cases render nothing — they shouldn't draw the customer's eye.
  attr :photo, :map, required: true

  defp ai_pill(%{photo: %{ai_tags: %{"is_vehicle_photo" => true} = tags}} = assigns)
       when is_map(tags) do
    assigns = assign(assigns, :summary, ai_summary(tags))

    ~H"""
    <span :if={@summary} class="absolute bottom-2 left-2 badge badge-sm badge-primary gap-1">
      ✨ {@summary}
    </span>
    """
  end

  defp ai_pill(assigns), do: ~H""

  defp ai_summary(%{"body_part" => part, "issue" => issue})
       when is_binary(part) and is_binary(issue) do
    "#{String.capitalize(issue)} · #{humanize_part(part)}"
  end

  defp ai_summary(%{"body_part" => part}) when is_binary(part) do
    humanize_part(part)
  end

  defp ai_summary(_), do: nil

  defp humanize_part(part) do
    part
    |> String.replace("_", " ")
    |> String.capitalize()
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
