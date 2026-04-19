defmodule MobileCarWashWeb.AppointmentStatusLive do
  @moduledoc """
  Customer-facing real-time appointment tracking page.
  Shows step-by-step progress with time estimates as the technician works.
  Subscribes to PubSub — no polling, pure push.
  """
  use MobileCarWashWeb, :live_view

  alias MobileCarWash.Scheduling.{Appointment, AppointmentTracker, ServiceType}
  alias MobileCarWash.Operations.{Photo, PhotoUpload}
  alias MobileCarWash.Fleet.Address

  require Ash.Query

  @key_areas [
    %{id: :front,           label: "Front"},
    %{id: :rear,            label: "Rear"},
    %{id: :driver_side,     label: "Driver Side"},
    %{id: :passenger_side,  label: "Passenger Side"},
    %{id: :interior,        label: "Interior"},
    %{id: :wheels,          label: "Wheels"}
  ]

  @impl true
  def mount(%{"id" => appointment_id}, _session, socket) do
    customer = socket.assigns.current_customer

    case Ash.get(Appointment, appointment_id) do
      {:ok, appointment} when appointment.customer_id == customer.id ->
        service_type = Ash.get!(ServiceType, appointment.service_type_id)
        address = Ash.get!(Address, appointment.address_id)

        if connected?(socket) do
          AppointmentTracker.subscribe(appointment_id)
        end

        photos =
          Photo
          |> Ash.Query.filter(appointment_id == ^appointment_id)
          |> Ash.read!()
          |> Enum.map(&PhotoUpload.apply_url/1)

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
           key_areas: @key_areas,
           # Real-time state (loaded from DB, then updated via PubSub)
           live_status: if(appointment.status == :in_progress, do: :in_progress, else: nil),
           current_step: current_step,
           steps_done: steps_done,
           steps_total: steps_total,
           eta_minutes: eta_minutes,
           items: items,
           message: status_message(appointment.status)
         )}

      _ ->
        {:ok,
         socket
         |> assign(page_title: "Not Found", appointment: nil)
         |> put_flash(:error, "Appointment not found")}
    end
  end

  @impl true
  def handle_info({:appointment_update, data}, socket) do
    socket =
      case data[:event] do
        :photo_uploaded ->
          reload_photos(socket)

        :started ->
          # Wash just started — load checklist from DB so progress appears immediately
          {items, steps_done, steps_total, eta_minutes, current_step} =
            load_checklist_state(socket.assigns.appointment.id)

          # Also reload the appointment to get updated status
          {:ok, appointment} = Ash.get(Appointment, socket.assigns.appointment.id)

          assign(socket,
            appointment: appointment,
            items: items,
            steps_done: steps_done,
            steps_total: steps_total,
            eta_minutes: eta_minutes,
            current_step: current_step
          )

        :completed ->
          # Wash finished — reload appointment and photos
          {:ok, appointment} = Ash.get(Appointment, socket.assigns.appointment.id)
          reload_photos(assign(socket, appointment: appointment))

        _ ->
          socket
      end

    {:noreply,
     assign(socket,
       live_status: data[:status],
       current_step: data[:current_step] || socket.assigns.current_step,
       steps_done: data[:steps_done] || socket.assigns.steps_done,
       steps_total: data[:steps_total] || socket.assigns.steps_total,
       eta_minutes: data[:eta_minutes],
       items: data[:items] || socket.assigns.items,
       message: data[:message] || socket.assigns.message
     )}
  end

  @impl true
  def handle_event("cancel_appointment", _params, socket) do
    appointment = socket.assigns.appointment
    customer = socket.assigns.current_customer

    cond do
      appointment.customer_id != customer.id ->
        {:noreply, put_flash(socket, :error, "Not authorized to cancel this appointment.")}

      appointment.status not in [:pending, :confirmed, :en_route] ->
        {:noreply,
         put_flash(socket, :error, "This appointment can no longer be cancelled.")}

      true ->
        case appointment
             |> Ash.Changeset.for_update(:cancel, %{cancellation_reason: "Customer requested"})
             |> Ash.update(actor: customer) do
          {:ok, cancelled} ->
            {:noreply,
             socket
             |> assign(
               appointment: cancelled,
               live_status: nil,
               message: status_message(:cancelled)
             )
             |> put_flash(:info, "Appointment cancelled. You should receive a confirmation shortly.")}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, "Could not cancel — please try again.")}
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-lg mx-auto py-8 px-4">
      <div :if={@appointment}>
        <h1 class="text-2xl font-bold mb-2">Appointment Status</h1>
        <p class="text-base-content/80 mb-6">
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
                  true -> "bg-base-300 text-base-content/70"
                end
              ]}>
                <span :if={item.completed}>✓</span>
                <span :if={!item.completed}>{item.step_number}</span>
              </div>
              <div class="flex-1">
                <span class={[
                  "text-sm",
                  item.completed && "line-through text-base-content/70",
                  item.started_at && !item.completed && "font-semibold text-primary"
                ]}>
                  {item.title}
                </span>
              </div>
              <span :if={!item.completed && !item.started_at} class="text-xs text-base-content/70">
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
            <div class="flex justify-between text-xs text-base-content/70 mb-1">
              <span>{@steps_done}/{@steps_total} steps</span>
              <span :if={@eta_minutes}>~{@eta_minutes} min remaining</span>
            </div>
            <progress class="progress progress-primary w-full" value={@steps_done} max={@steps_total} />
          </div>
        </div>

        <!-- Before/After Photos (live) -->
        <div :if={@live_status == :in_progress or @before_photos != [] or @after_photos != []} class="mb-6">
          <div class="flex items-center gap-2 mb-3">
            <h3 class="font-semibold">Photos</h3>
            <span :if={@live_status == :in_progress} class="flex items-center gap-1 text-xs text-error font-medium">
              <span class="w-2 h-2 rounded-full bg-error inline-block animate-pulse"></span> Live
            </span>
          </div>

          <!-- Column headers -->
          <div class="grid grid-cols-2 gap-2 mb-1 px-1">
            <span class="text-xs text-base-content/70 text-center">Before</span>
            <span class="text-xs text-base-content/70 text-center">After</span>
          </div>

          <div class="space-y-2">
            <div :for={area <- @key_areas}>
              <% before_p = Enum.find(@before_photos, &(&1.car_part == area.id)) %>
              <% after_p  = Enum.find(@after_photos,  &(&1.car_part == area.id)) %>
              <div :if={before_p || after_p || @live_status == :in_progress}>
                <p class="text-xs text-base-content/70 mb-1">{area.label}</p>
                <div class="grid grid-cols-2 gap-2">
                  <!-- Before cell -->
                  <div class="aspect-[4/3] rounded-xl overflow-hidden bg-base-200">
                    <img :if={before_p} src={before_p.file_path} class="w-full h-full object-cover" />
                    <div :if={!before_p} class="w-full h-full flex items-center justify-center">
                      <span class="text-base-content/20 text-2xl">○</span>
                    </div>
                  </div>
                  <!-- After cell -->
                  <div class="aspect-[4/3] rounded-xl overflow-hidden bg-base-200">
                    <img :if={after_p} src={after_p.file_path} class="w-full h-full object-cover" />
                    <div :if={!after_p && before_p} class="w-full h-full flex items-center justify-center">
                      <span class="text-base-content/20 text-2xl animate-pulse">⋯</span>
                    </div>
                    <div :if={!after_p && !before_p} class="w-full h-full flex items-center justify-center">
                      <span class="text-base-content/20 text-2xl">○</span>
                    </div>
                  </div>
                </div>
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

        <div :if={@appointment.status in [:pending, :confirmed, :en_route]} class="mt-4">
          <button
            type="button"
            phx-click="cancel_appointment"
            data-confirm="Cancel this booking? This cannot be undone."
            class="btn btn-outline btn-error btn-sm w-full"
          >
            Cancel booking
          </button>
        </div>
      </div>

      <div :if={!@appointment} class="text-center py-12">
        <p class="text-base-content/70">Appointment not found</p>
        <.link navigate={~p"/"} class="btn btn-primary mt-4">Back to Home</.link>
      </div>
    </div>
    """
  end

  defp reload_photos(socket) do
    appointment_id = socket.assigns.appointment.id

    photos =
      Photo
      |> Ash.Query.filter(appointment_id == ^appointment_id)
      |> Ash.read!()
      |> Enum.map(&PhotoUpload.apply_url/1)

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
  defp status_message(:en_route), do: "Your tech is on the way!"
  defp status_message(:on_site), do: "Your tech has arrived"
  defp status_message(:in_progress), do: "Wash in progress..."
  defp status_message(:completed), do: "Your wash is complete!"
  defp status_message(:cancelled), do: "Appointment cancelled"
  defp status_message(_), do: "Unknown status"

  defp status_alert_class(_, :completed), do: "alert-success"
  defp status_alert_class(_, :in_progress), do: "alert-info"
  defp status_alert_class(:on_site, _), do: "alert-info"
  defp status_alert_class(:en_route, _), do: "alert-info"
  defp status_alert_class(:confirmed, _), do: "alert-info"
  defp status_alert_class(:completed, _), do: "alert-success"
  defp status_alert_class(:cancelled, _), do: "alert-error"
  defp status_alert_class(_, _), do: ""

  defp appointment_badge(:pending), do: "badge-ghost"
  defp appointment_badge(:confirmed), do: "badge-info"
  defp appointment_badge(:en_route), do: "badge-info"
  defp appointment_badge(:on_site), do: "badge-info"
  defp appointment_badge(:in_progress), do: "badge-warning"
  defp appointment_badge(:completed), do: "badge-success"
  defp appointment_badge(:cancelled), do: "badge-error"
  defp appointment_badge(_), do: "badge-ghost"

  defp format_status(:pending), do: "Pending"
  defp format_status(:confirmed), do: "Confirmed"
  defp format_status(:en_route), do: "En Route"
  defp format_status(:on_site), do: "On Site"
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
