defmodule MobileCarWashWeb.Tech.JobLive do
  @moduledoc """
  Technician job brief with the next action for a single assigned appointment.
  """
  use MobileCarWashWeb, :live_view

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Fleet.{Address, Vehicle}
  alias MobileCarWash.Operations.Technician

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
         |> assign_job(job)}

      {:error, :not_found} ->
        {:ok, deny_access(socket, "Job not found.")}

      {:error, :forbidden} ->
        {:ok, deny_access(socket, "That job is not assigned to you.")}
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
                </div>
              </div>

              <div class="rounded-xl border border-base-300 bg-base-100 px-4 py-3 text-sm shadow-sm">
                <p class="font-medium text-base-content">Next step</p>
                <p class="mt-1 text-base-content/70">
                  {next_step_label(@appointment.status, @progress)}
                </p>
              </div>
            </div>
          </div>

          <div class="grid gap-4 px-5 py-5 sm:px-6 lg:grid-cols-[1.15fr_0.85fr]">
            <section class="rounded-xl border border-base-300 bg-base-100 p-4 shadow-sm">
              <h2 class="text-sm font-semibold uppercase tracking-[0.18em] text-base-content/50">
                Service stop
              </h2>
              <dl class="mt-4 space-y-4">
                <div>
                  <dt class="text-xs font-medium uppercase tracking-[0.14em] text-base-content/45">
                    Vehicle
                  </dt>
                  <dd class="mt-1 text-sm text-base-content">{vehicle_label(@vehicle)}</dd>
                </div>
                <div>
                  <dt class="text-xs font-medium uppercase tracking-[0.14em] text-base-content/45">
                    Address
                  </dt>
                  <dd class="mt-1">
                    <a
                      href={maps_url(@address)}
                      target="_blank"
                      rel="noopener"
                      class="inline-flex items-start gap-2 text-sm text-primary transition hover:text-primary/80"
                    >
                      <.icon name="hero-map-pin" class="mt-0.5 h-4 w-4 shrink-0" />
                      <span>{@address.street}, {@address.city}, {@address.state} {@address.zip}</span>
                    </a>
                  </dd>
                </div>
                <div :if={present?(@appointment.notes)}>
                  <dt class="text-xs font-medium uppercase tracking-[0.14em] text-base-content/45">
                    Notes
                  </dt>
                  <dd class="mt-1 text-sm leading-6 text-base-content/80">{@appointment.notes}</dd>
                </div>
              </dl>
            </section>

            <section class="rounded-xl border border-base-300 bg-base-100 p-4 shadow-sm">
              <h2 class="text-sm font-semibold uppercase tracking-[0.18em] text-base-content/50">
                Action
              </h2>

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

              <div class="mt-4 flex flex-col gap-3">
                <button
                  :if={@appointment.status == :confirmed and @progress.steps_total == 0}
                  id="job-head-out"
                  phx-click="depart"
                  class="btn btn-primary w-full transition hover:-translate-y-0.5"
                >
                  Head out
                </button>

                <button
                  :if={@appointment.status == :en_route and @progress.steps_total == 0}
                  id="job-arrived"
                  phx-click="arrive"
                  class="btn btn-info w-full transition hover:-translate-y-0.5"
                >
                  Arrived
                </button>

                <button
                  :if={@appointment.status == :on_site and @progress.steps_total == 0}
                  id="job-start-wash"
                  phx-click="start_wash"
                  class="btn btn-warning w-full transition hover:-translate-y-0.5"
                >
                  Start wash
                </button>

                <.link
                  :if={@progress.checklist_id}
                  id="job-open-checklist"
                  navigate={~p"/tech/checklist/#{@progress.checklist_id}"}
                  class="btn btn-primary w-full"
                >
                  {if @progress.steps_done > 0, do: "Continue checklist", else: "Start checklist"}
                </.link>

                <div
                  :if={show_waiting_state?(@appointment.status, @progress)}
                  class="rounded-xl border border-dashed border-base-300 bg-base-200/50 px-4 py-3 text-sm text-base-content/70"
                >
                  This appointment is waiting on dispatch or completion updates before the next action.
                </div>
              </div>
            </section>
          </div>
        </section>
      </main>
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
         progress: Dispatch.checklist_progress(appointment.id)
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
      progress: job.progress
    )
  end

  defp deny_access(socket, message) do
    socket
    |> put_flash(:error, message)
    |> redirect(to: ~p"/tech")
  end

  defp next_step_label(:confirmed, %{steps_total: 0}), do: "Leave for the service address."
  defp next_step_label(:en_route, %{steps_total: 0}), do: "Mark yourself on site when you arrive."
  defp next_step_label(:on_site, %{steps_total: 0}), do: "Start the wash when you're ready."

  defp next_step_label(_status, %{checklist_id: checklist_id, steps_total: steps_total})
       when not is_nil(checklist_id) and steps_total > 0 do
    "Open the checklist and continue the wash."
  end

  defp next_step_label(:completed, _progress), do: "Review the completed stop details."
  defp next_step_label(:pending, _progress), do: "Waiting on confirmation from dispatch."
  defp next_step_label(_status, _progress), do: "Review the appointment details."

  defp show_waiting_state?(status, progress) do
    progress.checklist_id == nil and status in [:pending, :completed, :cancelled]
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

  defp present?(value), do: not is_nil(value) and String.trim(to_string(value)) != ""

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
end
