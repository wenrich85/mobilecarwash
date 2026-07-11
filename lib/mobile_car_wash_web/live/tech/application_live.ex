defmodule MobileCarWashWeb.Tech.ApplicationLive do
  use MobileCarWashWeb, :live_view

  alias MobileCarWash.Operations.TechApplication

  @zone_options [{"Any", ""}, {"NW", "nw"}, {"NE", "ne"}, {"SW", "sw"}, {"SE", "se"}]
  @experience_options [{"None", "none"}, {"Some", "some"}, {"Professional", "professional"}]
  @zone_atoms [:nw, :ne, :sw, :se]
  @experience_atoms [:none, :some, :professional]

  @impl true
  def mount(_params, _session, socket) do
    customer = socket.assigns.current_customer
    application = application_for_customer(customer)

    {:ok,
     socket
     |> assign(:application, application)
     |> assign(:page_title, page_title(socket.assigns.live_action))
     |> assign(:zone_options, @zone_options)
     |> assign(:experience_options, @experience_options)
     |> assign(:form, to_form(form_params(application, customer), as: :application)),
     layout: false}
  end

  @impl true
  def handle_params(_params, _uri, %{assigns: %{live_action: :apply}} = socket) do
    socket =
      socket
      |> assign(:page_title, page_title(:apply))
      |> maybe_redirect_to_status()

    {:noreply, socket}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, assign(socket, :page_title, page_title(socket.assigns.live_action))}
  end

  @impl true
  def handle_event("save", %{"application" => params}, socket) do
    customer = socket.assigns.current_customer
    normalized_params = normalize_params(params)

    result =
      case socket.assigns.application do
        nil ->
          TechApplication
          |> Ash.Changeset.for_create(:create, normalized_params)
          |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
          |> Ash.create(authorize?: false)

        application ->
          application
          |> Ash.Changeset.for_update(:save_draft, normalized_params)
          |> Ash.update(authorize?: false)
      end

    case result do
      {:ok, application} ->
        {:noreply,
         socket
         |> assign(:application, application)
         |> assign(:form, to_form(form_params(application, customer), as: :application))
         |> put_flash(:info, "Application draft saved.")}

      {:error, _error} ->
        {:noreply,
         socket
         |> assign(:form, to_form(params, as: :application))
         |> put_flash(:error, "Could not save application.")}
    end
  end

  def handle_event("submit", _params, %{assigns: %{application: nil}} = socket) do
    {:noreply, put_flash(socket, :error, "Save your application before submitting.")}
  end

  def handle_event("submit", _params, socket) do
    case socket.assigns.application
         |> Ash.Changeset.for_update(:submit, %{})
         |> Ash.update(authorize?: false) do
      {:ok, application} ->
        {:noreply,
         socket
         |> assign(:application, application)
         |> assign(
           :form,
           to_form(form_params(application, socket.assigns.current_customer), as: :application)
         )
         |> put_flash(:info, "Application submitted for review.")
         |> push_patch(to: ~p"/tech/application")}

      {:error, _error} ->
        {:noreply, put_flash(socket, :error, "Complete required fields before submitting.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_customer}>
      <main
        id="tech-application-page"
        class="mx-auto flex min-h-[calc(100vh-8rem)] w-full max-w-5xl flex-col gap-8 px-4 py-8 sm:px-6 lg:px-8"
      >
        <section class="overflow-hidden rounded-2xl border border-base-300 bg-base-100 shadow-sm">
          <div class="border-b border-base-300 bg-gradient-to-r from-primary/10 via-base-100 to-secondary/10 px-6 py-6 sm:px-8">
            <div class="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
              <div class="space-y-2">
                <p class="text-xs font-semibold uppercase tracking-[0.2em] text-primary/80">
                  Technician pathway
                </p>
                <h1 class="text-3xl font-semibold text-base-content">
                  {heading_for(@live_action, @application)}
                </h1>
                <p class="max-w-2xl text-sm leading-6 text-base-content/70">
                  {subheading_for(@live_action, @application)}
                </p>
              </div>

              <div class="inline-flex items-center gap-2 self-start rounded-full border border-base-300 bg-base-100/90 px-3 py-2 text-sm font-medium text-base-content shadow-sm">
                <span class={status_badge_class(@application && @application.status)}>
                  {status_label(@application && @application.status)}
                </span>
              </div>
            </div>
          </div>

          <div
            :if={@live_action == :show}
            id="tech-application-status"
            class="space-y-6 px-6 py-6 sm:px-8"
          >
            <div class="grid gap-4 lg:grid-cols-[minmax(0,1.25fr)_minmax(20rem,0.75fr)]">
              <section class="rounded-2xl border border-base-300 bg-base-100 p-5 shadow-sm">
                <h2 class="text-sm font-semibold uppercase tracking-[0.2em] text-base-content/55">
                  Status journey
                </h2>
                <div id="tech-application-journey" class="mt-5 grid gap-3 sm:grid-cols-4">
                  <div
                    :for={step <- journey_steps(@application)}
                    id={"journey-step-#{step.id}"}
                    data-state={step.state}
                    class={journey_step_class(step.state)}
                  >
                    <p class="text-[11px] font-semibold uppercase tracking-[0.16em]">
                      {step.kicker}
                    </p>
                    <p class="mt-2 text-sm font-semibold">{step.label}</p>
                  </div>
                </div>
              </section>

              <section
                id="tech-application-next-action"
                class="rounded-2xl border border-base-300 bg-base-200/60 p-5 shadow-sm"
              >
                <h2 class="text-sm font-semibold uppercase tracking-[0.2em] text-base-content/55">
                  Next step
                </h2>
                <p class="mt-3 text-sm leading-6 text-base-content/75">
                  {next_step_message(@application)}
                </p>
                <div class="mt-5 flex flex-col gap-3">
                  <.link
                    :if={!@application || @application.status == :draft}
                    patch={~p"/tech/apply"}
                    class="btn btn-primary"
                  >
                    {if @application, do: "Continue application", else: "Start application"}
                  </.link>
                  <.link
                    :if={@application && @application.status == :accepted}
                    navigate={~p"/tech/profile"}
                    class="btn btn-primary"
                  >
                    View tech profile
                  </.link>
                  <.link
                    :if={@application && @application.status == :accepted}
                    navigate={~p"/tech"}
                    class="btn btn-outline"
                  >
                    Open tech tools
                  </.link>
                </div>
              </section>
            </div>

            <section
              :if={@application && final_decision?(@application)}
              class="rounded-2xl border border-base-300 bg-base-100 p-5 shadow-sm"
            >
              <h2 class="text-sm font-semibold uppercase tracking-[0.2em] text-base-content/55">
                Decision note
              </h2>
              <p class="mt-3 text-sm leading-6 text-base-content/75">
                {blank_fallback(@application.decision_note, "No decision note was added.")}
              </p>
            </section>

            <section
              :if={@application}
              id="tech-application-details"
              class="grid gap-4 lg:grid-cols-2"
            >
              <div class="rounded-2xl border border-base-300 bg-base-100 p-5 shadow-sm">
                <h2 class="text-sm font-semibold uppercase tracking-[0.2em] text-base-content/55">
                  Applicant details
                </h2>
                <dl class="mt-4 grid gap-4 sm:grid-cols-2">
                  <.detail_item label="Preferred name" value={@application.preferred_name} />
                  <.detail_item label="Phone" value={blank_fallback(@application.phone)} />
                  <.detail_item label="Home ZIP" value={blank_fallback(@application.home_zip)} />
                  <.detail_item
                    label="Preferred zone"
                    value={zone_label(@application.preferred_zone)}
                  />
                  <.detail_item
                    label="Experience"
                    value={experience_label(@application.experience_level)}
                  />
                  <.detail_item
                    label="Desired hours"
                    value={number_fallback(@application.desired_hours_per_week)}
                  />
                  <.detail_item
                    label="Earliest start"
                    value={date_fallback(@application.earliest_start_date)}
                  />
                  <.detail_item
                    label="Submitted"
                    value={datetime_fallback(@application.submitted_at)}
                  />
                  <.detail_item label="Reviewed" value={datetime_fallback(@application.reviewed_at)} />
                  <.detail_item label="Decided" value={datetime_fallback(@application.decided_at)} />
                </dl>
              </div>

              <div class="rounded-2xl border border-base-300 bg-base-100 p-5 shadow-sm">
                <h2 class="text-sm font-semibold uppercase tracking-[0.2em] text-base-content/55">
                  Availability and requirements
                </h2>
                <dl class="mt-4 grid gap-4 sm:grid-cols-2">
                  <.detail_item label="Days" value={availability_days(@application)} />
                  <.detail_item label="Times" value={availability_times(@application)} />
                  <.detail_item
                    label="Driver license"
                    value={yes_no(@application.has_valid_driver_license)}
                  />
                  <.detail_item
                    label="Transportation"
                    value={yes_no(@application.has_reliable_transportation)}
                  />
                  <.detail_item
                    label="Can lift supplies"
                    value={yes_no(@application.can_lift_supplies)}
                  />
                  <.detail_item
                    label="Emergency contact"
                    value={"#{blank_fallback(@application.emergency_contact_name)} / #{blank_fallback(@application.emergency_contact_phone)}"}
                  />
                </dl>
              </div>

              <div class="rounded-2xl border border-base-300 bg-base-100 p-5 shadow-sm lg:col-span-2">
                <h2 class="text-sm font-semibold uppercase tracking-[0.2em] text-base-content/55">
                  Application notes
                </h2>
                <div class="mt-4 grid gap-4 lg:grid-cols-3">
                  <.narrative_item label="Why work with us" value={@application.why_work_with_us} />
                  <.narrative_item label="Experience notes" value={@application.experience_notes} />
                  <.narrative_item label="Schedule notes" value={@application.schedule_notes} />
                </div>
              </div>
            </section>
          </div>

          <div :if={@live_action == :apply} class="px-6 py-6 sm:px-8">
            <.form for={@form} id="tech-application-form" phx-submit="save" class="space-y-8">
              <div class="grid gap-8 lg:grid-cols-[minmax(0,2fr)_minmax(18rem,1fr)]">
                <div class="space-y-8">
                  <section class="space-y-4">
                    <div>
                      <h2 class="text-lg font-semibold text-base-content">Basics</h2>
                      <p class="mt-1 text-sm text-base-content/65">
                        Tell us where you want to work and how to reach you.
                      </p>
                    </div>

                    <div class="grid gap-4 sm:grid-cols-2">
                      <.input field={@form[:preferred_name]} label="Preferred name" />
                      <.input field={@form[:phone]} label="Phone" />
                      <.input field={@form[:home_zip]} label="Home ZIP" />
                      <.input
                        field={@form[:preferred_zone]}
                        type="select"
                        label="Preferred zone"
                        options={@zone_options}
                      />
                      <.input
                        field={@form[:desired_hours_per_week]}
                        type="number"
                        label="Desired hours per week"
                      />
                      <.input
                        field={@form[:earliest_start_date]}
                        type="date"
                        label="Earliest start date"
                      />
                    </div>
                  </section>

                  <section class="space-y-4">
                    <div>
                      <h2 class="text-lg font-semibold text-base-content">
                        Availability and experience
                      </h2>
                      <p class="mt-1 text-sm text-base-content/65">
                        Help dispatch understand when you can realistically take jobs.
                      </p>
                    </div>

                    <div class="grid gap-4 sm:grid-cols-2">
                      <.input
                        field={@form[:experience_level]}
                        type="select"
                        label="Experience level"
                        options={@experience_options}
                      />
                    </div>

                    <div class="grid gap-3 rounded-2xl border border-base-300 bg-base-200/40 p-4 sm:grid-cols-2">
                      <.input
                        field={@form[:availability_weekdays]}
                        type="checkbox"
                        label="Available weekdays"
                      />
                      <.input
                        field={@form[:availability_weekends]}
                        type="checkbox"
                        label="Available weekends"
                      />
                      <.input
                        field={@form[:availability_mornings]}
                        type="checkbox"
                        label="Available mornings"
                      />
                      <.input
                        field={@form[:availability_afternoons]}
                        type="checkbox"
                        label="Available afternoons"
                      />
                      <.input
                        field={@form[:availability_evenings]}
                        type="checkbox"
                        label="Available evenings"
                      />
                      <.input
                        field={@form[:has_valid_driver_license]}
                        type="checkbox"
                        label="I have a valid driver license"
                      />
                      <.input
                        field={@form[:has_reliable_transportation]}
                        type="checkbox"
                        label="I have reliable transportation"
                      />
                      <.input
                        field={@form[:can_lift_supplies]}
                        type="checkbox"
                        label="I can lift and carry supplies"
                      />
                    </div>
                  </section>

                  <section class="space-y-4">
                    <div>
                      <h2 class="text-lg font-semibold text-base-content">Narrative</h2>
                      <p class="mt-1 text-sm text-base-content/65">
                        A little context goes a long way when admin reviews the queue.
                      </p>
                    </div>

                    <div class="space-y-4">
                      <.input
                        field={@form[:why_work_with_us]}
                        type="textarea"
                        label="Why do you want to work with us?"
                      />
                      <.input
                        field={@form[:experience_notes]}
                        type="textarea"
                        label="Car wash or detailing experience"
                      />
                      <.input
                        field={@form[:schedule_notes]}
                        type="textarea"
                        label="Schedule or transportation notes"
                      />
                    </div>
                  </section>
                </div>

                <aside class="space-y-4">
                  <div class="rounded-2xl border border-base-300 bg-base-200/60 p-5 shadow-sm">
                    <h2 class="text-sm font-semibold uppercase tracking-[0.2em] text-base-content/55">
                      Emergency contact
                    </h2>
                    <div class="mt-4 space-y-4">
                      <.input
                        field={@form[:emergency_contact_name]}
                        label="Emergency contact name"
                      />
                      <.input
                        field={@form[:emergency_contact_phone]}
                        label="Emergency contact phone"
                      />
                    </div>
                  </div>

                  <div class="rounded-2xl border border-base-300 bg-base-100 p-5 shadow-sm">
                    <h2 class="text-sm font-semibold uppercase tracking-[0.2em] text-base-content/55">
                      Submission flow
                    </h2>
                    <ol class="mt-4 space-y-3 text-sm leading-6 text-base-content/70">
                      <li>1. Save your draft so the application is attached to your account.</li>
                      <li>2. Review the details and make any edits you need.</li>
                      <li>3. Submit when you are ready for admin review.</li>
                    </ol>

                    <div class="mt-6 flex flex-col gap-3">
                      <button
                        id="save-tech-application"
                        type="submit"
                        class="btn btn-primary transition-transform duration-150 hover:-translate-y-0.5"
                      >
                        Save draft
                      </button>
                      <button
                        :if={@application}
                        id="submit-tech-application"
                        type="button"
                        phx-click="submit"
                        class="btn btn-secondary transition-transform duration-150 hover:-translate-y-0.5"
                      >
                        Submit for review
                      </button>
                    </div>
                  </div>
                </aside>
              </div>
            </.form>
          </div>
        </section>
      </main>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true

  defp detail_item(assigns) do
    ~H"""
    <div>
      <dt class="text-xs uppercase tracking-wide text-base-content/50">{@label}</dt>
      <dd class="mt-1 font-medium text-base-content">{@value}</dd>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true

  defp narrative_item(assigns) do
    ~H"""
    <article class="rounded-2xl border border-base-300 bg-base-200/35 p-4">
      <h3 class="text-xs font-semibold uppercase tracking-[0.16em] text-base-content/50">
        {@label}
      </h3>
      <p class="mt-2 text-sm leading-6 text-base-content/75">
        {blank_fallback(@value)}
      </p>
    </article>
    """
  end

  defp maybe_redirect_to_status(%{assigns: %{application: %{status: status}}} = socket)
       when status != :draft do
    push_patch(socket, to: ~p"/tech/application")
  end

  defp maybe_redirect_to_status(socket), do: socket

  defp application_for_customer(customer) do
    TechApplication
    |> Ash.Query.for_read(:for_customer, %{customer_id: customer.id})
    |> Ash.read_one!(authorize?: false)
  end

  defp page_title(:apply), do: "Technician Application"
  defp page_title(:show), do: "Application Status"
  defp page_title(_), do: "Technician Application"

  defp heading_for(:apply, _application), do: "Technician Application"
  defp heading_for(:show, _application), do: "Application Status"
  defp heading_for(_, _application), do: "Technician Application"

  defp subheading_for(:apply, _application) do
    "Save a draft first, then submit it when the details feel right."
  end

  defp subheading_for(:show, application) do
    status_message(application)
  end

  defp subheading_for(_, application), do: status_message(application)

  defp form_params(nil, customer) do
    %{
      "preferred_name" => customer.name || "",
      "phone" => customer.phone || "",
      "home_zip" => "",
      "preferred_zone" => "",
      "availability_weekdays" => false,
      "availability_weekends" => false,
      "availability_mornings" => false,
      "availability_afternoons" => false,
      "availability_evenings" => false,
      "experience_level" => "none",
      "has_valid_driver_license" => false,
      "has_reliable_transportation" => false,
      "can_lift_supplies" => false,
      "desired_hours_per_week" => "",
      "earliest_start_date" => "",
      "emergency_contact_name" => "",
      "emergency_contact_phone" => "",
      "why_work_with_us" => "",
      "experience_notes" => "",
      "schedule_notes" => ""
    }
  end

  defp form_params(application, _customer) do
    application
    |> Map.take(TechApplication.applicant_fields())
    |> Enum.into(%{}, fn {key, value} -> {to_string(key), value_to_form(value)} end)
  end

  defp value_to_form(nil), do: ""
  defp value_to_form(value) when is_atom(value), do: to_string(value)
  defp value_to_form(%Date{} = value), do: Date.to_iso8601(value)
  defp value_to_form(value), do: value

  defp normalize_params(params) do
    params
    |> Map.take(Enum.map(TechApplication.applicant_fields(), &to_string/1))
    |> Map.update("preferred_zone", "", &blank_to_nil/1)
    |> Map.update("experience_level", "none", &blank_to_nil/1)
    |> atomize_allowed("preferred_zone", @zone_atoms)
    |> atomize_allowed("experience_level", @experience_atoms)
    |> parse_int("desired_hours_per_week")
    |> parse_date("earliest_start_date")
    |> parse_bool("availability_weekdays")
    |> parse_bool("availability_weekends")
    |> parse_bool("availability_mornings")
    |> parse_bool("availability_afternoons")
    |> parse_bool("availability_evenings")
    |> parse_bool("has_valid_driver_license")
    |> parse_bool("has_reliable_transportation")
    |> parse_bool("can_lift_supplies")
    |> Enum.into(%{}, fn {key, value} -> {String.to_existing_atom(key), value} end)
  end

  defp atomize_allowed(params, key, allowed) do
    value = Map.get(params, key)
    Map.put(params, key, Enum.find(allowed, &(to_string(&1) == value)))
  end

  defp parse_int(params, key) do
    case Integer.parse(to_string(Map.get(params, key, ""))) do
      {value, ""} -> Map.put(params, key, value)
      _ -> Map.put(params, key, nil)
    end
  end

  defp parse_date(params, key) do
    case Date.from_iso8601(to_string(Map.get(params, key, ""))) do
      {:ok, value} -> Map.put(params, key, value)
      {:error, _} -> Map.put(params, key, nil)
    end
  end

  defp parse_bool(params, key) do
    Map.put(params, key, Map.get(params, key) in ["true", "on", true])
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp status_label(nil), do: "Start your application"
  defp status_label(:draft), do: "Draft"
  defp status_label(:pending_review), do: "Pending review"
  defp status_label(:reviewed), do: "Reviewed"
  defp status_label(:accepted), do: "Accepted"
  defp status_label(:not_accepted), do: "Not accepted"

  defp journey_steps(application) do
    status = application && application.status

    [
      %{id: "draft", kicker: "Step 1", label: "Draft", state: journey_state(status, :draft)},
      %{
        id: "pending_review",
        kicker: "Step 2",
        label: "Pending review",
        state: journey_state(status, :pending_review)
      },
      %{
        id: "reviewed",
        kicker: "Step 3",
        label: "Reviewed",
        state: journey_state(status, :reviewed)
      },
      %{
        id: "decision",
        kicker: "Step 4",
        label: decision_step_label(status),
        state: journey_state(status, :decision)
      }
    ]
  end

  defp journey_state(nil, _step), do: "upcoming"
  defp journey_state(:draft, :draft), do: "current"
  defp journey_state(:draft, _step), do: "upcoming"
  defp journey_state(:pending_review, :draft), do: "complete"
  defp journey_state(:pending_review, :pending_review), do: "current"
  defp journey_state(:pending_review, _step), do: "upcoming"
  defp journey_state(:reviewed, step) when step in [:draft, :pending_review], do: "complete"
  defp journey_state(:reviewed, :reviewed), do: "current"
  defp journey_state(:reviewed, :decision), do: "upcoming"

  defp journey_state(status, step)
       when status in [:accepted, :not_accepted] and
              step in [:draft, :pending_review, :reviewed],
       do: "complete"

  defp journey_state(status, :decision) when status in [:accepted, :not_accepted],
    do: "current"

  defp journey_state(_status, _step), do: "upcoming"

  defp decision_step_label(:accepted), do: "Accepted"
  defp decision_step_label(:not_accepted), do: "Not accepted"
  defp decision_step_label(_status), do: "Decision"

  defp journey_step_class("complete") do
    "rounded-2xl border border-success/25 bg-success/10 p-4 text-success"
  end

  defp journey_step_class("current") do
    "rounded-2xl border border-primary/35 bg-primary/10 p-4 text-primary"
  end

  defp journey_step_class(_state) do
    "rounded-2xl border border-base-300 bg-base-200/45 p-4 text-base-content/55"
  end

  defp final_decision?(%{status: status}), do: status in [:accepted, :not_accepted]
  defp final_decision?(_application), do: false

  defp status_badge_class(nil),
    do: "rounded-full bg-base-200 px-3 py-1 text-xs text-base-content/70"

  defp status_badge_class(:draft),
    do: "rounded-full bg-base-200 px-3 py-1 text-xs text-base-content/70"

  defp status_badge_class(:pending_review),
    do: "rounded-full bg-warning/15 px-3 py-1 text-xs text-warning"

  defp status_badge_class(:reviewed),
    do: "rounded-full bg-info/15 px-3 py-1 text-xs text-info"

  defp status_badge_class(:accepted),
    do: "rounded-full bg-success/15 px-3 py-1 text-xs text-success"

  defp status_badge_class(:not_accepted),
    do: "rounded-full bg-error/15 px-3 py-1 text-xs text-error"

  defp status_message(nil),
    do: "Start an application to share your availability and technician details."

  defp status_message(%{status: :draft}),
    do: "Your application is saved, but it has not been submitted yet."

  defp status_message(%{status: :pending_review}),
    do: "Your application is in the admin queue."

  defp status_message(%{status: :reviewed}),
    do: "Your application has been reviewed."

  defp status_message(%{status: :accepted}),
    do: "You have been accepted."

  defp status_message(%{status: :not_accepted}),
    do: "Your application was not accepted at this time."

  defp next_step_message(nil),
    do: "Fill out the application and save a draft before submitting it for review."

  defp next_step_message(%{status: :draft}),
    do: "Finish any remaining details and submit when ready."

  defp next_step_message(%{status: :pending_review}),
    do: "No action needed right now. We will review your application and update this page."

  defp next_step_message(%{status: :reviewed}),
    do: "A final decision is still pending. Watch this page for the next update."

  defp next_step_message(%{status: :accepted}),
    do:
      "Your technician profile is ready. Use your profile to review pay, zone, and account details."

  defp next_step_message(%{status: :not_accepted}),
    do:
      "You can keep using this customer account normally. Any applicant-visible note from the team appears below."

  defp availability_days(application) do
    []
    |> maybe_push(application.availability_weekdays, "Weekdays")
    |> maybe_push(application.availability_weekends, "Weekends")
    |> list_or_fallback()
  end

  defp availability_times(application) do
    []
    |> maybe_push(application.availability_mornings, "Mornings")
    |> maybe_push(application.availability_afternoons, "Afternoons")
    |> maybe_push(application.availability_evenings, "Evenings")
    |> list_or_fallback()
  end

  defp maybe_push(list, true, value), do: list ++ [value]
  defp maybe_push(list, _flag, _value), do: list
  defp list_or_fallback([]), do: "Not provided"
  defp list_or_fallback(items), do: Enum.join(items, ", ")

  defp yes_no(true), do: "Yes"
  defp yes_no(false), do: "No"
  defp yes_no(_), do: "No"

  defp zone_label(nil), do: "Not provided"
  defp zone_label(:nw), do: "NW"
  defp zone_label(:ne), do: "NE"
  defp zone_label(:sw), do: "SW"
  defp zone_label(:se), do: "SE"
  defp zone_label(_), do: "Not provided"

  defp experience_label(:none), do: "None"
  defp experience_label(:some), do: "Some"
  defp experience_label(:professional), do: "Professional"
  defp experience_label(_), do: "Not provided"

  defp blank_fallback(value, fallback \\ "Not provided")
  defp blank_fallback(nil, fallback), do: fallback
  defp blank_fallback("", fallback), do: fallback
  defp blank_fallback(value, _fallback), do: value

  defp number_fallback(nil), do: "Not provided"
  defp number_fallback(value), do: Integer.to_string(value)

  defp date_fallback(nil), do: "Not provided"
  defp date_fallback(%Date{} = value), do: Calendar.strftime(value, "%b %-d, %Y")

  defp datetime_fallback(nil), do: "Not yet"

  defp datetime_fallback(%DateTime{} = value) do
    Calendar.strftime(value, "%b %d, %Y at %I:%M %p UTC")
  end
end
