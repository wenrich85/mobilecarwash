defmodule MobileCarWashWeb.Admin.TechApplicationsLive do
  use MobileCarWashWeb, :live_view

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Operations.{TechApplication, Van}

  require Ash.Query

  @zone_options [
    {"Use preferred zone", ""},
    {"NW", "nw"},
    {"NE", "ne"},
    {"SW", "sw"},
    {"SE", "se"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Tech Applications")
     |> assign(:application, nil)
     |> assign(:customer, nil)
     |> assign(:vans, load_vans())
     |> assign(:zone_options, @zone_options)
     |> assign(:decision_form, empty_decision_form())
     |> assign(:decline_form, empty_decline_form())
     |> assign(:review_form, empty_review_form())
     |> stream(:applications, load_applications()), layout: false}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    application = load_application!(id)
    customer = load_customer!(application.customer_id)

    {:noreply,
     socket
     |> assign(:page_title, "Review #{application.preferred_name}")
     |> assign(:application, application)
     |> assign(:customer, customer)
     |> assign(:decision_form, decision_form(application))
     |> assign(:decline_form, decline_form(application))
     |> assign(:review_form, review_form(application))
     |> stream(:applications, load_applications(), reset: true)}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply,
     socket
     |> assign(:page_title, "Tech Applications")
     |> assign(:application, nil)
     |> assign(:customer, nil)
     |> assign(:decision_form, empty_decision_form())
     |> assign(:decline_form, empty_decline_form())
     |> assign(:review_form, empty_review_form())
     |> stream(:applications, load_applications(), reset: true)}
  end

  @impl true
  def handle_event("mark_reviewed", %{"review" => params}, socket) do
    case mark_reviewed(socket.assigns.application, params["review_notes"]) do
      {:ok, application} ->
        {:noreply,
         socket
         |> refresh_show(application)
         |> put_flash(:info, "Application marked reviewed.")}

      {:error, _error} ->
        {:noreply, put_flash(socket, :error, "Could not mark this application reviewed.")}
    end
  end

  def handle_event("not_accept", %{"not_accept" => params}, socket) do
    with {:ok, reviewed_application} <-
           ensure_reviewed(socket.assigns.application, params["review_notes"]),
         {:ok, application} <-
           reviewed_application
           |> Ash.Changeset.for_update(:not_accept, %{
             review_notes: blank_to_nil(params["review_notes"]),
             decision_note:
               blank_to_nil(params["decision_note"]) ||
                 "Application not accepted at this time."
           })
           |> Ash.update(authorize?: false) do
      {:noreply,
       socket
       |> refresh_show(application)
       |> put_flash(:info, "Application marked not accepted.")}
    else
      {:error, _error} ->
        {:noreply, put_flash(socket, :error, "Could not update this application.")}
    end
  end

  def handle_event("accept", %{"decision" => params}, socket) do
    attrs = %{
      review_notes: blank_to_nil(params["review_notes"]),
      decision_note: blank_to_nil(params["decision_note"]),
      accepted_pay_rate_cents: parse_int(params["accepted_pay_rate_cents"]) || 2500,
      accepted_pay_rate_pct: parse_pct(params["accepted_pay_rate_pct"]),
      assigned_zone: parse_zone(params["assigned_zone"]),
      van_id: blank_to_nil(params["van_id"]),
      active: truthy?(params["active"])
    }

    with {:ok, reviewed_application} <-
           ensure_reviewed(socket.assigns.application, params["review_notes"]),
         {:ok, application} <-
           reviewed_application
           |> Ash.Changeset.for_update(:accept, attrs)
           |> Ash.update(authorize?: false) do
      {:noreply,
       socket
       |> refresh_show(application)
       |> put_flash(:info, "Applicant accepted and technician account activated.")}
    else
      {:error, _error} ->
        {:noreply, put_flash(socket, :error, "Could not accept this application.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_customer}>
      <main class="mx-auto flex w-full max-w-7xl flex-col gap-6 px-4 py-8 sm:px-6 lg:px-8">
        <section :if={@live_action == :index} id="tech-applications" class="space-y-5">
          <div class="flex flex-col gap-2">
            <p class="text-xs font-semibold uppercase tracking-[0.2em] text-primary/80">
              Admin review
            </p>
            <div class="flex flex-col gap-3 md:flex-row md:items-end md:justify-between">
              <div class="space-y-2">
                <h1 class="text-3xl font-semibold text-base-content">Tech applications</h1>
                <p class="max-w-3xl text-sm leading-6 text-base-content/70">
                  Review applicants, capture notes, and convert accepted customers into technicians.
                </p>
              </div>
              <div class="rounded-full border border-base-300 bg-base-100 px-4 py-2 text-sm text-base-content/65 shadow-sm">
                Queue updates in real time with review decisions.
              </div>
            </div>
          </div>

          <div class="overflow-hidden rounded-2xl border border-base-300 bg-base-100 shadow-sm">
            <div class="overflow-x-auto">
              <table class="min-w-full divide-y divide-base-300">
                <thead class="bg-base-200/70">
                  <tr class="text-left text-xs font-semibold uppercase tracking-[0.18em] text-base-content/55">
                    <th class="px-4 py-3">Applicant</th>
                    <th class="px-4 py-3">Status</th>
                    <th class="px-4 py-3">Zone</th>
                    <th class="px-4 py-3">Experience</th>
                    <th class="px-4 py-3">Submitted</th>
                    <th class="px-4 py-3"></th>
                  </tr>
                </thead>
                <tbody
                  id="tech-applications-list"
                  phx-update="stream"
                  class="divide-y divide-base-300"
                >
                  <tr id="tech-applications-empty" class="hidden only:table-row">
                    <td colspan="6" class="px-4 py-12 text-center text-sm text-base-content/60">
                      No technician applications yet.
                    </td>
                  </tr>
                  <tr
                    :for={{dom_id, application} <- @streams.applications}
                    id={dom_id}
                    class="bg-base-100 transition-colors hover:bg-base-200/40"
                  >
                    <td class="px-4 py-4">
                      <div class="font-medium text-base-content">{application.preferred_name}</div>
                    </td>
                    <td class="px-4 py-4">
                      <span class={status_badge_class(application.status)}>
                        {status_label(application.status)}
                      </span>
                    </td>
                    <td class="px-4 py-4 text-sm text-base-content/70">
                      {zone_label(application.preferred_zone)}
                    </td>
                    <td class="px-4 py-4 text-sm text-base-content/70">
                      {experience_label(application.experience_level)}
                    </td>
                    <td class="px-4 py-4 text-sm text-base-content/70">
                      {format_date(application.submitted_at)}
                    </td>
                    <td class="px-4 py-4 text-right">
                      <.link
                        navigate={~p"/admin/tech-applications/#{application.id}"}
                        class="inline-flex items-center gap-2 rounded-full border border-base-300 px-3 py-2 text-sm font-medium text-base-content transition hover:border-primary/40 hover:text-primary"
                      >
                        <.icon name="hero-arrow-right" class="h-4 w-4" />
                        <span>Review</span>
                      </.link>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        </section>

        <section
          :if={(@live_action == :show and @application) && @customer}
          id="tech-application-review"
          class="space-y-6"
        >
          <.link
            navigate={~p"/admin/tech-applications"}
            class="inline-flex w-fit items-center gap-2 rounded-full border border-base-300 px-3 py-2 text-sm font-medium text-base-content/75 transition hover:border-primary/40 hover:text-primary"
          >
            <.icon name="hero-arrow-left" class="h-4 w-4" />
            <span>Back to queue</span>
          </.link>

          <div class="overflow-hidden rounded-3xl border border-base-300 bg-base-100 shadow-sm">
            <div class="border-b border-base-300 bg-gradient-to-r from-primary/10 via-base-100 to-secondary/10 px-6 py-6 sm:px-8">
              <div class="flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between">
                <div class="space-y-2">
                  <p class="text-xs font-semibold uppercase tracking-[0.2em] text-primary/80">
                    Application review
                  </p>
                  <h1 class="text-3xl font-semibold text-base-content">
                    {@application.preferred_name}
                  </h1>
                  <p class="text-sm leading-6 text-base-content/70">
                    {@customer.email} • {blank_fallback(@application.phone, @customer.phone)}
                  </p>
                </div>

                <div class="inline-flex items-center gap-3 self-start rounded-full border border-base-300 bg-base-100/90 px-4 py-2 shadow-sm">
                  <span class={status_badge_class(@application.status)}>
                    {status_label(@application.status)}
                  </span>
                  <span class="text-sm text-base-content/55">
                    Submitted {format_date(@application.submitted_at)}
                  </span>
                </div>
              </div>
            </div>

            <div class="grid gap-6 px-6 py-6 lg:grid-cols-[minmax(0,1.15fr)_minmax(22rem,0.85fr)] sm:px-8">
              <div class="space-y-6">
                <section class="rounded-2xl border border-base-300 bg-base-100 p-5 shadow-sm">
                  <div class="flex items-center justify-between gap-3">
                    <h2 class="text-lg font-semibold text-base-content">Applicant snapshot</h2>
                    <span class="rounded-full bg-base-200 px-3 py-1 text-xs font-medium uppercase tracking-wide text-base-content/60">
                      {experience_label(@application.experience_level)}
                    </span>
                  </div>

                  <dl class="mt-5 grid gap-4 sm:grid-cols-2">
                    <div>
                      <dt class="text-xs uppercase tracking-[0.16em] text-base-content/50">
                        Home ZIP
                      </dt>
                      <dd class="mt-1 text-sm font-medium text-base-content">
                        {blank_fallback(@application.home_zip)}
                      </dd>
                    </div>
                    <div>
                      <dt class="text-xs uppercase tracking-[0.16em] text-base-content/50">
                        Preferred zone
                      </dt>
                      <dd class="mt-1 text-sm font-medium text-base-content">
                        {zone_label(@application.preferred_zone)}
                      </dd>
                    </div>
                    <div>
                      <dt class="text-xs uppercase tracking-[0.16em] text-base-content/50">
                        Desired hours
                      </dt>
                      <dd class="mt-1 text-sm font-medium text-base-content">
                        {number_fallback(@application.desired_hours_per_week)}
                      </dd>
                    </div>
                    <div>
                      <dt class="text-xs uppercase tracking-[0.16em] text-base-content/50">
                        Earliest start
                      </dt>
                      <dd class="mt-1 text-sm font-medium text-base-content">
                        {date_fallback(@application.earliest_start_date)}
                      </dd>
                    </div>
                  </dl>

                  <div class="mt-5 grid gap-3 rounded-2xl border border-base-300 bg-base-200/40 p-4 sm:grid-cols-2">
                    <div class="text-sm text-base-content/75">
                      <span class="font-medium text-base-content">Weekdays:</span>
                      {yes_no(@application.availability_weekdays)}
                    </div>
                    <div class="text-sm text-base-content/75">
                      <span class="font-medium text-base-content">Weekends:</span>
                      {yes_no(@application.availability_weekends)}
                    </div>
                    <div class="text-sm text-base-content/75">
                      <span class="font-medium text-base-content">Mornings:</span>
                      {yes_no(@application.availability_mornings)}
                    </div>
                    <div class="text-sm text-base-content/75">
                      <span class="font-medium text-base-content">Afternoons:</span>
                      {yes_no(@application.availability_afternoons)}
                    </div>
                    <div class="text-sm text-base-content/75">
                      <span class="font-medium text-base-content">Evenings:</span>
                      {yes_no(@application.availability_evenings)}
                    </div>
                    <div class="text-sm text-base-content/75">
                      <span class="font-medium text-base-content">Can lift supplies:</span>
                      {yes_no(@application.can_lift_supplies)}
                    </div>
                    <div class="text-sm text-base-content/75">
                      <span class="font-medium text-base-content">Driver license:</span>
                      {yes_no(@application.has_valid_driver_license)}
                    </div>
                    <div class="text-sm text-base-content/75">
                      <span class="font-medium text-base-content">Transportation:</span>
                      {yes_no(@application.has_reliable_transportation)}
                    </div>
                  </div>
                </section>

                <section class="grid gap-4 xl:grid-cols-2">
                  <article class="rounded-2xl border border-base-300 bg-base-100 p-5 shadow-sm">
                    <h2 class="text-sm font-semibold uppercase tracking-[0.18em] text-base-content/55">
                      Why work with us
                    </h2>
                    <p class="mt-3 text-sm leading-6 text-base-content/75">
                      {blank_fallback(@application.why_work_with_us)}
                    </p>
                  </article>

                  <article class="rounded-2xl border border-base-300 bg-base-100 p-5 shadow-sm">
                    <h2 class="text-sm font-semibold uppercase tracking-[0.18em] text-base-content/55">
                      Experience notes
                    </h2>
                    <p class="mt-3 text-sm leading-6 text-base-content/75">
                      {blank_fallback(@application.experience_notes)}
                    </p>
                  </article>

                  <article class="rounded-2xl border border-base-300 bg-base-100 p-5 shadow-sm xl:col-span-2">
                    <h2 class="text-sm font-semibold uppercase tracking-[0.18em] text-base-content/55">
                      Schedule notes
                    </h2>
                    <p class="mt-3 text-sm leading-6 text-base-content/75">
                      {blank_fallback(@application.schedule_notes)}
                    </p>
                  </article>
                </section>
              </div>

              <div class="space-y-4">
                <section class="rounded-2xl border border-base-300 bg-base-100 p-5 shadow-sm">
                  <div class="flex flex-wrap items-center justify-between gap-3">
                    <div>
                      <h2 class="text-lg font-semibold text-base-content">Decisioning</h2>
                      <p class="mt-1 text-sm leading-6 text-base-content/65">
                        Save review notes, then approve or decline with a technician-ready payload.
                      </p>
                    </div>

                    <span class="rounded-full bg-base-200 px-3 py-1 text-xs font-medium uppercase tracking-wide text-base-content/60">
                      {decision_state_label(@application.status)}
                    </span>
                  </div>

                  <div
                    :if={decision_closed?(@application.status)}
                    class="mt-5 rounded-2xl border border-base-300 bg-base-200/50 p-4 text-sm leading-6 text-base-content/70"
                  >
                    This application has already been finalized. Review notes and decision details remain visible below.
                  </div>

                  <.form
                    :if={!decision_closed?(@application.status)}
                    for={@decision_form}
                    id="accept-tech-application-form"
                    phx-submit="accept"
                    class="mt-5 space-y-4"
                  >
                    <.input
                      field={@decision_form[:review_notes]}
                      type="textarea"
                      label="Internal review notes"
                    />
                    <.input
                      field={@decision_form[:decision_note]}
                      type="textarea"
                      label="Applicant-visible note"
                    />
                    <.input
                      field={@decision_form[:accepted_pay_rate_cents]}
                      type="number"
                      label="Flat pay rate (cents per wash)"
                    />
                    <.input
                      field={@decision_form[:accepted_pay_rate_pct]}
                      type="number"
                      step="0.5"
                      label="Percent pay rate"
                    />
                    <.input
                      field={@decision_form[:assigned_zone]}
                      type="select"
                      options={@zone_options}
                      label="Assigned zone"
                    />
                    <.input
                      field={@decision_form[:van_id]}
                      type="select"
                      options={van_options(@vans)}
                      label="Assigned van"
                    />
                    <input type="hidden" name="decision[active]" value="true" />

                    <div class="flex flex-col gap-3 pt-2 sm:flex-row">
                      <button
                        type="submit"
                        class="inline-flex items-center justify-center rounded-full bg-emerald-600 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-emerald-500"
                      >
                        Accept application
                      </button>
                    </div>
                  </.form>

                  <.form
                    :if={!decision_closed?(@application.status)}
                    for={@decline_form}
                    id="not-accept-tech-application-form"
                    phx-submit="not_accept"
                    class="mt-3 space-y-4 rounded-2xl border border-rose-200 bg-rose-50/40 p-4"
                  >
                    <.input
                      field={@decline_form[:review_notes]}
                      type="textarea"
                      label="Internal review notes"
                    />
                    <.input
                      field={@decline_form[:decision_note]}
                      type="textarea"
                      label="Applicant-visible decline note"
                    />
                    <button
                      type="submit"
                      class="inline-flex items-center justify-center rounded-full border border-rose-300 px-4 py-2.5 text-sm font-semibold text-rose-700 transition hover:border-rose-400 hover:bg-rose-50"
                    >
                      Not accept
                    </button>
                  </.form>

                  <.form
                    :if={@application.status == :pending_review}
                    for={@review_form}
                    id="review-tech-application-form"
                    phx-submit="mark_reviewed"
                    class="mt-4 space-y-4 rounded-2xl border border-base-300 bg-base-200/30 p-4"
                  >
                    <.input
                      field={@review_form[:review_notes]}
                      type="textarea"
                      label="Internal review notes"
                    />
                    <button
                      type="submit"
                      class="inline-flex items-center justify-center rounded-full border border-base-300 px-4 py-2 text-sm font-medium text-base-content/75 transition hover:border-primary/40 hover:text-primary"
                    >
                      Mark reviewed without deciding
                    </button>
                  </.form>
                </section>

                <section class="rounded-2xl border border-base-300 bg-base-100 p-5 shadow-sm">
                  <h2 class="text-sm font-semibold uppercase tracking-[0.18em] text-base-content/55">
                    Current admin notes
                  </h2>

                  <dl class="mt-4 space-y-4 text-sm leading-6">
                    <div>
                      <dt class="text-base-content/50">Review notes</dt>
                      <dd class="mt-1 text-base-content/75">
                        {blank_fallback(@application.review_notes, "No internal notes yet")}
                      </dd>
                    </div>
                    <div>
                      <dt class="text-base-content/50">Decision note</dt>
                      <dd class="mt-1 text-base-content/75">
                        {blank_fallback(@application.decision_note, "No decision note yet")}
                      </dd>
                    </div>
                    <div class="grid gap-3 sm:grid-cols-2">
                      <div>
                        <dt class="text-base-content/50">Reviewed</dt>
                        <dd class="mt-1 text-base-content/75">
                          {datetime_fallback(@application.reviewed_at)}
                        </dd>
                      </div>
                      <div>
                        <dt class="text-base-content/50">Decided</dt>
                        <dd class="mt-1 text-base-content/75">
                          {datetime_fallback(@application.decided_at)}
                        </dd>
                      </div>
                    </div>
                  </dl>
                </section>
              </div>
            </div>
          </div>
        </section>
      </main>
    </Layouts.app>
    """
  end

  defp refresh_show(socket, application) do
    socket
    |> assign(:application, application)
    |> assign(:customer, load_customer!(application.customer_id))
    |> assign(:decision_form, decision_form(application))
    |> assign(:decline_form, decline_form(application))
    |> assign(:review_form, review_form(application))
    |> stream(:applications, load_applications(), reset: true)
  end

  defp ensure_reviewed(%{status: :pending_review} = application, review_notes) do
    mark_reviewed(application, review_notes)
  end

  defp ensure_reviewed(%{status: :reviewed} = application, _review_notes), do: {:ok, application}
  defp ensure_reviewed(%{status: :accepted}, _review_notes), do: {:error, :already_accepted}
  defp ensure_reviewed(%{status: :not_accepted}, _review_notes), do: {:error, :already_declined}
  defp ensure_reviewed(_, _review_notes), do: {:error, :invalid_status}

  defp mark_reviewed(%{status: :pending_review} = application, review_notes) do
    application
    |> Ash.Changeset.for_update(:mark_reviewed, %{review_notes: blank_to_nil(review_notes)})
    |> Ash.update(authorize?: false)
  end

  defp mark_reviewed(_application, _review_notes), do: {:error, :invalid_status}

  defp load_applications do
    TechApplication
    |> Ash.Query.sort(submitted_at: :desc, inserted_at: :desc)
    |> Ash.read!(authorize?: false)
  end

  defp load_vans do
    Van
    |> Ash.Query.sort(name: :asc)
    |> Ash.read!(authorize?: false)
  end

  defp load_application!(id), do: Ash.get!(TechApplication, id, authorize?: false)
  defp load_customer!(id), do: Ash.get!(Customer, id, authorize?: false)

  defp decision_form(application) do
    to_form(
      %{
        "review_notes" => application.review_notes || "",
        "decision_note" => application.decision_note || "",
        "accepted_pay_rate_cents" => application.accepted_pay_rate_cents || 2500,
        "accepted_pay_rate_pct" => pct_for_form(application.accepted_pay_rate_pct),
        "assigned_zone" => atom_to_string(application.assigned_zone),
        "van_id" => application.van_id || ""
      },
      as: :decision
    )
  end

  defp decline_form(application) do
    to_form(
      %{
        "review_notes" => application.review_notes || "",
        "decision_note" => application.decision_note || "Application not accepted at this time."
      },
      as: :not_accept
    )
  end

  defp review_form(application) do
    to_form(
      %{"review_notes" => application.review_notes || ""},
      as: :review
    )
  end

  defp empty_decision_form do
    to_form(
      %{
        "review_notes" => "",
        "decision_note" => "",
        "accepted_pay_rate_cents" => 2500,
        "accepted_pay_rate_pct" => "",
        "assigned_zone" => "",
        "van_id" => ""
      },
      as: :decision
    )
  end

  defp empty_decline_form do
    to_form(
      %{
        "review_notes" => "",
        "decision_note" => "Application not accepted at this time."
      },
      as: :not_accept
    )
  end

  defp empty_review_form, do: to_form(%{"review_notes" => ""}, as: :review)

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil
  defp parse_int(value) when is_integer(value), do: value

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, _rest} -> parsed
      :error -> nil
    end
  end

  defp parse_pct(nil), do: nil
  defp parse_pct(""), do: nil
  defp parse_pct(value), do: Decimal.div(Decimal.new(value), Decimal.new(100))

  defp parse_zone(value) when value in ["nw", "ne", "sw", "se"],
    do: String.to_existing_atom(value)

  defp parse_zone(_value), do: nil

  defp truthy?(value), do: value in [true, "true", "on", 1, "1"]

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(value), do: value

  defp atom_to_string(nil), do: ""
  defp atom_to_string(value), do: to_string(value)

  defp pct_for_form(nil), do: ""

  defp pct_for_form(value) do
    value
    |> Decimal.mult(Decimal.new("100"))
    |> Decimal.normalize()
    |> Decimal.to_string(:normal)
  end

  defp van_options(vans) do
    [{"No van assigned", ""} | Enum.map(vans, &{&1.name, &1.id})]
  end

  defp decision_closed?(status), do: status in [:accepted, :not_accepted]

  defp decision_state_label(:pending_review), do: "Pending"
  defp decision_state_label(:reviewed), do: "Reviewed"
  defp decision_state_label(:accepted), do: "Accepted"
  defp decision_state_label(:not_accepted), do: "Closed"
  defp decision_state_label(_), do: "Draft"

  defp status_label(:draft), do: "Draft"
  defp status_label(:pending_review), do: "Pending review"
  defp status_label(:reviewed), do: "Reviewed"
  defp status_label(:accepted), do: "Accepted"
  defp status_label(:not_accepted), do: "Not accepted"

  defp status_badge_class(:pending_review) do
    "inline-flex items-center rounded-full bg-amber-100 px-3 py-1 text-xs font-semibold uppercase tracking-wide text-amber-800"
  end

  defp status_badge_class(:reviewed) do
    "inline-flex items-center rounded-full bg-sky-100 px-3 py-1 text-xs font-semibold uppercase tracking-wide text-sky-800"
  end

  defp status_badge_class(:accepted) do
    "inline-flex items-center rounded-full bg-emerald-100 px-3 py-1 text-xs font-semibold uppercase tracking-wide text-emerald-800"
  end

  defp status_badge_class(:not_accepted) do
    "inline-flex items-center rounded-full bg-rose-100 px-3 py-1 text-xs font-semibold uppercase tracking-wide text-rose-800"
  end

  defp status_badge_class(_status) do
    "inline-flex items-center rounded-full bg-base-200 px-3 py-1 text-xs font-semibold uppercase tracking-wide text-base-content/70"
  end

  defp zone_label(nil), do: "Any"
  defp zone_label(zone), do: zone |> to_string() |> String.upcase()

  defp experience_label(:none), do: "None"
  defp experience_label(:some), do: "Some"
  defp experience_label(:professional), do: "Professional"
  defp experience_label(_value), do: "Unknown"

  defp yes_no(true), do: "Yes"
  defp yes_no(false), do: "No"

  defp blank_fallback(value, fallback \\ "Not provided")

  defp blank_fallback(nil, fallback), do: fallback
  defp blank_fallback("", fallback), do: fallback
  defp blank_fallback(value, _fallback), do: value

  defp number_fallback(nil), do: "Not provided"
  defp number_fallback(value), do: Integer.to_string(value)

  defp date_fallback(nil), do: "Not provided"
  defp date_fallback(%Date{} = date), do: Calendar.strftime(date, "%b %d, %Y")

  defp format_date(nil), do: "Not submitted"
  defp format_date(%DateTime{} = dt), do: Calendar.strftime(dt, "%b %d, %Y")

  defp datetime_fallback(nil), do: "Not yet"
  defp datetime_fallback(%DateTime{} = dt), do: Calendar.strftime(dt, "%b %d, %Y %I:%M %p")
end
