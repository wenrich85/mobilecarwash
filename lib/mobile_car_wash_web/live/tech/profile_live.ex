defmodule MobileCarWashWeb.Tech.ProfileLive do
  use MobileCarWashWeb, :live_view

  alias MobileCarWash.Operations.{TechApplication, TechEarnings, Technician}

  require Ash.Query

  @impl true
  def mount(_params, _session, socket) do
    customer = socket.assigns.current_customer
    application = application_for_customer(customer)
    technician = technician_for_customer(customer)
    earnings = if technician, do: TechEarnings.earnings_for_period(technician, :week), else: nil

    {:ok,
     socket
     |> assign(:page_title, "Tech Profile")
     |> assign(:application, application)
     |> assign(:technician, technician)
     |> assign(:earnings, earnings), layout: false}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_customer}>
      <main
        id="tech-profile"
        class="mx-auto flex min-h-[calc(100vh-8rem)] w-full max-w-6xl flex-col gap-6 px-4 py-8 sm:px-6 lg:px-8"
      >
        <section class="overflow-hidden rounded-3xl border border-base-300 bg-base-100 shadow-sm">
          <div class="bg-[linear-gradient(135deg,rgba(58,124,165,0.12),rgba(255,255,255,0.94)_52%,rgba(120,177,89,0.12))] px-6 py-8 sm:px-8">
            <div class="flex flex-col gap-6 lg:flex-row lg:items-end lg:justify-between">
              <div class="space-y-3">
                <p class="text-xs font-semibold uppercase tracking-[0.24em] text-primary/80">
                  Private technician profile
                </p>
                <h1 class="text-3xl font-semibold text-base-content sm:text-4xl">
                  {profile_name(@technician, @application, @current_customer)}
                </h1>
                <p class="max-w-2xl text-sm leading-6 text-base-content/70">
                  {profile_subheading(@application, @technician)}
                </p>
              </div>

              <div class="flex flex-wrap gap-3">
                <div class="rounded-2xl border border-base-300 bg-base-100/90 px-4 py-3 shadow-sm">
                  <p class="text-[11px] font-semibold uppercase tracking-[0.2em] text-base-content/45">
                    Status
                  </p>
                  <p class="mt-2 text-sm font-semibold text-base-content">
                    {status_label(@application, @technician)}
                  </p>
                </div>
                <div class="rounded-2xl border border-base-300 bg-base-100/90 px-4 py-3 shadow-sm">
                  <p class="text-[11px] font-semibold uppercase tracking-[0.2em] text-base-content/45">
                    Service zone
                  </p>
                  <p class="mt-2 text-sm font-semibold text-base-content">
                    {active_zone(@application, @technician)}
                  </p>
                </div>
              </div>
            </div>
          </div>

          <div class="grid gap-4 border-t border-base-300 bg-base-100 px-6 py-5 sm:grid-cols-3 sm:px-8">
            <div class="rounded-2xl border border-base-300 bg-base-200/35 p-4">
              <p class="text-[11px] font-semibold uppercase tracking-[0.2em] text-base-content/45">
                Account email
              </p>
              <p class="mt-2 text-sm font-medium text-base-content">{@current_customer.email}</p>
            </div>
            <div class="rounded-2xl border border-base-300 bg-base-200/35 p-4">
              <p class="text-[11px] font-semibold uppercase tracking-[0.2em] text-base-content/45">
                Contact phone
              </p>
              <p class="mt-2 text-sm font-medium text-base-content">
                {contact_phone(@application, @technician, @current_customer)}
              </p>
            </div>
            <div class="rounded-2xl border border-base-300 bg-base-200/35 p-4">
              <p class="text-[11px] font-semibold uppercase tracking-[0.2em] text-base-content/45">
                Pathway
              </p>
              <p class="mt-2 text-sm font-medium text-base-content">
                {pathway_label(@application, @technician)}
              </p>
            </div>
          </div>
        </section>

        <div class="grid gap-6 xl:grid-cols-[minmax(0,1.35fr)_minmax(20rem,0.9fr)]">
          <section id="tech-profile-applicant" class="space-y-6">
            <div class="rounded-3xl border border-base-300 bg-base-100 p-6 shadow-sm">
              <div class="flex items-start justify-between gap-4">
                <div>
                  <h2 class="text-lg font-semibold text-base-content">Applicant profile</h2>
                  <p class="mt-1 text-sm leading-6 text-base-content/65">
                    Application status and technician demographics tied to this customer account.
                  </p>
                </div>

                <.link
                  :if={show_application_link?(@application)}
                  navigate={~p"/tech/apply"}
                  class="inline-flex items-center rounded-full border border-primary/20 bg-primary/10 px-4 py-2 text-sm font-medium text-primary transition-colors duration-150 hover:bg-primary hover:text-primary-content"
                >
                  Continue application
                </.link>
              </div>

              <div :if={@application} class="mt-6 space-y-6">
                <div class="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
                  <.detail_card label="Application status" value={status_label(@application, nil)} />
                  <.detail_card
                    label="Preferred name"
                    value={blank_fallback(@application.preferred_name)}
                  />
                  <.detail_card label="Home ZIP" value={blank_fallback(@application.home_zip)} />
                  <.detail_card
                    label="Preferred zone"
                    value={zone_label(@application.preferred_zone)}
                  />
                  <.detail_card
                    label="Desired hours per week"
                    value={integer_fallback(@application.desired_hours_per_week)}
                  />
                  <.detail_card
                    label="Experience"
                    value={experience_label(@application.experience_level)}
                  />
                </div>

                <div class="grid gap-4 lg:grid-cols-2">
                  <div class="rounded-2xl border border-base-300 bg-base-200/35 p-5">
                    <h3 class="text-sm font-semibold uppercase tracking-[0.2em] text-base-content/55">
                      Availability
                    </h3>

                    <dl class="mt-4 space-y-4">
                      <div>
                        <dt class="text-xs uppercase tracking-wide text-base-content/45">Days</dt>
                        <dd class="mt-1 text-sm font-medium text-base-content">
                          {availability_days(@application)}
                        </dd>
                      </div>
                      <div>
                        <dt class="text-xs uppercase tracking-wide text-base-content/45">Times</dt>
                        <dd class="mt-1 text-sm font-medium text-base-content">
                          {availability_times(@application)}
                        </dd>
                      </div>
                      <div>
                        <dt class="text-xs uppercase tracking-wide text-base-content/45">
                          Earliest start date
                        </dt>
                        <dd class="mt-1 text-sm font-medium text-base-content">
                          {date_fallback(@application.earliest_start_date)}
                        </dd>
                      </div>
                    </dl>
                  </div>

                  <div class="rounded-2xl border border-base-300 bg-base-200/35 p-5">
                    <h3 class="text-sm font-semibold uppercase tracking-[0.2em] text-base-content/55">
                      Requirements
                    </h3>

                    <ul class="mt-4 space-y-3 text-sm text-base-content">
                      <li class="flex items-center gap-3">
                        <span class={flag_dot(@application.has_valid_driver_license)} />
                        <span>Driver license</span>
                      </li>
                      <li class="flex items-center gap-3">
                        <span class={flag_dot(@application.has_reliable_transportation)} />
                        <span>Reliable transportation</span>
                      </li>
                      <li class="flex items-center gap-3">
                        <span class={flag_dot(@application.can_lift_supplies)} />
                        <span>Can lift and carry supplies</span>
                      </li>
                    </ul>

                    <div class="mt-4 rounded-2xl border border-base-300 bg-base-100 px-4 py-3 text-sm text-base-content/70">
                      Emergency contact: {blank_fallback(@application.emergency_contact_name)} / {blank_fallback(
                        @application.emergency_contact_phone
                      )}
                    </div>
                  </div>
                </div>

                <div class="grid gap-4 lg:grid-cols-2">
                  <div class="rounded-2xl border border-base-300 bg-base-100 p-5">
                    <h3 class="text-sm font-semibold uppercase tracking-[0.2em] text-base-content/55">
                      Review notes
                    </h3>
                    <div class="mt-4 space-y-4 text-sm leading-6 text-base-content/75">
                      <p>{blank_fallback(@application.review_notes, "No review notes yet")}</p>
                      <div :if={@application.decision_note}>
                        <p class="text-xs font-semibold uppercase tracking-[0.2em] text-base-content/45">
                          Decision note
                        </p>
                        <p class="mt-1">{@application.decision_note}</p>
                      </div>
                    </div>
                  </div>

                  <div class="rounded-2xl border border-base-300 bg-base-100 p-5">
                    <h3 class="text-sm font-semibold uppercase tracking-[0.2em] text-base-content/55">
                      Application summary
                    </h3>
                    <dl class="mt-4 space-y-4 text-sm">
                      <div>
                        <dt class="text-xs uppercase tracking-wide text-base-content/45">
                          Submitted
                        </dt>
                        <dd class="mt-1 font-medium text-base-content">
                          {datetime_fallback(@application.submitted_at)}
                        </dd>
                      </div>
                      <div>
                        <dt class="text-xs uppercase tracking-wide text-base-content/45">Reviewed</dt>
                        <dd class="mt-1 font-medium text-base-content">
                          {datetime_fallback(@application.reviewed_at)}
                        </dd>
                      </div>
                      <div>
                        <dt class="text-xs uppercase tracking-wide text-base-content/45">
                          Narrative
                        </dt>
                        <dd class="mt-1 text-base-content/75">
                          {blank_fallback(@application.why_work_with_us)}
                        </dd>
                      </div>
                    </dl>
                  </div>
                </div>
              </div>

              <div
                :if={!@application}
                class="mt-6 rounded-2xl border border-dashed border-base-300 bg-base-200/25 p-6"
              >
                <p class="text-sm leading-6 text-base-content/70">
                  No technician application is attached to this account yet.
                </p>
              </div>
            </div>
          </section>

          <aside class="space-y-6">
            <section
              id="tech-profile-technician"
              class="rounded-3xl border border-base-300 bg-base-100 p-6 shadow-sm"
            >
              <div>
                <h2 class="text-lg font-semibold text-base-content">Technician profile</h2>
                <p class="mt-1 text-sm leading-6 text-base-content/65">
                  Private technician-only details appear here once the application is accepted.
                </p>
              </div>

              <div :if={@technician} class="mt-6 space-y-4">
                <div class="grid gap-4 sm:grid-cols-2">
                  <.detail_card label="Technician name" value={blank_fallback(@technician.name)} />
                  <.detail_card label="Assigned zone" value={zone_label(@technician.zone)} />
                  <.detail_card label="Pay rate" value={pay_rate_label(@technician)} />
                  <.detail_card
                    label="Duty status"
                    value={technician_status_label(@technician.status)}
                  />
                  <.detail_card
                    label="Pay period starts"
                    value={pay_period_start_day_label(@technician.pay_period_start_day)}
                  />
                  <.detail_card label="Active" value={yes_no(@technician.active)} />
                </div>
              </div>

              <div
                :if={!@technician}
                class="mt-6 rounded-2xl border border-dashed border-base-300 bg-base-200/25 p-5"
              >
                <p class="text-sm leading-6 text-base-content/70">
                  Technician access is not active yet. Your customer account stays the same while the application is in review.
                </p>
              </div>
            </section>

            <section
              :if={@earnings}
              id="tech-profile-earnings"
              class="rounded-3xl border border-base-300 bg-base-100 p-6 shadow-sm"
            >
              <div>
                <h2 class="text-lg font-semibold text-base-content">This pay period</h2>
                <p class="mt-1 text-sm leading-6 text-base-content/65">
                  {period_label(@earnings.period_start, @earnings.period_end)}
                </p>
              </div>

              <div class="mt-6 grid gap-4 sm:grid-cols-3">
                <div class="rounded-2xl border border-base-300 bg-base-200/35 p-4">
                  <p class="text-[11px] font-semibold uppercase tracking-[0.2em] text-base-content/45">
                    Completed washes
                  </p>
                  <p class="mt-2 text-2xl font-semibold text-base-content">
                    {@earnings.washes_count}
                  </p>
                </div>
                <div class="rounded-2xl border border-base-300 bg-base-200/35 p-4">
                  <p class="text-[11px] font-semibold uppercase tracking-[0.2em] text-base-content/45">
                    Gross earnings
                  </p>
                  <p class="mt-2 text-2xl font-semibold text-base-content">
                    ${format_money(@earnings.total_cents)}
                  </p>
                </div>
                <div class="rounded-2xl border border-base-300 bg-base-200/35 p-4">
                  <p class="text-[11px] font-semibold uppercase tracking-[0.2em] text-base-content/45">
                    Pay model
                  </p>
                  <p class="mt-2 text-sm font-semibold text-base-content">
                    {pay_rate_label(@technician)}
                  </p>
                </div>
              </div>
            </section>
          </aside>
        </div>
      </main>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true

  defp detail_card(assigns) do
    ~H"""
    <div class="rounded-2xl border border-base-300 bg-base-200/35 p-4">
      <p class="text-[11px] font-semibold uppercase tracking-[0.2em] text-base-content/45">
        {@label}
      </p>
      <p class="mt-2 text-sm font-medium text-base-content">{@value}</p>
    </div>
    """
  end

  defp application_for_customer(customer) do
    TechApplication
    |> Ash.Query.for_read(:for_customer, %{customer_id: customer.id})
    |> Ash.read_one!()
  end

  defp technician_for_customer(customer) do
    Technician
    |> Ash.Query.for_read(:for_user_account, %{user_account_id: customer.id})
    |> Ash.read_one!()
  end

  defp profile_name(%{name: name}, _application, _customer), do: blank_fallback(name)
  defp profile_name(nil, %{preferred_name: name}, _customer), do: blank_fallback(name)
  defp profile_name(nil, nil, customer), do: blank_fallback(customer.name, "Customer profile")

  defp profile_subheading(application, technician) do
    cond do
      technician ->
        "Your technician profile, assigned zone, pay model, and current pay-period snapshot all live here."

      application ->
        "Your application details stay private on this page while admin reviews the account."

      true ->
        "Start an application to share your technician details and availability."
    end
  end

  defp pathway_label(application, technician) do
    cond do
      application && application.source == :admin_invite -> "Admin invite"
      technician -> "Accepted technician"
      application -> "Applicant"
      true -> "Customer account only"
    end
  end

  defp status_label(nil, %{active: true}), do: "Accepted"
  defp status_label(nil, %{active: false}), do: "Inactive technician"
  defp status_label(nil, nil), do: "No application"
  defp status_label(%{status: :draft}, _technician), do: "Draft"
  defp status_label(%{status: :pending_review}, _technician), do: "Pending review"
  defp status_label(%{status: :reviewed}, _technician), do: "Reviewed"
  defp status_label(%{status: :accepted}, _technician), do: "Accepted"
  defp status_label(%{status: :not_accepted}, _technician), do: "Not accepted"

  defp active_zone(application, technician) do
    cond do
      technician && technician.zone -> zone_label(technician.zone)
      application && application.assigned_zone -> zone_label(application.assigned_zone)
      application -> zone_label(application.preferred_zone)
      true -> "Not assigned"
    end
  end

  defp show_application_link?(nil), do: true
  defp show_application_link?(%{status: :draft}), do: true
  defp show_application_link?(_application), do: false

  defp contact_phone(application, technician, customer) do
    technician_phone =
      case technician do
        %{phone: phone} -> phone
        _ -> nil
      end

    application_phone =
      case application do
        %{phone: phone} -> phone
        _ -> nil
      end

    technician_phone || application_phone || customer.phone || "Not provided"
  end

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

  defp list_or_fallback(items) do
    items
    |> Enum.map(&String.downcase/1)
    |> Enum.join(", ")
    |> String.capitalize()
  end

  defp flag_dot(true), do: "h-2.5 w-2.5 rounded-full bg-success"
  defp flag_dot(false), do: "h-2.5 w-2.5 rounded-full bg-base-300"

  defp pay_rate_label(%{pay_rate_pct: %Decimal{} = pct}) do
    pct
    |> Decimal.mult(100)
    |> Decimal.round(1)
    |> Decimal.normalize()
    |> Decimal.to_string(:normal)
    |> then(&"#{&1}% of each wash")
  end

  defp pay_rate_label(%{pay_rate_cents: cents}) when is_integer(cents) do
    "$#{format_money(cents)} per wash"
  end

  defp pay_rate_label(_), do: "Not assigned"

  defp technician_status_label(:off_duty), do: "Off duty"
  defp technician_status_label(:available), do: "Available"
  defp technician_status_label(:on_break), do: "On break"
  defp technician_status_label(_), do: "Unknown"

  defp pay_period_start_day_label(1), do: "Monday"
  defp pay_period_start_day_label(2), do: "Tuesday"
  defp pay_period_start_day_label(3), do: "Wednesday"
  defp pay_period_start_day_label(4), do: "Thursday"
  defp pay_period_start_day_label(5), do: "Friday"
  defp pay_period_start_day_label(6), do: "Saturday"
  defp pay_period_start_day_label(7), do: "Sunday"
  defp pay_period_start_day_label(_), do: "Monday"

  defp period_label(%Date{} = period_start, %Date{} = period_end) do
    "#{Calendar.strftime(period_start, "%b %-d")} - #{Calendar.strftime(period_end, "%b %-d, %Y")}"
  end

  defp format_money(cents) when is_integer(cents) do
    dollars = div(cents, 100)
    remainder = rem(cents, 100) |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{dollars}.#{remainder}"
  end

  defp yes_no(true), do: "Yes"
  defp yes_no(false), do: "No"
  defp yes_no(_), do: "No"

  defp blank_fallback(value, fallback \\ "Not provided")
  defp blank_fallback("", fallback), do: fallback
  defp blank_fallback(nil, fallback), do: fallback
  defp blank_fallback(value, _fallback), do: value

  defp integer_fallback(nil), do: "Not provided"
  defp integer_fallback(value), do: Integer.to_string(value)

  defp date_fallback(nil), do: "Not provided"
  defp date_fallback(%Date{} = value), do: Calendar.strftime(value, "%b %-d, %Y")

  defp datetime_fallback(nil), do: "Not yet"

  defp datetime_fallback(%DateTime{} = value) do
    Calendar.strftime(value, "%b %-d, %Y at %I:%M %p UTC")
  end
end
