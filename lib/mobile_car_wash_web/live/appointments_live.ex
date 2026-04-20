defmodule MobileCarWashWeb.AppointmentsLive do
  @moduledoc """
  Customer's appointment list with status, photo upload, and real-time tracking links.
  """
  use MobileCarWashWeb, :live_view

  alias MobileCarWash.Scheduling.{Appointment, AppointmentTracker, ServiceType}
  alias MobileCarWash.Operations.{Photo, PhotoUpload}

  require Ash.Query

  @impl true
  def mount(_params, _session, socket) do
    customer = socket.assigns.current_customer

    appointments =
      if customer do
        Appointment
        |> Ash.Query.filter(customer_id == ^customer.id)
        |> Ash.Query.sort(scheduled_at: :desc)
        |> Ash.read!()
      else
        []
      end

    if connected?(socket) do
      # New appointments (e.g. booked in another tab)
      AppointmentTracker.subscribe_to_new_appointments()
      # All non-cancelled appointments so status changes update in-place immediately
      for appt <- appointments, appt.status != :cancelled do
        AppointmentTracker.subscribe(appt.id)
      end
    end

    # Load service types for display
    service_types = Ash.read!(ServiceType) |> Map.new(&{&1.id, &1})

    loyalty_card =
      if customer do
        case MobileCarWash.Loyalty.get_or_create_card(customer.id) do
          {:ok, card} -> card
          _ -> nil
        end
      end

    share_link = if customer, do: MobileCarWash.Marketing.Referrals.share_link_for(customer), else: nil

    socket =
      socket
      |> assign(
        page_title: "My Appointments",
        appointments: appointments,
        service_types: service_types,
        loyalty_card: loyalty_card,
        share_link: share_link,
        uploading_for: nil,
        # Photo uploader state — scoped to whichever appointment's modal
        # is currently open. Reset on every show_upload.
        photo_caption: nil,
        selected_car_part: nil,
        show_all_parts: false,
        uploaded_photos: []
      )
      |> allow_upload(:problem_photo_camera,
        accept: ~w(.jpg .jpeg .png .webp),
        max_entries: 5,
        max_file_size: 10_000_000,
        auto_upload: true,
        progress: &handle_photo_progress/3
      )
      |> allow_upload(:problem_photo_library,
        accept: ~w(.jpg .jpeg .png .webp),
        max_entries: 5,
        max_file_size: 10_000_000,
        auto_upload: true,
        progress: &handle_photo_progress/3
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("show_upload", %{"id" => appointment_id}, socket) do
    # Verify appointment belongs to current customer
    owns? = Enum.any?(socket.assigns.appointments, &(&1.id == appointment_id))

    if owns? do
      photos = load_problem_photos(appointment_id)

      # Subscribe to every existing photo's AI channel so late-arriving
      # tags reach the modal even if the customer opened it before the
      # background analyzer finished.
      if connected?(socket) do
        Enum.each(photos, &MobileCarWash.AI.PhotoAnalyzer.subscribe(&1.id))
      end

      {:noreply,
       assign(socket,
         uploading_for: appointment_id,
         uploaded_photos: photos,
         photo_caption: nil,
         selected_car_part: nil,
         show_all_parts: false
       )}
    else
      {:noreply, put_flash(socket, :error, "Appointment not found")}
    end
  end

  def handle_event("close_upload_modal", _params, socket) do
    {:noreply, assign(socket, uploading_for: nil, uploaded_photos: [])}
  end

  def handle_event("validate_photos", params, socket) do
    {:noreply,
     assign(socket, photo_caption: params["caption"] || socket.assigns.photo_caption)}
  end

  def handle_event("cancel_photo_upload", %{"ref" => ref, "source" => source}, socket) do
    {:noreply, cancel_upload(socket, upload_name_for(source), ref)}
  end

  def handle_event("cancel_photo_upload", %{"ref" => ref}, socket) do
    {:noreply,
     socket
     |> cancel_upload(:problem_photo_camera, ref)
     |> cancel_upload(:problem_photo_library, ref)}
  end

  def handle_event("select_car_part", %{"part" => part_str}, socket) do
    atom = String.to_existing_atom(part_str)

    selected =
      if socket.assigns.selected_car_part == atom, do: nil, else: atom

    {:noreply, assign(socket, selected_car_part: selected)}
  end

  def handle_event("toggle_all_parts", _params, socket) do
    {:noreply, assign(socket, show_all_parts: !socket.assigns.show_all_parts)}
  end

  # Customer-initiated delete from the preview grid. Hard-deletes the
  # Photo record and its underlying file since it's already persisted.
  def handle_event("delete_uploaded_photo", %{"url" => url}, socket) do
    case Enum.find(socket.assigns.uploaded_photos, &(&1.file_path == url)) do
      nil ->
        {:noreply, socket}

      photo ->
        # Best-effort cleanup: drop the file first, then the record. If
        # the DB side fails we leave the file orphaned — still safer than
        # the inverse (dangling DB row pointing at a deleted file).
        _ = PhotoUpload.delete_file(photo)
        _ = photo |> Ash.destroy(authorize?: false)

        remaining = Enum.reject(socket.assigns.uploaded_photos, &(&1.file_path == url))
        {:noreply, assign(socket, uploaded_photos: remaining)}
    end
  end

  defp upload_name_for("camera"), do: :problem_photo_camera
  defp upload_name_for("library"), do: :problem_photo_library
  defp upload_name_for(_), do: :problem_photo_library

  defp handle_photo_progress(name, entry, socket)
       when name in [:problem_photo_camera, :problem_photo_library] do
    if entry.done? do
      appointment_id = socket.assigns.uploading_for
      caption = socket.assigns.photo_caption
      car_part = socket.assigns.selected_car_part

      photo =
        consume_uploaded_entry(socket, entry, fn %{path: path} ->
          opts =
            [uploaded_by: :customer, caption: caption]
            |> then(fn o -> if car_part, do: o ++ [car_part: car_part], else: o end)

          case PhotoUpload.save_file(
                 appointment_id,
                 path,
                 entry.client_name,
                 :problem_area,
                 opts
               ) do
            {:ok, photo} ->
              {:ok, PhotoUpload.apply_url(photo)}

            other ->
              other
          end
        end)

      # Subscribe to the photo's AI channel so the preview updates the
      # moment the background analyzer finishes.
      if connected?(socket) and photo.id do
        MobileCarWash.AI.PhotoAnalyzer.subscribe(photo.id)
      end

      {:noreply, update(socket, :uploaded_photos, &(&1 ++ [photo]))}
    else
      {:noreply, socket}
    end
  end

  # Loads already-uploaded problem-area photos for this appointment so
  # they're visible the moment the modal opens (e.g. the customer comes
  # back after a reload).
  defp load_problem_photos(appointment_id) do
    Photo
    |> Ash.Query.filter(appointment_id == ^appointment_id and photo_type == :problem_area)
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.read!()
    |> Enum.map(&PhotoUpload.apply_url/1)
  end

  # Auto-apply guards — only fill fields the customer hasn't already set.
  defp maybe_auto_apply_ai_tags(socket, %{ai_tags: %{"is_vehicle_photo" => true} = tags}) do
    socket
    |> maybe_assign_car_part(tags["body_part"])
    |> maybe_assign_caption(tags["description"])
  end

  defp maybe_auto_apply_ai_tags(socket, _), do: socket

  defp maybe_assign_car_part(socket, part_str) when is_binary(part_str) do
    if is_nil(socket.assigns.selected_car_part) do
      try do
        assign(socket, selected_car_part: String.to_existing_atom(part_str))
      rescue
        ArgumentError -> socket
      end
    else
      socket
    end
  end

  defp maybe_assign_car_part(socket, _), do: socket

  defp maybe_assign_caption(socket, text) when is_binary(text) and text != "" do
    current = socket.assigns.photo_caption

    if is_nil(current) or current == "" do
      assign(socket, photo_caption: text)
    else
      socket
    end
  end

  defp maybe_assign_caption(socket, _), do: socket

  @impl true
  # AI tags arrived for one of the photos in the open modal. Splice the
  # fresh tags into the existing photo struct so the ✨ badge renders and
  # optionally auto-apply the chip/caption if the customer hasn't set them.
  def handle_info({:ai_tags, photo}, socket) do
    updated_photos =
      Enum.map(socket.assigns.uploaded_photos, fn p ->
        if p.id == photo.id do
          Map.merge(p, %{ai_tags: photo.ai_tags, ai_processed_at: photo.ai_processed_at})
        else
          p
        end
      end)

    {:noreply,
     socket
     |> assign(uploaded_photos: updated_photos)
     |> maybe_auto_apply_ai_tags(photo)}
  end

  # Step progress — nothing to update in the list view, no-op
  def handle_info({:appointment_update, %{event: :step_update}}, socket) do
    {:noreply, socket}
  end

  # Photo uploaded — nothing to update in the list view, no-op
  def handle_info({:appointment_update, %{event: :photo_uploaded}}, socket) do
    {:noreply, socket}
  end

  # Status/assignment changes — reload just the one appointment in-place
  def handle_info({:appointment_update, %{appointment_id: id}}, socket) do
    case Ash.get(Appointment, id) do
      {:ok, updated} ->
        appointments = Enum.map(socket.assigns.appointments, fn a ->
          if a.id == updated.id, do: updated, else: a
        end)
        {:noreply, assign(socket, appointments: appointments)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_info({:new_appointment, _id}, socket) do
    {:noreply, reload_appointments(socket)}
  end

  defp reload_appointments(socket) do
    customer = socket.assigns.current_customer

    appointments =
      if customer do
        Appointment
        |> Ash.Query.filter(customer_id == ^customer.id)
        |> Ash.Query.sort(scheduled_at: :desc)
        |> Ash.read!()
      else
        []
      end

    assign(socket, appointments: appointments)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto py-8 px-4">
      <div class="flex justify-between items-center mb-6">
        <h1 class="text-3xl font-bold">My Appointments</h1>
        <.link navigate={~p"/account/recurring"} class="btn btn-outline btn-sm">
          Recurring Schedules
        </.link>
      </div>

      <!-- Loyalty Punch Card -->
      <div :if={@loyalty_card} class="card bg-base-100 shadow mb-6">
        <div class="card-body p-4">
          <% free = MobileCarWash.Loyalty.available_free_washes(@loyalty_card) %>
          <% punches = MobileCarWash.Loyalty.punches_in_cycle(@loyalty_card) %>
          <% total = MobileCarWash.Loyalty.punches_per_reward() %>

          <!-- Free wash available banner -->
          <div :if={free > 0} class="alert alert-success mb-3">
            <span class="font-semibold">
              🎁 You have {free} free wash{if free != 1, do: "es"} ready! Apply it at your next booking.
            </span>
          </div>

          <div class="flex items-center justify-between mb-2">
            <h3 class="font-semibold">Loyalty Card</h3>
            <span class="text-xs text-base-content/70">
              {if free > 0, do: "#{punches} punches toward next reward", else: "#{punches} / #{total} punches"}
            </span>
          </div>

          <!-- Punch slots: 2 rows of 5 -->
          <div class="grid grid-cols-5 gap-2">
            <div
              :for={n <- 1..total}
              class={[
                "aspect-square rounded-full border-2 flex items-center justify-center text-sm font-bold transition-all",
                n <= punches && "bg-primary border-primary text-primary-content" ||
                  "border-base-300 text-base-content/20"
              ]}
            >
              {if n <= punches, do: "✓", else: n}
            </div>
          </div>

          <p class="text-xs text-base-content/70 mt-2 text-center">
            {cond do
              free > 0 -> "#{total - punches} more punch#{if total - punches != 1, do: "es"} until your next free wash"
              punches == 0 -> "Every wash earns a punch — 10 punches = 1 free wash"
              true -> "#{total - punches} more punch#{if total - punches != 1, do: "es"} to earn a free wash"
            end}
          </p>
        </div>
      </div>

      <!-- Share & earn -->
      <div :if={@share_link && @current_customer} class="card bg-gradient-to-br from-primary/10 to-secondary/10 shadow mb-6">
        <div class="card-body p-4">
          <div class="flex items-start justify-between gap-3 flex-wrap">
            <div>
              <h3 class="font-semibold">🎁 Share &amp; earn</h3>
              <p class="text-sm text-base-content/80">
                Send a friend your referral link — they save on their first wash and you earn
                <span class="font-semibold">${MobileCarWash.Marketing.Referrals.default_reward_dollars()} in credit</span>
                when they book.
              </p>
            </div>
            <div class="text-right">
              <div class="text-xs text-base-content/70">Referral credit balance</div>
              <div class="text-2xl font-bold text-primary">
                ${dollars(@current_customer.referral_credit_cents)}
              </div>
            </div>
          </div>

          <div class="mt-3 join w-full">
            <input
              id="share-link"
              type="text"
              readonly
              value={@share_link}
              class="input input-bordered join-item flex-1 text-xs"
            />
            <button
              class="btn btn-primary join-item"
              phx-click={Phoenix.LiveView.JS.dispatch("phx:copy", to: "#share-link")}
            >
              Copy
            </button>
          </div>
        </div>
      </div>

      <div :if={@appointments == []} class="text-center py-12">
        <p class="text-base-content/70 mb-4">No appointments yet</p>
        <.link navigate={~p"/book"} class="btn btn-primary">Book a Wash</.link>
      </div>

      <div class="space-y-4">
        <div :for={appt <- @appointments} class="card bg-base-100 shadow">
          <div class="card-body p-4">
            <div class="flex justify-between items-start">
              <div>
                <h3 class="font-bold">{Map.get(@service_types, appt.service_type_id, %{name: "Service"}).name}</h3>
                <p class="text-sm text-base-content/80">
                  {Calendar.strftime(appt.scheduled_at, "%B %d, %Y at %I:%M %p")}
                </p>
              </div>
              <span class={["badge", status_class(appt.status)]}>
                {format_status(appt.status)}
              </span>
            </div>

            <div class="flex gap-2 mt-3">
              <!-- Real-time tracking -->
              <.link
                :if={appt.status in [:confirmed, :in_progress]}
                navigate={~p"/appointments/#{appt.id}/status"}
                class="btn btn-primary btn-sm"
              >
                Track Live
              </.link>

              <!-- Upload problem photos (before appointment starts) -->
              <button
                :if={appt.status in [:pending, :confirmed]}
                class="btn btn-outline btn-sm"
                phx-click="show_upload"
                phx-value-id={appt.id}
              >
                + Problem Area Photos
              </button>
            </div>

            <!-- Photo Upload Form — mobile-first uploader with dual
                 CTAs (camera and library) and auto-upload. -->
            <div :if={@uploading_for == appt.id} class="mt-4 bg-base-200 rounded-2xl p-4 space-y-4">
              <div class="flex justify-between items-start">
                <div>
                  <h4 class="font-bold">Problem Area Photos</h4>
                  <p class="text-xs text-base-content/80">
                    Show the tech what to focus on.
                  </p>
                </div>
                <button
                  type="button"
                  class="btn btn-ghost btn-sm btn-circle"
                  phx-click="close_upload_modal"
                  aria-label="Close"
                >
                  ✕
                </button>
              </div>

              <form phx-change="validate_photos" id={"photo-upload-form-#{appt.id}"}>
                <MobileCarWashWeb.PhotoUploader.uploader
                  camera_upload={@uploads.problem_photo_camera}
                  library_upload={@uploads.problem_photo_library}
                  uploaded_photos={@uploaded_photos}
                  selected_car_part={@selected_car_part}
                  show_all_parts={@show_all_parts}
                  caption={@photo_caption}
                />
              </form>

              <div class="flex justify-end">
                <button type="button" class="btn btn-primary btn-sm" phx-click="close_upload_modal">
                  Done
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp dollars(nil), do: "0.00"
  defp dollars(0), do: "0.00"

  defp dollars(cents) when is_integer(cents),
    do: :erlang.float_to_binary(cents / 100, decimals: 2)

  defp status_class(:pending), do: "badge-ghost"
  defp status_class(:confirmed), do: "badge-info"
  defp status_class(:in_progress), do: "badge-warning"
  defp status_class(:completed), do: "badge-success"
  defp status_class(:cancelled), do: "badge-error"
  defp status_class(_), do: "badge-ghost"

  defp format_status(:pending), do: "Pending"
  defp format_status(:confirmed), do: "Confirmed"
  defp format_status(:in_progress), do: "In Progress"
  defp format_status(:completed), do: "Completed"
  defp format_status(:cancelled), do: "Cancelled"
  defp format_status(s), do: to_string(s)
end
