# Applicant Status Portal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn `/tech/application` into a clearer logged-in applicant status portal without changing admin review behavior.

**Architecture:** Keep the existing `MobileCarWashWeb.Tech.ApplicationLive` and `TechApplication` resource. Add LiveView tests that describe the applicant-facing status states first, then refactor the show-state markup into status journey, next action, submitted details, and applicant-visible decision sections.

**Tech Stack:** Phoenix LiveView, Ash resources, ExUnit, Phoenix.LiveViewTest, Tailwind/DaisyUI classes already used by this app.

## Global Constraints

- Use the existing `/tech/application` route; do not add a new route.
- Use the existing status vocabulary: `draft | pending_review | reviewed | accepted | not_accepted`.
- Do not change admin review transitions or Ash actions.
- Do not add migrations.
- Do not expose `TechApplication.review_notes` on `/tech/application`.
- Show `TechApplication.decision_note` only for final decision states.
- Preserve applicant ownership through `TechApplication` read action `:for_customer` using the signed-in customer id.
- Follow test-driven development: write failing tests, verify red, implement, verify green.

---

## File Structure

- Modify `test/mobile_car_wash_web/live/tech/application_live_test.exs`: add status portal tests and helpers for reviewed/accepted/not accepted application states.
- Modify `lib/mobile_car_wash_web/live/tech/application_live.ex`: replace the basic show-state status area with a status journey, next-action panel, submitted detail sections, and privacy-safe note rendering.
- No new modules, migrations, or routes.

---

### Task 1: Applicant Status Portal Tests

**Files:**
- Modify: `test/mobile_car_wash_web/live/tech/application_live_test.exs`

**Interfaces:**
- Consumes: existing `customer_fixture/0`, `sign_in/2`, `application_attrs/0`, `create_application!/2`.
- Produces: failing tests for the status portal UI elements that Task 2 must implement.

- [ ] **Step 1: Add helper functions for status transitions**

Add these helpers below `create_application!/2`:

```elixir
  defp submit_application!(application) do
    application
    |> Ash.Changeset.for_update(:submit, %{})
    |> Ash.update!(authorize?: false)
  end

  defp review_application!(application, review_notes \\ "Internal review note") do
    application
    |> Ash.Changeset.for_update(:mark_reviewed, %{review_notes: review_notes})
    |> Ash.update!(authorize?: false)
  end

  defp accept_application!(application, attrs \\ %{}) do
    application
    |> Ash.Changeset.for_update(
      :accept,
      Map.merge(
        %{
          review_notes: "Internal accepted note",
          decision_note: "Welcome to the technician team.",
          accepted_pay_rate_cents: 3500,
          accepted_pay_rate_pct: nil,
          assigned_zone: :sw,
          active: true
        },
        attrs
      )
    )
    |> Ash.update!(authorize?: false)
  end

  defp not_accept_application!(application, attrs \\ %{}) do
    application
    |> Ash.Changeset.for_update(
      :not_accept,
      Map.merge(
        %{
          review_notes: "Internal decline note",
          decision_note: "We are moving forward with other applicants."
        },
        attrs
      )
    )
    |> Ash.update!(authorize?: false)
  end
```

- [ ] **Step 2: Add no-application portal test**

Append this test:

```elixir
  test "status portal invites signed-in customers without an application to start", %{conn: conn} do
    customer = customer_fixture()

    {:ok, view, _html} =
      conn
      |> sign_in(customer)
      |> live(~p"/tech/application")

    assert has_element?(view, "#tech-application-status")
    assert has_element?(view, "#tech-application-journey")
    assert has_element?(view, "#tech-application-next-action a[href='/tech/apply']")
    assert render(view) =~ "Start an application to share your availability and technician details."
  end
```

- [ ] **Step 3: Add pending/reviewed/final decision tests**

Append these tests:

