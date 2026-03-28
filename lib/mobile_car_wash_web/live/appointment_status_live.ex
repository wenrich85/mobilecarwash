defmodule MobileCarWashWeb.AppointmentStatusLive do
  @moduledoc """
  Customer-facing real-time appointment tracking page.
  Subscribes to PubSub and shows live progress as the technician
  works through the checklist. No polling — pure push updates.
  """
  use MobileCarWashWeb, :live_view

  alias MobileCarWash.Scheduling.{Appointment, AppointmentTracker, ServiceType}
  alias MobileCarWash.Operations.Photo
  alias MobileCarWash.Fleet.Address

  require Ash.Query

  @impl true
  def mount(%{"id" => appointment_id}, _session, socket) do
    case Ash.get(Appointment, appointment_id) do
      {:ok, appointment} ->
        service_type = Ash.get!(ServiceType, appointment.service_type_id)
        address = Ash.get!(Address, appointment.address_id)

        # Subscribe to real-time updates
        if connected?(socket) do
          AppointmentTracker.subscribe(appointment_id)
        end

        # Load photos
        photos = Ash.read!(Photo, action: :for_appointment, arguments: %{appointment_id: appointment_id})
        problem_photos = Enum.filter(photos, &(&1.photo_type == :problem_area))
        before_photos = Enum.filter(photos, &(&1.photo_type == :before))
        after_photos = Enum.filter(photos, &(&1.photo_type == :after))

        {:ok,
         assign(socket,
           page_title: "Appointment Status",
           appointment: appointment,
           service_type: service_type,
           address: address,
           problem_photos: problem_photos,
           before_photos: before_photos,
           after_photos: after_photos,
           live_status: nil,
           current_step: nil,
           steps_done: 0,
           steps_total: 0,
           eta_minutes: nil,
           message: status_message(appointment.status)
         )}

      {:error, _} ->
        {:ok,
         socket
         |> assign(page_title: "Not Found", appointment: nil)
         |> put_flash(:error, "Appointment not found")}
    end
  end

  @impl true
  def handle_info({:appointment_update, data}, socket) do
    # Reload photos on photo events
    socket =
      if data[:event] == :photo_uploaded do
        reload_photos(socket)
      else
        socket
      end

    {:noreply,
     assign(socket,
       live_status: data[:status],
       current_step: data[:current_step],
       steps_done: data[:steps_done] || socket.assigns.steps_done,
       steps_total: data[:steps_total] || socket.assigns.steps_total,
       eta_minutes: data[:eta_minutes],
       message: data[:message] || socket.assigns.message
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-lg mx-auto py-8 px-4">
      <div :if={@appointment}>
        <h1 class="text-2xl font-bold mb-2">Appointment Status</h1>
        <p class="text-base-content/60 mb-6">
          {@service_type.name} · {Calendar.strftime(@appointment.scheduled_at, "%B %d at %I:%M %p")}
        </p>

        <!-- Status Banner -->
        <div class={["alert mb-6", status_alert_class(@appointment.status, @live_status)]}>
          <div>
            <div class="text-lg font-bold">{@message}</div>
            <div :if={@eta_minutes && @eta_minutes > 0} class="text-sm mt-1">
              Estimated time remaining: ~{@eta_minutes} minutes
            </div>
          </div>
        </div>

        <!-- Progress Bar (during wash) -->
        <div :if={@steps_total > 0} class="mb-6">
          <div class="flex justify-between text-sm mb-1">
            <span>Progress</span>
            <span>{@steps_done}/{@steps_total} steps</span>
          </div>
          <progress
            class="progress progress-primary w-full"
            value={@steps_done}
            max={@steps_total}
          />
          <p :if={@current_step} class="text-sm text-primary mt-2 font-medium">
            Currently: {@current_step}
          </p>
        </div>

        <!-- Before/After Photos -->
        <div :if={@before_photos != [] or @after_photos != []} class="mb-6">
          <h3 class="font-semibold mb-3">Photos</h3>
          <div class="grid grid-cols-2 gap-4">
            <div :if={@before_photos != []}>
              <h4 class="text-sm text-base-content/60 mb-1">Before</h4>
              <div :for={photo <- @before_photos}>
                <img src={photo.file_path} class="w-full rounded-lg shadow" />
              </div>
            </div>
            <div :if={@after_photos != []}>
              <h4 class="text-sm text-base-content/60 mb-1">After</h4>
              <div :for={photo <- @after_photos}>
                <img src={photo.file_path} class="w-full rounded-lg shadow" />
              </div>
            </div>
          </div>
        </div>

        <!-- Customer Problem Photos -->
        <div :if={@problem_photos != []} class="mb-6">
          <h3 class="font-semibold mb-2">Your Problem Areas</h3>
          <div class="flex gap-2 overflow-x-auto">
            <div :for={photo <- @problem_photos} class="flex-shrink-0">
              <img src={photo.file_path} class="w-24 h-24 object-cover rounded-lg" />
              <p :if={photo.caption} class="text-xs text-center mt-1">{photo.caption}</p>
            </div>
          </div>
        </div>

        <!-- Appointment Details -->
        <div class="card bg-base-100 shadow">
          <div class="card-body p-4 space-y-2 text-sm">
            <div><span class="font-semibold">Service:</span> {@service_type.name}</div>
            <div><span class="font-semibold">Location:</span> {@address.street}, {@address.city}</div>
            <div><span class="font-semibold">Duration:</span> ~{@service_type.duration_minutes} min</div>
            <div><span class="font-semibold">Status:</span>
              <span class={["badge badge-sm", appointment_status_class(@appointment.status)]}>
                {format_status(@appointment.status)}
              </span>
            </div>
          </div>
        </div>
      </div>

      <div :if={!@appointment} class="text-center py-12">
        <p class="text-base-content/50">Appointment not found</p>
        <.link navigate={~p"/"} class="btn btn-primary mt-4">Back to Home</.link>
      </div>
    </div>
    """
  end

  defp reload_photos(socket) do
    appointment_id = socket.assigns.appointment.id
    photos = Ash.read!(Photo, action: :for_appointment, arguments: %{appointment_id: appointment_id})

    assign(socket,
      before_photos: Enum.filter(photos, &(&1.photo_type == :before)),
      after_photos: Enum.filter(photos, &(&1.photo_type == :after))
    )
  end

  defp status_message(:pending), do: "Appointment scheduled"
  defp status_message(:confirmed), do: "Appointment confirmed — we'll be there!"
  defp status_message(:in_progress), do: "Wash in progress..."
  defp status_message(:completed), do: "Your wash is complete!"
  defp status_message(:cancelled), do: "Appointment cancelled"
  defp status_message(_), do: "Unknown status"

  defp status_alert_class(_, :completed), do: "alert-success"
  defp status_alert_class(_, :in_progress), do: "alert-info"
  defp status_alert_class(:confirmed, _), do: "alert-info"
  defp status_alert_class(:completed, _), do: "alert-success"
  defp status_alert_class(:cancelled, _), do: "alert-error"
  defp status_alert_class(_, _), do: ""

  defp appointment_status_class(:pending), do: "badge-ghost"
  defp appointment_status_class(:confirmed), do: "badge-info"
  defp appointment_status_class(:in_progress), do: "badge-warning"
  defp appointment_status_class(:completed), do: "badge-success"
  defp appointment_status_class(:cancelled), do: "badge-error"
  defp appointment_status_class(_), do: "badge-ghost"

  defp format_status(:not_started), do: "Not Started"
  defp format_status(:in_progress), do: "In Progress"
  defp format_status(:completed), do: "Completed"
  defp format_status(:pending), do: "Pending"
  defp format_status(:confirmed), do: "Confirmed"
  defp format_status(:cancelled), do: "Cancelled"
  defp format_status(s), do: to_string(s)
end
