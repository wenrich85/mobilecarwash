defmodule MobileCarWashWeb.AppointmentStatusLive do
  @moduledoc """
  Customer-facing real-time appointment tracking page.
  Shows step-by-step progress with time estimates as the technician works.
  Subscribes to PubSub — no polling, pure push.
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

        if connected?(socket) do
          AppointmentTracker.subscribe(appointment_id)
        end

        photos = Photo |> Ash.Query.filter(appointment_id == ^appointment_id) |> Ash.read!()
        problem_photos = Enum.filter(photos, &(&1.photo_type == :problem_area))
        before_photos = Enum.filter(photos, &(&1.photo_type == :before))
        after_photos = Enum.filter(photos, &(&1.photo_type == :after))

        # Load current checklist state from DB
        {items, steps_done, steps_total, eta_minutes, current_step} =
          load_checklist_state(appointment_id)

        {:ok,
         assign(socket,
           page_title: "Appointment Status",
           appointment: appointment,
           service_type: service_type,
           address: address,
           problem_photos: problem_photos,
           before_photos: before_photos,
           after_photos: after_photos,
           # Real-time state (loaded from DB, then updated via PubSub)
           live_status: if(appointment.status == :in_progress, do: :in_progress, else: nil),
           current_step: current_step,
           steps_done: steps_done,
           steps_total: steps_total,
           eta_minutes: eta_minutes,
           items: items,
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
       items: data[:items] || socket.assigns.items,
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

        <!-- Step-by-Step Progress (visible during wash) -->
        <div :if={@items != []} class="mb-6">
          <h3 class="font-semibold mb-3">Progress</h3>
          <div class="space-y-2">
            <div :for={item <- @items} class="flex items-center gap-3">
              <div class={[
                "w-6 h-6 rounded-full flex items-center justify-center text-xs font-bold",
                cond do
                  item.completed -> "bg-success text-success-content"
                  item.started_at -> "bg-warning text-warning-content animate-pulse"
                  true -> "bg-base-300 text-base-content/40"
                end
              ]}>
                <span :if={item.completed}>✓</span>
                <span :if={!item.completed}>{item.step_number}</span>
              </div>
              <div class="flex-1">
                <span class={[
                  "text-sm",
                  item.completed && "line-through text-base-content/50",
                  item.started_at && !item.completed && "font-semibold text-primary"
                ]}>
                  {item.title}
                </span>
              </div>
              <span :if={!item.completed && !item.started_at} class="text-xs text-base-content/40">
                ~{item.estimated_minutes || 5}m
              </span>
              <span :if={item.completed && item.actual_seconds} class="text-xs text-success">
                {format_seconds(item.actual_seconds)}
              </span>
              <span :if={item.started_at && !item.completed} class="text-xs text-warning animate-pulse">
                In progress...
              </span>
            </div>
          </div>

          <!-- Overall Progress Bar -->
          <div class="mt-4">
            <div class="flex justify-between text-xs text-base-content/50 mb-1">
              <span>{@steps_done}/{@steps_total} steps</span>
              <span :if={@eta_minutes}>~{@eta_minutes} min remaining</span>
            </div>
            <progress class="progress progress-primary w-full" value={@steps_done} max={@steps_total} />
          </div>
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
              <span class={["badge badge-sm", appointment_badge(@appointment.status)]}>
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
    photos = Photo |> Ash.Query.filter(appointment_id == ^appointment_id) |> Ash.read!()

    assign(socket,
      before_photos: Enum.filter(photos, &(&1.photo_type == :before)),
      after_photos: Enum.filter(photos, &(&1.photo_type == :after))
    )
  end

  defp format_seconds(seconds) when is_integer(seconds) do
    mins = div(seconds, 60)
    secs = rem(seconds, 60)
    "#{mins}:#{String.pad_leading("#{secs}", 2, "0")}"
  end

  defp format_seconds(_), do: ""

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

  defp appointment_badge(:pending), do: "badge-ghost"
  defp appointment_badge(:confirmed), do: "badge-info"
  defp appointment_badge(:in_progress), do: "badge-warning"
  defp appointment_badge(:completed), do: "badge-success"
  defp appointment_badge(:cancelled), do: "badge-error"
  defp appointment_badge(_), do: "badge-ghost"

  defp format_status(:pending), do: "Pending"
  defp format_status(:confirmed), do: "Confirmed"
  defp format_status(:in_progress), do: "In Progress"
  defp format_status(:completed), do: "Completed"
  defp format_status(:cancelled), do: "Cancelled"
  defp format_status(s), do: to_string(s)

  defp load_checklist_state(appointment_id) do
    alias MobileCarWash.Operations.{AppointmentChecklist, ChecklistItem}

    checklists =
      AppointmentChecklist
      |> Ash.Query.filter(appointment_id == ^appointment_id)
      |> Ash.read!()

    case checklists do
      [checklist | _] ->
        items =
          ChecklistItem
          |> Ash.Query.filter(checklist_id == ^checklist.id)
          |> Ash.Query.sort(step_number: :asc)
          |> Ash.read!()
          |> Enum.map(fn item ->
            %{
              step_number: item.step_number,
              title: item.title,
              completed: item.completed,
              estimated_minutes: item.estimated_minutes,
              started_at: item.started_at,
              actual_seconds: item.actual_seconds
            }
          end)

        total = length(items)
        done = Enum.count(items, & &1.completed)
        eta = items |> Enum.reject(& &1.completed) |> Enum.reduce(0, fn i, acc -> acc + (i.estimated_minutes || 5) end)

        active = Enum.find(items, &(&1.started_at && !&1.completed))
        next_pending = Enum.find(items, &(!&1.completed))
        current = (active || next_pending)
        current_name = if current, do: current.title, else: nil

        {items, done, total, eta, current_name}

      [] ->
        {[], 0, 0, nil, nil}
    end
  end
end