```elixir
  test "pending review portal shows waiting guidance and hides internal review notes", %{conn: conn} do
    customer = customer_fixture()

    customer
    |> create_application!()
    |> submit_application!()

    {:ok, view, _html} =
      conn
      |> sign_in(customer)
      |> live(~p"/tech/application")

    html = render(view)

    assert has_element?(view, "#tech-application-journey")
    assert has_element?(view, "#journey-step-pending_review[data-state='current']")
    assert html =~ "No action needed right now. We will review your application and update this page."
    refute html =~ "Internal review note"
  end

  test "reviewed portal shows final decision pending copy and reviewed timestamp", %{conn: conn} do
    customer = customer_fixture()

    customer
    |> create_application!()
    |> submit_application!()
    |> review_application!("Internal review note")

    {:ok, view, _html} =
      conn
      |> sign_in(customer)
      |> live(~p"/tech/application")

    html = render(view)

    assert has_element?(view, "#journey-step-reviewed[data-state='current']")
    assert html =~ "A final decision is still pending. Watch this page for the next update."
    assert html =~ "Reviewed"
    refute html =~ "Internal review note"
  end

  test "accepted portal links to technician profile and tools", %{conn: conn} do
    customer = customer_fixture()

    customer
    |> create_application!()
    |> submit_application!()
    |> review_application!("Internal accepted note")
    |> accept_application!()

    {:ok, view, _html} =
      conn
      |> sign_in(customer)
      |> live(~p"/tech/application")

    html = render(view)

    assert has_element?(view, "#journey-step-decision[data-state='current']")
    assert has_element?(view, "#tech-application-next-action a[href='/tech/profile']")
    assert has_element?(view, "#tech-application-next-action a[href='/tech']")
    assert html =~ "Welcome to the technician team."
    refute html =~ "Internal accepted note"
  end

  test "not accepted portal shows applicant-visible decision note only", %{conn: conn} do
    customer = customer_fixture()

    customer
    |> create_application!()
    |> submit_application!()
    |> review_application!("Internal decline note")
    |> not_accept_application!()

    {:ok, view, _html} =
      conn
      |> sign_in(customer)
      |> live(~p"/tech/application")

    html = render(view)

    assert has_element?(view, "#journey-step-decision[data-state='current']")
    assert html =~ "We are moving forward with other applicants."
    refute html =~ "Internal decline note"
  end
```

- [ ] **Step 4: Extend submitted details test**

Update the existing `"status page shows submitted application status"` test to assert core details:

```elixir
    assert has_element?(view, "#tech-application-details")
    assert render(view) =~ application.preferred_name
    assert render(view) =~ "+15125550200"
    assert render(view) =~ "NW"
    assert render(view) =~ "Weekdays"
    assert render(view) =~ "Mornings"
    assert render(view) =~ "I enjoy mobile work."
```

- [ ] **Step 5: Run tests to verify red**

Run:

```bash
mix test test/mobile_car_wash_web/live/tech/application_live_test.exs
```

Expected:

- Fails because `#tech-application-journey`, `#tech-application-next-action`, status step ids, and richer detail sections do not exist yet.
- No compile errors.

---

### Task 2: Applicant Portal Rendering

**Files:**
- Modify: `lib/mobile_car_wash_web/live/tech/application_live.ex`

**Interfaces:**
- Consumes: `@application`, existing route helpers `~p"/tech/apply"`, `~p"/tech/profile"`, `~p"/tech"`.
- Produces: DOM ids and privacy behavior asserted by Task 1 tests:
  - `#tech-application-status`
  - `#tech-application-journey`
  - `#tech-application-next-action`
  - `#tech-application-details`
  - `#journey-step-draft`
  - `#journey-step-pending_review`
  - `#journey-step-reviewed`
  - `#journey-step-decision`

- [ ] **Step 1: Replace the show-state status markup**

Inside `render/1`, replace the current `<div :if={@live_action == :show} id="tech-application-status" ...>` block with:

```heex
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

            <section :if={@application && final_decision?(@application)} class="rounded-2xl border border-base-300 bg-base-100 p-5 shadow-sm">
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
                  <.detail_item label="Preferred zone" value={zone_label(@application.preferred_zone)} />
                  <.detail_item label="Experience" value={experience_label(@application.experience_level)} />
                  <.detail_item label="Desired hours" value={number_fallback(@application.desired_hours_per_week)} />
                  <.detail_item label="Earliest start" value={date_fallback(@application.earliest_start_date)} />
                  <.detail_item label="Submitted" value={datetime_fallback(@application.submitted_at)} />
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
                  <.detail_item label="Driver license" value={yes_no(@application.has_valid_driver_license)} />
                  <.detail_item label="Transportation" value={yes_no(@application.has_reliable_transportation)} />
                  <.detail_item label="Can lift supplies" value={yes_no(@application.can_lift_supplies)} />
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
```

