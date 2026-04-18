defmodule MobileCarWashWeb.AppointmentsLive do
  @moduledoc """
  Customer's appointment list with status, photo upload, and real-time tracking links.
  """
  use MobileCarWashWeb, :live_view

  alias MobileCarWash.Scheduling.{Appointment, AppointmentTracker, ServiceType}
  alias MobileCarWash.Operations.PhotoUpload

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

    socket =
      socket
      |> assign(
        page_title: "My Appointments",
        appointments: appointments,
        service_types: service_types,
        loyalty_card: loyalty_card,
        uploading_for: nil
      )
      |> allow_upload(:problem_photo, accept: ~w(.jpg .jpeg .png .webp), max_entries: 3, max_file_size: 10_000_000)

    {:ok, socket}
  end

  @impl true
  def handle_event("show_upload", %{"id" => appointment_id}, socket) do
    # Verify appointment belongs to current customer
    owns? = Enum.any?(socket.assigns.appointments, &(&1.id == appointment_id))

    if owns? do
      {:noreply, assign(socket, uploading_for: appointment_id)}
    else
      {:noreply, put_flash(socket, :error, "Appointment not found")}
    end
  end

  def handle_event("cancel_upload", _params, socket) do
    {:noreply, assign(socket, uploading_for: nil)}
  end

  def handle_event("validate_upload", _params, socket), do: {:noreply, socket}

  def handle_event("save_problem_photos", %{"caption" => caption}, socket) do
    appointment_id = socket.assigns.uploading_for

    consume_uploaded_entries(socket, :problem_photo, fn %{path: path}, entry ->
      opts = [uploaded_by: :customer, caption: caption]

      case PhotoUpload.save_file(appointment_id, path, entry.client_name, :problem_area, opts) do
        {:ok, photo} -> {:ok, photo}
        {:error, reason} -> {:postpone, reason}
      end
    end)

    {:noreply,
     socket
     |> assign(uploading_for: nil)
     |> put_flash(:info, "Photos uploaded! The technician will see these.")}
  end

  @impl true
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

            <!-- Photo Upload Form -->
            <div :if={@uploading_for == appt.id} class="mt-4 bg-base-200 rounded-lg p-4">
              <h4 class="font-semibold text-sm mb-2">Upload Problem Area Photos</h4>
              <p class="text-xs text-base-content/80 mb-3">
                Show us areas that need extra attention. The technician will see these before starting.
              </p>
              <form phx-submit="save_problem_photos" phx-change="validate_upload">
                <.live_file_input upload={@uploads.problem_photo} class="file-input file-input-bordered w-full file-input-sm mb-2" />

                <div class="flex gap-2 overflow-x-auto mb-2">
                  <div :for={entry <- @uploads.problem_photo.entries} class="flex-shrink-0">
                    <.live_img_preview entry={entry} class="w-20 h-20 object-cover rounded" />
                  </div>
                </div>

                <input type="text" name="caption" placeholder="Describe the issue (optional)" class="input input-bordered input-sm w-full mb-2" />

                <div class="flex gap-2">
                  <button type="submit" class="btn btn-primary btn-sm">Upload</button>
                  <button type="button" class="btn btn-ghost btn-sm" phx-click="cancel_upload">Cancel</button>
                </div>
              </form>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

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
