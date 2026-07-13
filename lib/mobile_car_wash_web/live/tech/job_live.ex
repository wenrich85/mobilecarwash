defmodule MobileCarWashWeb.Tech.JobLive do
  @moduledoc """
  Technician job brief with the next action for a single assigned appointment.
  """
  use MobileCarWashWeb, :live_view

  import MobileCarWashWeb.Lightbox, only: [lightbox_root: 1]

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Fleet.{Address, Vehicle}
  alias MobileCarWash.Operations.{Photo, PhotoUpload, Technician}

  alias MobileCarWash.Scheduling.{
    Appointment,
    AppointmentTracker,
    Dispatch,
    ServiceType,
    WashOrchestrator
  }

  require Ash.Query

  @impl true
  def mount(%{"id" => appointment_id}, _session, socket) do
    case load_job(socket.assigns.current_customer, appointment_id) do
      {:ok, job} ->
        if connected?(socket) do
          AppointmentTracker.subscribe(job.appointment.id)
        end

        {:ok,
         socket
         |> assign(:page_title, "Job Brief")
         |> assign_job(job), layout: false}

      {:error, :not_found} ->
        {:ok, deny_access(socket, "Job not found."), layout: false}

      {:error, :forbidden} ->
        {:ok, deny_access(socket, "That job is not assigned to you."), layout: false}
    end
  end

  @impl true
  def handle_info({:appointment_update, _payload}, socket) do
    case load_job(socket.assigns.current_customer, socket.assigns.appointment.id) do
      {:ok, job} -> {:noreply, assign_job(socket, job)}
      {:error, _reason} -> {:noreply, deny_access(socket, "That job is no longer available.")}
    end
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def handle_event("depart", _params, socket) do
    with_authorized_job(socket, fn socket, %{appointment: appointment} ->
      transition_job(socket, appointment, :depart)
    end)
  end

  def handle_event("arrive", _params, socket) do
    with_authorized_job(socket, fn socket, %{appointment: appointment} ->
      transition_job(socket, appointment, :arrive)
    end)
  end

  def handle_event("start_wash", _params, socket) do
    with_authorized_job(socket, fn socket, %{appointment: appointment} ->
      case WashOrchestrator.start_wash(appointment.id) do
        {:ok, checklist} ->
          {:noreply, push_navigate(socket, to: ~p"/tech/checklist/#{checklist.id}")}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Could not start wash: #{inspect(reason)}")}
      end
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_customer}>
      <main
        id="tech-job-brief"
        class="mx-auto flex min-h-screen max-w-4xl flex-col gap-6 px-4 py-6 sm:px-6 lg:px-8"
      >
        <section class="overflow-hidden rounded-2xl border border-base-300 bg-base-100 shadow-sm">
          <div class="border-b border-base-300 bg-base-200/60 px-5 py-4 sm:px-6">
            <.link
              navigate={~p"/tech"}
              class="inline-flex items-center gap-2 text-sm font-medium text-base-content/70 transition hover:text-base-content"
            >
              <.icon name="hero-arrow-left" class="h-4 w-4" /> Back to schedule
            </.link>
            <div class="mt-4 flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
              <div class="space-y-2">
                <span class={["badge badge-sm", status_class(@appointment.status)]}>
                  {format_status(@appointment.status)}
                </span>
                <div>
                  <h1 class="text-2xl font-semibold tracking-tight text-base-content sm:text-3xl">
                    {@customer.name}
                  </h1>
                  <p class="mt-1 text-sm text-base-content/70 sm:text-base">
                    {@service.name} · {Calendar.strftime(
                      @appointment.scheduled_at,
                      "%b %d · %I:%M %p"
                    )}
                  </p>
                  <a
                    id="job-header-address"
                    href={maps_url(@address)}
                    target="_blank"
                    rel="noopener"
                    class="inline-flex items-center gap-1.5 text-sm font-medium text-primary transition hover:text-primary/80"
                  >
                    <.icon name="hero-map-pin" class="h-4 w-4 shrink-0" />
                    <span>{@address.street}, {@address.city}, {@address.state} {@address.zip}</span>
                  </a>
                </div>
              </div>

              <div class="sm:min-w-72">
                <div
                  id="job-command-card"
                  class="rounded-xl border border-base-300 bg-base-100 px-4 py-4 text-sm shadow-sm"
                >
                  <p class="text-xs font-semibold uppercase tracking-[0.16em] text-base-content/45">
                    Next action
                  </p>
                  <p class="mt-2 text-base font-semibold text-base-content">{@command.title}</p>
                  <p class="mt-1 text-sm leading-6 text-base-content/70">{@command.body}</p>

                  <button
                    :if={@command.action && @command.action.type == :event}
                    id={@command.action.id}
                    data-role="job-primary-action"
                    phx-click={@command.action.event}
                    class="btn btn-primary mt-4 w-full"
                  >
                    {@command.action.label}
                  </button>

                  <.link
                    :if={@command.action && @command.action.type == :link}
                    id={@command.action.id}
                    data-role="job-primary-action"
                    navigate={@command.action.to}
                    class="btn btn-primary mt-4 w-full"
                  >
                    {@command.action.label}
                  </.link>

                  <div
                    :if={is_nil(@command.action)}
                    id="job-primary-waiting"
                    class="mt-4 rounded-lg border border-dashed border-base-300 bg-base-200/50 px-3 py-2 text-sm text-base-content/70"
                  >
                    No field action available.
                  </div>
                </div>

                <div :if={@progress.steps_total > 0} class="mt-4 space-y-2">
                  <div class="flex items-center justify-between text-sm text-base-content/70">
                    <span>Checklist progress</span>
                    <span>{@progress.steps_done}/{@progress.steps_total}</span>
                  </div>
                  <progress
                    class="progress progress-primary h-2 w-full"
                    value={@progress.steps_done}
                    max={@progress.steps_total}
                  />
                </div>
              </div>
            </div>
          </div>

          <section id="job-prep-cards" class="grid gap-3 px-5 py-5 sm:px-6 lg:grid-cols-2">
            <article
              id="job-service-card"
              class="rounded-xl border border-base-300 bg-base-100 p-4 shadow-sm"
            >
              <p class="text-xs font-semibold uppercase tracking-[0.16em] text-base-content/45">
                Service
              </p>
              <p class="mt-2 text-sm font-semibold text-base-content">{@service.name}</p>
              <p class="mt-1 text-sm text-base-content/70">
                {Calendar.strftime(@appointment.scheduled_at, "%b %d · %I:%M %p")}
              </p>
            </article>

            <article
              id="job-vehicle-card"
              class="rounded-xl border border-base-300 bg-base-100 p-4 shadow-sm"
            >
              <p class="text-xs font-semibold uppercase tracking-[0.16em] text-base-content/45">
                Vehicle
              </p>
              <p class="mt-2 text-sm font-semibold text-base-content">{vehicle_label(@vehicle)}</p>
            </article>

            <article
              id="job-address-card"
              class="rounded-xl border border-base-300 bg-base-100 p-4 shadow-sm"
            >
              <p class="text-xs font-semibold uppercase tracking-[0.16em] text-base-content/45">
                Address
              </p>
              <a
                href={maps_url(@address)}
                target="_blank"
                rel="noopener"
                class="mt-2 inline-flex items-start gap-2 text-sm font-semibold text-primary transition hover:text-primary/80"
              >
                <.icon name="hero-map-pin" class="mt-0.5 h-4 w-4 shrink-0" />
                <span>{@address.street}, {@address.city}, {@address.state} {@address.zip}</span>
              </a>
            </article>

            <article
              id="job-customer-card"
              class="rounded-xl border border-base-300 bg-base-100 p-4 shadow-sm"
            >
              <p class="text-xs font-semibold uppercase tracking-[0.16em] text-base-content/45">
                Customer
              </p>
              <p class="mt-2 text-sm font-semibold text-base-content">{@customer.name}</p>
              <p class="mt-1 text-sm text-base-content/70">{customer_contact_label(@customer)}</p>
            </article>

            <article
              id="job-notes-card"
              class="rounded-xl border border-base-300 bg-base-100 p-4 shadow-sm lg:col-span-2"
            >
              <p class="text-xs font-semibold uppercase tracking-[0.16em] text-base-content/45">
                Appointment notes
              </p>
              <p class="mt-2 text-sm leading-6 text-base-content/80">{notes_text(@appointment)}</p>
            </article>
          </section>

          <section
            id="job-problem-photos"
            class="border-t border-base-300 px-5 py-5 sm:px-6"
          >
            <div class="flex items-center justify-between gap-3">
              <div>
                <h2 class="text-sm font-semibold uppercase tracking-[0.18em] text-base-content/50">
                  Customer problem photos
                </h2>
                <p class="mt-1 text-sm text-base-content/70">
                  Review these before starting the wash.
                </p>
              </div>
              <span class="badge badge-ghost">{length(@problem_photos)}</span>
            </div>

            <div
              :if={@problem_photos == []}
              id="job-problem-photo-empty"
              class="mt-4 rounded-xl border border-dashed border-base-300 bg-base-200/50 px-4 py-5 text-sm text-base-content/70"
            >
              No customer problem photos.
            </div>

            <div :if={@problem_photos != []} class="mt-4 grid grid-cols-2 gap-3 sm:grid-cols-3">
              <figure
                :for={photo <- @problem_photos}
                id={"job-problem-photo-#{photo.id}"}
                class="overflow-hidden rounded-xl border border-base-300 bg-base-100"
              >
                <img
                  src={photo.file_path}
                  alt={problem_photo_label(photo)}
                  data-lightbox="problem-photos"
                  data-lightbox-caption={photo.caption}
                  class="aspect-square w-full object-cover cursor-zoom-in"
                />
                <figcaption class="space-y-1 px-3 py-2">
                  <p class="text-xs font-semibold text-base-content">
                    {photo_car_part_label(photo.car_part)}
                  </p>
                  <p class="line-clamp-2 text-xs text-base-content/70">
                    {problem_photo_label(photo)}
                  </p>
                </figcaption>
              </figure>
            </div>
          </section>
        </section>
      </main>

      <.lightbox_root />
    </Layouts.app>
    """
  end

  defp transition_job(socket, appointment, action) do
    case appointment
         |> Ash.Changeset.for_update(action, %{})
         |> Ash.update(authorize?: false) do
      {:ok, _updated} ->
        case load_job(socket.assigns.current_customer, socket.assigns.appointment.id) do
          {:ok, job} -> {:noreply, assign_job(socket, job)}
          {:error, _reason} -> {:noreply, deny_access(socket, "That job is no longer available.")}
        end

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not update appointment.")}
    end
  end

  defp with_authorized_job(socket, callback) do
    case load_job(socket.assigns.current_customer, socket.assigns.appointment.id) do
      {:ok, job} -> callback.(socket, job)
      {:error, _reason} -> {:noreply, deny_access(socket, "That job is no longer available.")}
    end
  end

  defp load_job(current_customer, appointment_id) do
    with {:ok, appointment} <- Ash.get(Appointment, appointment_id, authorize?: false),
         {:ok, tech_record} <- authorize_job_access(current_customer, appointment),
         {:ok, customer} <- Ash.get(Customer, appointment.customer_id, authorize?: false),
         {:ok, service} <- Ash.get(ServiceType, appointment.service_type_id, authorize?: false),
         {:ok, address} <- Ash.get(Address, appointment.address_id, authorize?: false),
         {:ok, vehicle} <- Ash.get(Vehicle, appointment.vehicle_id, authorize?: false) do
      {:ok,
       %{
         appointment: appointment,
         tech_record: tech_record,
         customer: customer,
         service: service,
         address: address,
         vehicle: vehicle,
         progress: Dispatch.checklist_progress(appointment.id),
         problem_photos: load_problem_photos(appointment.id)
       }}
    else
      {:error, %Ash.Error.Invalid{errors: errors}} ->
        if Enum.any?(errors, &match?(%Ash.Error.Query.NotFound{}, &1)) do
          {:error, :not_found}
        else
          {:error, :forbidden}
        end

      {:error, %Ash.Error.Query.NotFound{}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp load_problem_photos(appointment_id) do
    Photo
    |> Ash.Query.filter(
      appointment_id == ^appointment_id and photo_type == :problem_area and is_nil(deleted_at)
    )
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.read!(authorize?: false)
    |> Enum.map(&PhotoUpload.apply_url/1)
  end

  defp problem_photo_label(%{caption: caption}) when is_binary(caption) do
    case String.trim(caption) do
      "" -> "Customer problem photo"
      value -> value
    end
  end

  defp problem_photo_label(_photo), do: "Customer problem photo"

  defp photo_car_part_label(nil), do: "Problem area"

  defp photo_car_part_label(part) do
    part
    |> to_string()
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp authorize_job_access(%{role: :admin}, _appointment), do: {:ok, nil}

  defp authorize_job_access(current_customer, appointment) do
    case technician_record_for(current_customer) do
      nil -> {:error, :forbidden}
      %{id: technician_id} = tech when technician_id == appointment.technician_id -> {:ok, tech}
      _other -> {:error, :forbidden}
    end
  end

  defp technician_record_for(current_customer) do
    Technician
    |> Ash.Query.for_read(:for_user_account, %{user_account_id: current_customer.id})
    |> Ash.read_one!(authorize?: false)
  end

  defp assign_job(socket, job) do
    assign(socket,
      appointment: job.appointment,
      tech_record: job.tech_record,
      customer: job.customer,
      service: job.service,
      address: job.address,
      vehicle: job.vehicle,
      progress: job.progress,
      problem_photos: job.problem_photos,
      command: job_command(job.appointment.status, job.progress)
    )
  end

  defp deny_access(socket, message) do
    socket
    |> put_flash(:error, message)
    |> redirect(to: ~p"/tech")
  end

  defp job_command(_status, %{checklist_id: checklist_id}) when not is_nil(checklist_id) do
    %{
      title: "Wash in progress",
      body: "Continue the active wash checklist.",
      kind: :active,
      action: %{
        type: :link,
        id: "job-open-checklist",
        to: ~p"/tech/checklist/#{checklist_id}",
        label: "Continue checklist"
      }
    }
  end

  defp job_command(:confirmed, %{steps_total: 0}) do
    %{
      title: "Leave for this service stop",
      body: "Head out when you are ready to travel to the customer.",
      kind: :ready,
      action: %{type: :event, id: "job-head-out", event: "depart", label: "Head out"}
    }
  end

  defp job_command(:en_route, %{steps_total: 0}) do
    %{
      title: "You are en route",
      body: "Mark yourself on site when you arrive.",
      kind: :travel,
      action: %{type: :event, id: "job-arrived", event: "arrive", label: "Arrived"}
    }
  end

  defp job_command(:on_site, %{steps_total: 0}) do
    %{
      title: "You are on site",
      body: "Start the wash when you are ready.",
      kind: :onsite,
      action: %{type: :event, id: "job-start-wash", event: "start_wash", label: "Start wash"}
    }
  end

  defp job_command(:pending, _progress) do
    %{
      title: "Waiting on dispatch",
      body: "This appointment is not ready for field action yet.",
      kind: :waiting,
      action: nil
    }
  end

  defp job_command(:completed, _progress) do
    %{
      title: "Completed stop",
      body: "Review the completed service details.",
      kind: :done,
      action: nil
    }
  end

  defp job_command(:cancelled, _progress) do
    %{
      title: "Cancelled stop",
      body: "No field action is available for this appointment.",
      kind: :waiting,
      action: nil
    }
  end

  defp job_command(_status, _progress) do
    %{
      title: "Review appointment",
      body: "Review the appointment details before taking action.",
      kind: :review,
      action: nil
    }
  end

  defp status_class(:pending), do: "badge-ghost"
  defp status_class(:confirmed), do: "badge-info"
  defp status_class(:en_route), do: "badge-info"
  defp status_class(:on_site), do: "badge-info"
  defp status_class(:in_progress), do: "badge-warning"
  defp status_class(:completed), do: "badge-success"
  defp status_class(_), do: "badge-ghost"

  defp format_status(:pending), do: "Pending"
  defp format_status(:confirmed), do: "Confirmed"
  defp format_status(:en_route), do: "En route"
  defp format_status(:on_site), do: "On site"
  defp format_status(:in_progress), do: "Active"
  defp format_status(:completed), do: "Done"
  defp format_status(status), do: to_string(status)

  defp maps_url(%{latitude: lat, longitude: lng})
       when is_number(lat) and is_number(lng) do
    "https://maps.apple.com/?daddr=#{lat},#{lng}"
  end

  defp maps_url(%{street: street, city: city, state: state, zip: zip}) do
    q = URI.encode("#{street}, #{city}, #{state} #{zip}")
    "https://maps.apple.com/?daddr=#{q}"
  end

  defp maps_url(_), do: "#"

  defp vehicle_label(%{make: make, model: model, size: size}) do
    type =
      case size do
        :car -> "Car"
        :suv_van -> "SUV/Van"
        :pickup -> "Pickup"
        _ -> ""
      end

    [make, model, type]
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> Enum.join(" · ")
  end

  defp vehicle_label(_), do: "Vehicle details unavailable"

  defp customer_contact_label(%{phone: phone}) when is_binary(phone) do
    case String.trim(phone) do
      "" -> "No phone on file"
      value -> value
    end
  end

  defp customer_contact_label(_customer), do: "No phone on file"

  defp notes_text(%{notes: notes}) when is_binary(notes) do
    case String.trim(notes) do
      "" -> "No appointment notes"
      value -> value
    end
  end

  defp notes_text(_appointment), do: "No appointment notes"
end
