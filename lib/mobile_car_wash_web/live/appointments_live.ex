defmodule MobileCarWashWeb.AppointmentsLive do
  @moduledoc """
  Customer's appointment list with status, photo upload, and real-time tracking links.
  """
  use MobileCarWashWeb, :live_view

  alias MobileCarWash.Scheduling.{Appointment, ServiceType}
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

    # Load service types for display
    service_types = Ash.read!(ServiceType) |> Map.new(&{&1.id, &1})

    socket =
      socket
      |> assign(
        page_title: "My Appointments",
        appointments: appointments,
        service_types: service_types,
        uploading_for: nil
      )
      |> allow_upload(:problem_photo, accept: ~w(.jpg .jpeg .png .webp), max_entries: 3, max_file_size: 10_000_000)

    {:ok, socket}
  end

  @impl true
  def handle_event("show_upload", %{"id" => appointment_id}, socket) do
    {:noreply, assign(socket, uploading_for: appointment_id)}
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
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto py-8 px-4">
      <h1 class="text-3xl font-bold mb-6">My Appointments</h1>

      <div :if={@appointments == []} class="text-center py-12">
        <p class="text-base-content/50 mb-4">No appointments yet</p>
        <.link navigate={~p"/book"} class="btn btn-primary">Book a Wash</.link>
      </div>

      <div class="space-y-4">
        <div :for={appt <- @appointments} class="card bg-base-100 shadow">
          <div class="card-body p-4">
            <div class="flex justify-between items-start">
              <div>
                <h3 class="font-bold">{Map.get(@service_types, appt.service_type_id, %{name: "Service"}).name}</h3>
                <p class="text-sm text-base-content/60">
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
              <p class="text-xs text-base-content/60 mb-3">
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