- [ ] **Step 2: Add HEEx helper components**

Add below `render/1`:

```elixir
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
```

- [ ] **Step 3: Add status journey helper functions**

Add near existing status helper functions:

```elixir
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
  defp journey_state(status, step) when status in [:accepted, :not_accepted] and step in [:draft, :pending_review, :reviewed], do: "complete"
  defp journey_state(status, :decision) when status in [:accepted, :not_accepted], do: "current"
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
```

- [ ] **Step 4: Add detail formatting helpers**

Add near existing formatting helpers:

```elixir
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

  defp date_fallback(nil), do: "Not provided"
  defp date_fallback(%Date{} = value), do: Calendar.strftime(value, "%b %-d, %Y")
```

- [ ] **Step 5: Update status copy**

Replace these existing functions with the spec copy:

```elixir
  defp status_message(nil),
    do: "Start an application to share your availability and technician details."

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

  defp next_step_message(%{status: :pending_review}),
    do: "No action needed right now. We will review your application and update this page."

  defp next_step_message(%{status: :reviewed}),
    do: "A final decision is still pending. Watch this page for the next update."

  defp next_step_message(%{status: :accepted}),
    do: "Your technician profile is ready. Use your profile to review pay, zone, and account details."

  defp next_step_message(%{status: :not_accepted}),
    do: "You can keep using this customer account normally. Any applicant-visible note from the team appears below."
```

Keep the existing `:draft` status copy.

- [ ] **Step 6: Run tests to verify green**

Run:

```bash
mix test test/mobile_car_wash_web/live/tech/application_live_test.exs
```

Expected:

- All tests in `application_live_test.exs` pass.

---

### Task 3: Focused Regression Verification and Commit

**Files:**
- Modify: no additional files unless formatting changes.

**Interfaces:**
- Consumes: Task 1 tests and Task 2 implementation.
- Produces: formatted, committed applicant status portal slice.

- [ ] **Step 1: Format touched files**

Run:

```bash
mix format lib/mobile_car_wash_web/live/tech/application_live.ex test/mobile_car_wash_web/live/tech/application_live_test.exs
```

Expected:

- Command exits 0.

- [ ] **Step 2: Run focused LiveView regression tests**

Run:

```bash
mix test test/mobile_car_wash_web/live/tech/application_live_test.exs test/mobile_car_wash_web/live/tech/profile_live_test.exs test/mobile_car_wash_web/live/admin/tech_applications_live_test.exs
```

Expected:

- All tests pass.
- No applicant status page renders internal `review_notes`.

- [ ] **Step 3: Inspect git diff**

Run:

```bash
git diff -- lib/mobile_car_wash_web/live/tech/application_live.ex test/mobile_car_wash_web/live/tech/application_live_test.exs
```

Expected:

- Diff is limited to applicant portal rendering/helpers and tests.
- No admin review transition changes.

- [ ] **Step 4: Commit implementation**

Run:

```bash
git add lib/mobile_car_wash_web/live/tech/application_live.ex test/mobile_car_wash_web/live/tech/application_live_test.exs
git commit -m "Improve applicant status portal"
```

Expected:

- Commit succeeds.

- [ ] **Step 5: Run final pre-merge verification**

Run:

```bash
mix precommit
```

Expected:

- Full project precommit exits 0.
- Known existing Ash notification warnings may appear, but no test failures are acceptable.

---

## Self-Review

- Spec coverage: The plan covers no-application, draft, pending review, reviewed, accepted, not accepted, submitted details, accepted actions, and review-note privacy.
- Placeholder scan: No placeholders or deferred implementation notes remain.
- Type consistency: All helpers consume existing `TechApplication` structs and route helpers from `MobileCarWashWeb.Tech.ApplicationLive`; test helpers use existing Ash action names.
