# Tech Flow Applicant Profile Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a private technician applicant portal, admin approval workflow, tech profile page, and clearer field-work paths for accepted technicians.

**Architecture:** Add a `TechApplication` Ash resource in the Operations domain tied to the existing `Customer` login identity. Applicant-facing pages live in the authenticated browser session so normal customers can apply without becoming technicians; operational technician pages remain behind technician/admin role checks. Admin acceptance promotes the existing customer account to `:technician` and creates or links a `Technician` record.

**Tech Stack:** Phoenix 1.8 LiveView, Ash 3, AshPostgres, Ecto migrations, ExUnit, Phoenix.LiveViewTest, Tailwind CSS v4.

## Global Constraints

- Run `mix precommit` when all implementation changes are done and fix pending issues.
- Use existing `Customer` accounts for applicants; do not create a separate applicant identity.
- Do not add public technician profile pages or public technician directories.
- New LiveView templates must begin with `<Layouts.app flash={@flash} current_scope={@current_customer}>`.
- Use the imported `<.input>` component for form fields when available.
- Use `<.icon>` for icons; do not use Heroicons modules directly.
- Use Tailwind CSS classes and custom CSS rules; do not use `@apply`.
- Use only `app.js` and `app.css` bundles; do not add inline `<script>` tags.
- Use `mix ecto.gen.migration migration_name_using_underscores` for migrations.
- Keep existing user-owned worktree changes untouched.

---

## File Structure

Create:

- `lib/mobile_car_wash/operations/tech_application.ex`
  - Ash resource for applicant data, status transitions, and acceptance.
- `test/mobile_car_wash/operations/tech_application_test.exs`
  - Resource/state-transition tests.
- `lib/mobile_car_wash_web/live/tech/application_live.ex`
  - Applicant-facing apply/status LiveView.
- `test/mobile_car_wash_web/live/tech/application_live_test.exs`
  - Applicant flow tests.
- `lib/mobile_car_wash_web/live/admin/tech_applications_live.ex`
  - Admin application queue and review detail LiveView.
- `test/mobile_car_wash_web/live/admin/tech_applications_live_test.exs`
  - Admin review/acceptance tests.
- `lib/mobile_car_wash_web/live/tech/profile_live.ex`
  - Private applicant/technician profile page.
- `test/mobile_car_wash_web/live/tech/profile_live_test.exs`
  - Profile visibility and content tests.
- `lib/mobile_car_wash_web/live/tech/job_live.ex`
  - One-appointment job brief page for accepted technicians.
- `test/mobile_car_wash_web/live/tech/job_live_test.exs`
  - Job brief CTA and authorization tests.

Modify:

- `lib/mobile_car_wash/operations/operations.ex`
  - Register `MobileCarWash.Operations.TechApplication`.
- `lib/mobile_car_wash_web/router.ex`
  - Add applicant/profile routes in authenticated live session, admin application routes in admin live session, and job brief route in technician live session.
- `lib/mobile_car_wash_web/live/tech/tech_dashboard_live.ex`
  - Prioritize next action and link appointment rows to job brief.
- `lib/mobile_car_wash_web/live/checklist_live.ex`
  - Add active-step-focused layout and wrap-up area.

Generated:

- `priv/repo/migrations/<timestamp>_create_tech_applications.exs`
  - Created via `mix ecto.gen.migration create_tech_applications`.

---

### Task 1: TechApplication Resource And State Transitions

**Files:**
- Create: `lib/mobile_car_wash/operations/tech_application.ex`
- Modify: `lib/mobile_car_wash/operations/operations.ex`
- Generate: `priv/repo/migrations/<timestamp>_create_tech_applications.exs`
- Test: `test/mobile_car_wash/operations/tech_application_test.exs`

**Interfaces:**
- Produces: `MobileCarWash.Operations.TechApplication`
- Produces action: `:save_draft` accepting applicant-editable fields
- Produces action: `:submit` changing `status` to `:pending_review`
- Produces action: `:mark_reviewed` accepting `:review_notes` and changing `status` to `:reviewed`
- Produces action: `:not_accept` accepting `:review_notes` and `:decision_note` and changing `status` to `:not_accepted`
- Produces action: `:accept` accepting `:review_notes`, `:decision_note`, `:accepted_pay_rate_cents`, `:accepted_pay_rate_pct`, `:assigned_zone`, `:van_id`, and `:active`
- Produces read action: `:for_customer` with argument `customer_id`

- [ ] **Step 1: Write failing resource tests**

Create `test/mobile_car_wash/operations/tech_application_test.exs`:

```elixir
defmodule MobileCarWash.Operations.TechApplicationTest do
  use MobileCarWash.DataCase, async: true

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Operations.{TechApplication, Technician}

  defp customer_fixture do
    {:ok, customer} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "tech-applicant-#{System.unique_integer([:positive])}@example.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Applicant One",
        phone: "+15125550100"
      })
      |> Ash.create()

    customer
  end

  describe "application lifecycle" do
    test "customer can create and submit a draft application" do
      customer = customer_fixture()

      {:ok, application} =
        TechApplication
        |> Ash.Changeset.for_create(:create, %{
          preferred_name: "App One",
          phone: "+15125550100",
          home_zip: "78259",
          preferred_zone: :nw,
          availability_weekdays: true,
          availability_weekends: false,
          availability_mornings: true,
          availability_afternoons: true,
          availability_evenings: false,
          experience_level: :some,
          has_valid_driver_license: true,
          has_reliable_transportation: true,
          can_lift_supplies: true,
          desired_hours_per_week: 20,
          earliest_start_date: Date.utc_today(),
          emergency_contact_name: "Backup Person",
          emergency_contact_phone: "+15125550101",
          why_work_with_us: "I like clean cars and field work.",
          experience_notes: "Weekend detailing for neighbors.",
          schedule_notes: "Prefer mornings."
        })
        |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
        |> Ash.create(authorize?: false)

      assert application.status == :draft

      {:ok, submitted} =
        application
        |> Ash.Changeset.for_update(:submit, %{})
        |> Ash.update(authorize?: false)

      assert submitted.status == :pending_review
      assert submitted.submitted_at
    end

    test "accepting promotes customer and creates linked technician" do
      customer = customer_fixture()

      {:ok, application} =
        TechApplication
        |> Ash.Changeset.for_create(:create, %{
          preferred_name: "Accepted Tech",
          phone: "+15125550102",
          home_zip: "78259",
          preferred_zone: :se,
          availability_weekdays: true,
          availability_weekends: true,
          availability_mornings: true,
          availability_afternoons: false,
          availability_evenings: false,
          experience_level: :professional,
          has_valid_driver_license: true,
          has_reliable_transportation: true,
          can_lift_supplies: true,
          desired_hours_per_week: 30,
          earliest_start_date: Date.utc_today(),
          emergency_contact_name: "Emergency Contact",
          emergency_contact_phone: "+15125550103",
          why_work_with_us: "I want consistent work.",
          experience_notes: "Two years of mobile detailing.",
          schedule_notes: "Weekdays preferred."
        })
        |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
        |> Ash.create(authorize?: false)

      {:ok, accepted} =
        application
        |> Ash.Changeset.for_update(:accept, %{
          review_notes: "Strong applicant.",
          decision_note: "Welcome aboard.",
          accepted_pay_rate_cents: 3000,
          accepted_pay_rate_pct: nil,
          assigned_zone: :se,
          van_id: nil,
          active: true
        })
        |> Ash.update(authorize?: false)

      assert accepted.status == :accepted
      assert accepted.decided_at

      reloaded_customer = Ash.get!(Customer, customer.id, authorize?: false)
      assert reloaded_customer.role == :technician

      technicians = Ash.read!(Technician, authorize?: false)
      technician = Enum.find(technicians, &(&1.user_account_id == customer.id))
      assert technician.name == "Accepted Tech"
      assert technician.phone == "+15125550102"
      assert technician.zone == :se
      assert technician.pay_rate_cents == 3000
      assert technician.active == true
    end

    test "not_accept leaves customer role unchanged" do
      customer = customer_fixture()

      {:ok, application} =
        TechApplication
        |> Ash.Changeset.for_create(:create, %{
          preferred_name: "Declined Applicant",
          phone: "+15125550104",
          home_zip: "78259",
          preferred_zone: :ne,
          availability_weekdays: false,
          availability_weekends: true,
          availability_mornings: false,
          availability_afternoons: true,
          availability_evenings: true,
          experience_level: :none,
          has_valid_driver_license: false,
          has_reliable_transportation: true,
          can_lift_supplies: true,
          desired_hours_per_week: 10,
          earliest_start_date: Date.utc_today(),
          emergency_contact_name: "Emergency Contact",
          emergency_contact_phone: "+15125550105",
          why_work_with_us: "I want to learn.",
          experience_notes: "No prior experience.",
          schedule_notes: "Weekends only."
        })
        |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
        |> Ash.create(authorize?: false)

      {:ok, declined} =
        application
        |> Ash.Changeset.for_update(:not_accept, %{
          review_notes: "Needs valid license first.",
          decision_note: "Please apply again when your license is active."
        })
        |> Ash.update(authorize?: false)

      assert declined.status == :not_accepted
      assert Ash.get!(Customer, customer.id, authorize?: false).role == :customer
    end
  end
end
```

- [ ] **Step 2: Run failing resource tests**

Run:

```bash
mix test test/mobile_car_wash/operations/tech_application_test.exs
```

Expected: fail because `MobileCarWash.Operations.TechApplication` is not defined.

- [ ] **Step 3: Generate migration**

Run:

```bash
mix ecto.gen.migration create_tech_applications
```

Expected: prints a path like `priv/repo/migrations/20260708HHMMSS_create_tech_applications.exs`.

- [ ] **Step 4: Implement migration**

Replace the generated migration body with:

```elixir
defmodule MobileCarWash.Repo.Migrations.CreateTechApplications do
  use Ecto.Migration

  def change do
    create table(:tech_applications, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :customer_id, references(:customers, type: :uuid, on_delete: :delete_all), null: false
      add :status, :text, null: false, default: "draft"
      add :preferred_name, :text, null: false
      add :phone, :text
      add :home_zip, :text
      add :preferred_zone, :text
      add :availability_weekdays, :boolean, null: false, default: false
      add :availability_weekends, :boolean, null: false, default: false
      add :availability_mornings, :boolean, null: false, default: false
      add :availability_afternoons, :boolean, null: false, default: false
      add :availability_evenings, :boolean, null: false, default: false
      add :experience_level, :text, null: false, default: "none"
      add :has_valid_driver_license, :boolean, null: false, default: false
      add :has_reliable_transportation, :boolean, null: false, default: false
      add :can_lift_supplies, :boolean, null: false, default: false
      add :desired_hours_per_week, :integer
      add :earliest_start_date, :date
      add :emergency_contact_name, :text
      add :emergency_contact_phone, :text
      add :why_work_with_us, :text
      add :experience_notes, :text
      add :schedule_notes, :text
      add :review_notes, :text
      add :decision_note, :text
      add :accepted_pay_rate_cents, :integer
      add :accepted_pay_rate_pct, :decimal
      add :assigned_zone, :text
      add :van_id, references(:vans, type: :uuid, on_delete: :nilify_all)
      add :active, :boolean, null: false, default: true
      add :submitted_at, :utc_datetime_usec
      add :reviewed_at, :utc_datetime_usec
      add :decided_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:tech_applications, [:customer_id])
    create index(:tech_applications, [:status])
  end
end
```

- [ ] **Step 5: Implement resource**

Create `lib/mobile_car_wash/operations/tech_application.ex`:

```elixir
defmodule MobileCarWash.Operations.TechApplication do
  @moduledoc """
  Private technician application tied to an existing Customer account.
  """
  use Ash.Resource,
    otp_app: :mobile_car_wash,
    domain: MobileCarWash.Operations,
    data_layer: AshPostgres.DataLayer

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Operations.Technician

  require Ash.Query

  postgres do
    table("tech_applications")
    repo(MobileCarWash.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :status, :atom do
      constraints(one_of: [:draft, :pending_review, :reviewed, :accepted, :not_accepted])
      default(:draft)
      allow_nil?(false)
      public?(true)
    end

    attribute(:preferred_name, :string, allow_nil?: false, public?: true)
    attribute(:phone, :string, public?: true)
    attribute(:home_zip, :string, public?: true)

    attribute :preferred_zone, :atom do
      constraints(one_of: [:nw, :ne, :sw, :se])
      public?(true)
    end

    attribute(:availability_weekdays, :boolean, default: false, allow_nil?: false, public?: true)
    attribute(:availability_weekends, :boolean, default: false, allow_nil?: false, public?: true)
    attribute(:availability_mornings, :boolean, default: false, allow_nil?: false, public?: true)
    attribute(:availability_afternoons, :boolean, default: false, allow_nil?: false, public?: true)
    attribute(:availability_evenings, :boolean, default: false, allow_nil?: false, public?: true)

    attribute :experience_level, :atom do
      constraints(one_of: [:none, :some, :professional])
      default(:none)
      allow_nil?(false)
      public?(true)
    end

    attribute(:has_valid_driver_license, :boolean, default: false, allow_nil?: false, public?: true)
    attribute(:has_reliable_transportation, :boolean, default: false, allow_nil?: false, public?: true)
    attribute(:can_lift_supplies, :boolean, default: false, allow_nil?: false, public?: true)
    attribute(:desired_hours_per_week, :integer, public?: true)
    attribute(:earliest_start_date, :date, public?: true)
    attribute(:emergency_contact_name, :string, public?: true)
    attribute(:emergency_contact_phone, :string, public?: true)
    attribute(:why_work_with_us, :string, public?: true)
    attribute(:experience_notes, :string, public?: true)
    attribute(:schedule_notes, :string, public?: true)
    attribute(:review_notes, :string, public?: true)
    attribute(:decision_note, :string, public?: true)
    attribute(:accepted_pay_rate_cents, :integer, public?: true)
    attribute(:accepted_pay_rate_pct, :decimal, public?: true)

    attribute :assigned_zone, :atom do
      constraints(one_of: [:nw, :ne, :sw, :se])
      public?(true)
    end

    attribute(:active, :boolean, default: true, allow_nil?: false, public?: true)
    attribute(:submitted_at, :utc_datetime_usec, public?: true)
    attribute(:reviewed_at, :utc_datetime_usec, public?: true)
    attribute(:decided_at, :utc_datetime_usec, public?: true)

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :customer, Customer do
      allow_nil?(false)
      public?(true)
    end

    belongs_to :van, MobileCarWash.Operations.Van do
      allow_nil?(true)
      public?(true)
    end
  end

  identities do
    identity(:unique_customer_application, [:customer_id])
  end

  actions do
    defaults([:read, create: :*, update: :*])

    read :for_customer do
      argument(:customer_id, :uuid, allow_nil?: false)
      filter(expr(customer_id == ^arg(:customer_id)))
    end

    update :save_draft do
      require_atomic?(false)
      accept(applicant_fields())
      change(set_attribute(:status, :draft))
    end

    update :submit do
      require_atomic?(false)
      validate(present([:preferred_name, :home_zip, :desired_hours_per_week]))
      change(set_attribute(:status, :pending_review))
      change(set_attribute(:submitted_at, &DateTime.utc_now/0))
    end

    update :mark_reviewed do
      require_atomic?(false)
      accept([:review_notes, :decision_note])
      change(set_attribute(:status, :reviewed))
      change(set_attribute(:reviewed_at, &DateTime.utc_now/0))
    end

    update :not_accept do
      require_atomic?(false)
      accept([:review_notes, :decision_note])
      change(set_attribute(:status, :not_accepted))
      change(set_attribute(:decided_at, &DateTime.utc_now/0))
    end

    update :accept do
      require_atomic?(false)

      accept([
        :review_notes,
        :decision_note,
        :accepted_pay_rate_cents,
        :accepted_pay_rate_pct,
        :assigned_zone,
        :van_id,
        :active
      ])

      change(set_attribute(:status, :accepted))
      change(set_attribute(:decided_at, &DateTime.utc_now/0))
      change(after_action(&promote_customer_to_technician/3))
    end
  end

  def applicant_fields do
    [
      :preferred_name,
      :phone,
      :home_zip,
      :preferred_zone,
      :availability_weekdays,
      :availability_weekends,
      :availability_mornings,
      :availability_afternoons,
      :availability_evenings,
      :experience_level,
      :has_valid_driver_license,
      :has_reliable_transportation,
      :can_lift_supplies,
      :desired_hours_per_week,
      :earliest_start_date,
      :emergency_contact_name,
      :emergency_contact_phone,
      :why_work_with_us,
      :experience_notes,
      :schedule_notes
    ]
  end

  defp promote_customer_to_technician(_changeset, application, _context) do
    customer = Ash.get!(Customer, application.customer_id, authorize?: false)

    customer
    |> Ash.Changeset.for_update(:update, %{role: :technician})
    |> Ash.update!(authorize?: false)

    technician =
      Technician
      |> Ash.Query.filter(user_account_id == ^customer.id)
      |> Ash.read_one!(authorize?: false)

    attrs = %{
      name: application.preferred_name,
      phone: application.phone || customer.phone,
      active: application.active,
      zone: application.assigned_zone || application.preferred_zone,
      pay_rate_cents: application.accepted_pay_rate_cents || 2500,
      pay_rate_pct: application.accepted_pay_rate_pct,
      van_id: application.van_id
    }

    if technician do
      technician
      |> Ash.Changeset.for_update(:update, attrs)
      |> Ash.Changeset.force_change_attribute(:user_account_id, customer.id)
      |> Ash.update!(authorize?: false)
    else
      Technician
      |> Ash.Changeset.for_create(:create, attrs)
      |> Ash.Changeset.force_change_attribute(:user_account_id, customer.id)
      |> Ash.create!(authorize?: false)
    end

    {:ok, application}
  end
end
```

- [ ] **Step 6: Register resource in Operations domain**

Modify `lib/mobile_car_wash/operations/operations.ex`:

```elixir
resources do
  resource(MobileCarWash.Operations.Technician)
  resource(MobileCarWash.Operations.TechApplication)
  resource(MobileCarWash.Operations.Van)
  resource(MobileCarWash.Operations.OrgPosition)
  resource(MobileCarWash.Operations.PositionContract)
  resource(MobileCarWash.Operations.Procedure)
  resource(MobileCarWash.Operations.ProcedureStep)
  resource(MobileCarWash.Operations.AppointmentChecklist)
  resource(MobileCarWash.Operations.ChecklistItem)
  resource(MobileCarWash.Operations.Photo)
end
```

- [ ] **Step 7: Run focused tests**

Run:

```bash
mix format lib/mobile_car_wash/operations/tech_application.ex lib/mobile_car_wash/operations/operations.ex test/mobile_car_wash/operations/tech_application_test.exs
mix test test/mobile_car_wash/operations/tech_application_test.exs
```

Expected: tests pass.

- [ ] **Step 8: Commit**

Run:

```bash
git add lib/mobile_car_wash/operations/tech_application.ex lib/mobile_car_wash/operations/operations.ex priv/repo/migrations/*_create_tech_applications.exs test/mobile_car_wash/operations/tech_application_test.exs
git commit -m "Add tech application resource"
```

---

### Task 2: Applicant Apply And Status Pages

**Files:**
- Create: `lib/mobile_car_wash_web/live/tech/application_live.ex`
- Modify: `lib/mobile_car_wash_web/router.ex`
- Test: `test/mobile_car_wash_web/live/tech/application_live_test.exs`

**Interfaces:**
- Consumes: `MobileCarWash.Operations.TechApplication`
- Produces route: `GET /tech/apply`
- Produces route: `GET /tech/application`

- [ ] **Step 1: Write failing LiveView tests**

Create `test/mobile_car_wash_web/live/tech/application_live_test.exs`:

```elixir
defmodule MobileCarWashWeb.Tech.ApplicationLiveTest do
  use MobileCarWashWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Operations.TechApplication

  defp customer_fixture do
    {:ok, customer} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "apply-#{System.unique_integer([:positive])}@example.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Apply Customer",
        phone: "+15125550200"
      })
      |> Ash.create()

    customer
  end

  defp sign_in(conn, customer) do
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> post("/auth/customer/password/sign_in", %{
      "customer" => %{
        "email" => to_string(customer.email),
        "password" => "Password123!"
      }
    })
    |> recycle()
  end

  test "anonymous visitors are redirected to sign in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/tech/apply")
  end

  test "signed-in customer can save a draft and submit it", %{conn: conn} do
    customer = customer_fixture()
    conn = sign_in(conn, customer)

    {:ok, view, _html} = live(conn, ~p"/tech/apply")
    assert has_element?(view, "#tech-application-form")

    view
    |> form("#tech-application-form", %{
      "application" => %{
        "preferred_name" => "Apply Customer",
        "phone" => "+15125550200",
        "home_zip" => "78259",
        "preferred_zone" => "nw",
        "availability_weekdays" => "true",
        "availability_weekends" => "false",
        "availability_mornings" => "true",
        "availability_afternoons" => "true",
        "availability_evenings" => "false",
        "experience_level" => "some",
        "has_valid_driver_license" => "true",
        "has_reliable_transportation" => "true",
        "can_lift_supplies" => "true",
        "desired_hours_per_week" => "20",
        "earliest_start_date" => Date.to_iso8601(Date.utc_today()),
        "emergency_contact_name" => "Emergency Person",
        "emergency_contact_phone" => "+15125550201",
        "why_work_with_us" => "I enjoy mobile work.",
        "experience_notes" => "Some detail work.",
        "schedule_notes" => "Mornings are best."
      }
    })
    |> render_submit()

    [application] = Ash.read!(TechApplication, authorize?: false)
    assert application.status == :draft

    view
    |> element("#submit-tech-application")
    |> render_click()

    application = Ash.get!(TechApplication, application.id, authorize?: false)
    assert application.status == :pending_review
  end

  test "status page shows submitted application status", %{conn: conn} do
    customer = customer_fixture()

    {:ok, application} =
      TechApplication
      |> Ash.Changeset.for_create(:create, %{
        preferred_name: "Apply Customer",
        home_zip: "78259",
        status: :pending_review
      })
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create(authorize?: false)

    conn = sign_in(conn, customer)
    {:ok, view, _html} = live(conn, ~p"/tech/application")

    assert has_element?(view, "#tech-application-status")
    assert render(view) =~ "Pending review"
    assert render(view) =~ application.preferred_name
  end
end
```

- [ ] **Step 2: Run failing tests**

Run:

```bash
mix test test/mobile_car_wash_web/live/tech/application_live_test.exs
```

Expected: fail because routes and LiveView are missing.

- [ ] **Step 3: Add authenticated routes**

In `lib/mobile_car_wash_web/router.ex`, inside the existing `live_session :authenticated` block, add these before the account routes:

```elixir
live "/tech/apply", Tech.ApplicationLive, :apply
live "/tech/application", Tech.ApplicationLive, :show
live "/tech/profile", Tech.ProfileLive
```

- [ ] **Step 4: Implement applicant LiveView**

Create `lib/mobile_car_wash_web/live/tech/application_live.ex`:

```elixir
defmodule MobileCarWashWeb.Tech.ApplicationLive do
  use MobileCarWashWeb, :live_view

  alias MobileCarWash.Operations.TechApplication

  require Ash.Query

  @impl true
  def mount(_params, _session, socket) do
    customer = socket.assigns.current_customer
    application = application_for_customer(customer)

    {:ok,
     assign(socket,
       page_title: "Technician Application",
       application: application,
       form: to_form(form_params(application, customer), as: :application)
     )}
  end

  @impl true
  def handle_params(_params, _uri, %{assigns: %{live_action: :apply}} = socket) do
    if socket.assigns.application && socket.assigns.application.status != :draft do
      {:noreply, push_patch(socket, to: ~p"/tech/application")}
    else
      {:noreply, socket}
    end
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_event("save", %{"application" => params}, socket) do
    customer = socket.assigns.current_customer

    result =
      case socket.assigns.application do
        nil ->
          TechApplication
          |> Ash.Changeset.for_create(:create, normalize_params(params))
          |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
          |> Ash.create(authorize?: false)

        application ->
          application
          |> Ash.Changeset.for_update(:save_draft, normalize_params(params))
          |> Ash.update(authorize?: false)
      end

    case result do
      {:ok, application} ->
        {:noreply,
         socket
         |> assign(application: application, form: to_form(form_params(application, customer), as: :application))
         |> put_flash(:info, "Application draft saved.")}

      {:error, _error} ->
        {:noreply, put_flash(socket, :error, "Could not save application.")}
    end
  end

  def handle_event("submit", _params, socket) do
    case socket.assigns.application do
      nil ->
        {:noreply, put_flash(socket, :error, "Save your application before submitting.")}

      application ->
        case application |> Ash.Changeset.for_update(:submit, %{}) |> Ash.update(authorize?: false) do
          {:ok, submitted} ->
            {:noreply,
             socket
             |> assign(application: submitted)
             |> put_flash(:info, "Application submitted for review.")
             |> push_patch(to: ~p"/tech/application")}

          {:error, _error} ->
            {:noreply, put_flash(socket, :error, "Complete required fields before submitting.")}
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_customer}>
      <main id="tech-application-page" class="mx-auto max-w-3xl px-4 py-8">
        <section :if={@live_action == :show} id="tech-application-status" class="space-y-6">
          <div>
            <p class="text-sm font-semibold uppercase tracking-wide text-primary">Technician application</p>
            <h1 class="text-3xl font-bold">{status_label(@application && @application.status)}</h1>
            <p class="mt-2 text-base-content/70">
              {status_message(@application)}
            </p>
          </div>

          <div :if={@application} class="rounded-lg border border-base-300 bg-base-100 p-5 shadow-sm">
            <dl class="grid gap-4 sm:grid-cols-2">
              <div>
                <dt class="text-xs uppercase text-base-content/60">Preferred name</dt>
                <dd class="font-semibold">{@application.preferred_name}</dd>
              </div>
              <div>
                <dt class="text-xs uppercase text-base-content/60">Home ZIP</dt>
                <dd class="font-semibold">{@application.home_zip}</dd>
              </div>
              <div>
                <dt class="text-xs uppercase text-base-content/60">Experience</dt>
                <dd class="font-semibold">{experience_label(@application.experience_level)}</dd>
              </div>
              <div>
                <dt class="text-xs uppercase text-base-content/60">Decision note</dt>
                <dd class="font-semibold">{@application.decision_note || "No decision note yet"}</dd>
              </div>
            </dl>
          </div>

          <.link :if={!@application or @application.status == :draft} patch={~p"/tech/apply"} class="btn btn-primary">
            Continue application
          </.link>
        </section>

        <section :if={@live_action == :apply} class="space-y-6">
          <div>
            <p class="text-sm font-semibold uppercase tracking-wide text-primary">Apply to become a tech</p>
            <h1 class="text-3xl font-bold">Technician Application</h1>
            <p class="mt-2 text-base-content/70">Save a draft first, then submit it for admin review.</p>
          </div>

          <.form for={@form} id="tech-application-form" phx-submit="save" class="space-y-5">
            <div class="grid gap-4 sm:grid-cols-2">
              <.input field={@form[:preferred_name]} label="Preferred name" />
              <.input field={@form[:phone]} label="Phone" />
              <.input field={@form[:home_zip]} label="Home ZIP" />
              <.input field={@form[:desired_hours_per_week]} type="number" label="Desired hours per week" />
              <.input field={@form[:earliest_start_date]} type="date" label="Earliest start date" />
              <.input field={@form[:emergency_contact_name]} label="Emergency contact name" />
              <.input field={@form[:emergency_contact_phone]} label="Emergency contact phone" />
            </div>

            <div class="grid gap-4 sm:grid-cols-2">
              <.input field={@form[:preferred_zone]} type="select" label="Preferred zone" options={[{"Any", ""}, {"NW", "nw"}, {"NE", "ne"}, {"SW", "sw"}, {"SE", "se"}]} />
              <.input field={@form[:experience_level]} type="select" label="Experience" options={[{"None", "none"}, {"Some", "some"}, {"Professional", "professional"}]} />
            </div>

            <div class="grid gap-3 sm:grid-cols-2">
              <.input field={@form[:availability_weekdays]} type="checkbox" label="Weekdays" />
              <.input field={@form[:availability_weekends]} type="checkbox" label="Weekends" />
              <.input field={@form[:availability_mornings]} type="checkbox" label="Mornings" />
              <.input field={@form[:availability_afternoons]} type="checkbox" label="Afternoons" />
              <.input field={@form[:availability_evenings]} type="checkbox" label="Evenings" />
              <.input field={@form[:has_valid_driver_license]} type="checkbox" label="Valid driver license" />
              <.input field={@form[:has_reliable_transportation]} type="checkbox" label="Reliable transportation" />
              <.input field={@form[:can_lift_supplies]} type="checkbox" label="Can lift and carry supplies" />
            </div>

            <.input field={@form[:why_work_with_us]} type="textarea" label="Why do you want to work with us?" />
            <.input field={@form[:experience_notes]} type="textarea" label="Car wash or detailing experience" />
            <.input field={@form[:schedule_notes]} type="textarea" label="Schedule or transportation notes" />

            <div class="flex flex-wrap gap-3">
              <button id="save-tech-application" type="submit" class="btn btn-primary">Save draft</button>
              <button :if={@application} id="submit-tech-application" type="button" phx-click="submit" class="btn btn-success">
                Submit for review
              </button>
            </div>
          </.form>
        </section>
      </main>
    </Layouts.app>
    """
  end

  defp application_for_customer(customer) do
    TechApplication
    |> Ash.Query.filter(customer_id == ^customer.id)
    |> Ash.read_one!(authorize?: false)
  end

  defp form_params(nil, customer) do
    %{
      "preferred_name" => customer.name,
      "phone" => customer.phone || "",
      "home_zip" => "",
      "preferred_zone" => "",
      "experience_level" => "none"
    }
  end

  defp form_params(application, _customer) do
    application
    |> Map.take(TechApplication.applicant_fields())
    |> Enum.map(fn {key, value} -> {to_string(key), value_to_form(value)} end)
    |> Map.new()
  end

  defp value_to_form(nil), do: ""
  defp value_to_form(value) when is_atom(value), do: to_string(value)
  defp value_to_form(value), do: value

  defp normalize_params(params) do
    params
    |> Map.update("preferred_zone", nil, &blank_to_nil/1)
    |> Map.update("experience_level", "none", &blank_to_nil/1)
    |> atomize_allowed("preferred_zone", [:nw, :ne, :sw, :se])
    |> atomize_allowed("experience_level", [:none, :some, :professional])
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
    |> Map.new(fn {key, value} -> {String.to_existing_atom(key), value} end)
  end

  defp atomize_allowed(params, key, allowed) do
    value = Map.get(params, key)
    atom = Enum.find(allowed, &(to_string(&1) == value))
    Map.put(params, key, atom)
  end

  defp parse_int(params, key) do
    case Integer.parse(to_string(Map.get(params, key, ""))) do
      {int, ""} -> Map.put(params, key, int)
      _ -> Map.put(params, key, nil)
    end
  end

  defp parse_date(params, key) do
    case Date.from_iso8601(to_string(Map.get(params, key, ""))) do
      {:ok, date} -> Map.put(params, key, date)
      {:error, _} -> Map.put(params, key, nil)
    end
  end

  defp parse_bool(params, key), do: Map.put(params, key, Map.get(params, key) in ["true", "on", true])
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp status_label(nil), do: "Start your application"
  defp status_label(:draft), do: "Draft"
  defp status_label(:pending_review), do: "Pending review"
  defp status_label(:reviewed), do: "Reviewed"
  defp status_label(:accepted), do: "Accepted"
  defp status_label(:not_accepted), do: "Not accepted"

  defp status_message(nil), do: "Start an application and save it as a draft."
  defp status_message(%{status: :draft}), do: "Your application is saved but has not been submitted."
  defp status_message(%{status: :pending_review}), do: "Your application is waiting for admin review."
  defp status_message(%{status: :reviewed}), do: "Your application has been reviewed and is waiting for a decision."
  defp status_message(%{status: :accepted}), do: "You have been accepted. Your technician access is active."
  defp status_message(%{status: :not_accepted}), do: "Your application was not accepted at this time."

  defp experience_label(:none), do: "None"
  defp experience_label(:some), do: "Some"
  defp experience_label(:professional), do: "Professional"
  defp experience_label(_), do: "Not provided"
end
```

- [ ] **Step 5: Run applicant LiveView tests**

Run:

```bash
mix format lib/mobile_car_wash_web/live/tech/application_live.ex lib/mobile_car_wash_web/router.ex test/mobile_car_wash_web/live/tech/application_live_test.exs
mix test test/mobile_car_wash_web/live/tech/application_live_test.exs
```

Expected: tests pass.

- [ ] **Step 6: Commit**

Run:

```bash
git add lib/mobile_car_wash_web/live/tech/application_live.ex lib/mobile_car_wash_web/router.ex test/mobile_car_wash_web/live/tech/application_live_test.exs
git commit -m "Add tech application portal"
```

---

### Task 3: Admin Application Queue And Approval

**Files:**
- Create: `lib/mobile_car_wash_web/live/admin/tech_applications_live.ex`
- Modify: `lib/mobile_car_wash_web/router.ex`
- Test: `test/mobile_car_wash_web/live/admin/tech_applications_live_test.exs`

**Interfaces:**
- Consumes: `TechApplication` actions `:mark_reviewed`, `:accept`, and `:not_accept`
- Produces route: `GET /admin/tech-applications`
- Produces route: `GET /admin/tech-applications/:id`

- [ ] **Step 1: Write failing admin tests**

Create `test/mobile_car_wash_web/live/admin/tech_applications_live_test.exs`:

```elixir
defmodule MobileCarWashWeb.Admin.TechApplicationsLiveTest do
  use MobileCarWashWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Operations.{TechApplication, Technician}

  defp user_fixture(role) do
    {:ok, user} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "#{role}-#{System.unique_integer([:positive])}@example.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "#{role} user",
        phone: "+15125550300"
      })
      |> Ash.create()

    user
    |> Ash.Changeset.for_update(:update, %{role: role})
    |> Ash.update!(authorize?: false)
  end

  defp sign_in(conn, user) do
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> post("/auth/customer/password/sign_in", %{
      "customer" => %{
        "email" => to_string(user.email),
        "password" => "Password123!"
      }
    })
    |> recycle()
  end

  defp application_fixture(customer) do
    {:ok, application} =
      TechApplication
      |> Ash.Changeset.for_create(:create, %{
        preferred_name: "Queue Applicant",
        phone: "+15125550301",
        home_zip: "78259",
        preferred_zone: :sw,
        availability_weekdays: true,
        availability_weekends: true,
        availability_mornings: true,
        availability_afternoons: false,
        availability_evenings: false,
        experience_level: :some,
        has_valid_driver_license: true,
        has_reliable_transportation: true,
        can_lift_supplies: true,
        desired_hours_per_week: 25,
        earliest_start_date: Date.utc_today(),
        emergency_contact_name: "Contact",
        emergency_contact_phone: "+15125550302",
        why_work_with_us: "I like detailing.",
        experience_notes: "Some detail work.",
        schedule_notes: "Weekdays."
      })
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create(authorize?: false)

    application
    |> Ash.Changeset.for_update(:submit, %{})
    |> Ash.update!(authorize?: false)
  end

  test "non-admin cannot view application queue", %{conn: conn} do
    user = user_fixture(:customer)
    conn = sign_in(conn, user)

    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/admin/tech-applications")
  end

  test "admin can see pending applications", %{conn: conn} do
    admin = user_fixture(:admin)
    applicant = user_fixture(:customer)
    application_fixture(applicant)
    conn = sign_in(conn, admin)

    {:ok, view, _html} = live(conn, ~p"/admin/tech-applications")
    assert has_element?(view, "#tech-applications")
    assert render(view) =~ "Queue Applicant"
    assert render(view) =~ "Pending review"
  end

  test "admin can accept an application and create technician", %{conn: conn} do
    admin = user_fixture(:admin)
    applicant = user_fixture(:customer)
    application = application_fixture(applicant)
    conn = sign_in(conn, admin)

    {:ok, view, _html} = live(conn, ~p"/admin/tech-applications/#{application.id}")

    view
    |> form("#accept-tech-application-form", %{
      "decision" => %{
        "review_notes" => "Approved.",
        "decision_note" => "Welcome.",
        "accepted_pay_rate_cents" => "3500",
        "accepted_pay_rate_pct" => "",
        "assigned_zone" => "sw",
        "van_id" => "",
        "active" => "true"
      }
    })
    |> render_submit()

    reloaded = Ash.get!(Customer, applicant.id, authorize?: false)
    assert reloaded.role == :technician

    technician =
      Technician
      |> Ash.read!(authorize?: false)
      |> Enum.find(&(&1.user_account_id == applicant.id))

    assert technician.pay_rate_cents == 3500
    assert technician.zone == :sw
  end
end
```

- [ ] **Step 2: Run failing tests**

Run:

```bash
mix test test/mobile_car_wash_web/live/admin/tech_applications_live_test.exs
```

Expected: fail because routes and LiveView are missing.

- [ ] **Step 3: Add admin routes**

In `lib/mobile_car_wash_web/router.ex`, inside the existing `live_session :admin` block, add:

```elixir
live "/tech-applications", TechApplicationsLive, :index
live "/tech-applications/:id", TechApplicationsLive, :show
```

- [ ] **Step 4: Implement admin LiveView**

Create `lib/mobile_car_wash_web/live/admin/tech_applications_live.ex`:

```elixir
defmodule MobileCarWashWeb.Admin.TechApplicationsLive do
  use MobileCarWashWeb, :live_view

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Operations.{TechApplication, Van}

  require Ash.Query

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Tech Applications",
       applications: load_applications(),
       application: nil,
       customer: nil,
       vans: load_vans()
     )}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    application = Ash.get!(TechApplication, id, authorize?: false)
    customer = Ash.get!(Customer, application.customer_id, authorize?: false)

    {:noreply,
     assign(socket,
       page_title: "Review #{application.preferred_name}",
       application: application,
       customer: customer
     )}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, assign(socket, applications: load_applications(), application: nil, customer: nil)}
  end

  @impl true
  def handle_event("mark_reviewed", %{"review" => params}, socket) do
    {:ok, application} =
      socket.assigns.application
      |> Ash.Changeset.for_update(:mark_reviewed, %{
        review_notes: params["review_notes"],
        decision_note: params["decision_note"]
      })
      |> Ash.update(authorize?: false)

    {:noreply, assign(socket, application: application)}
  end

  def handle_event("not_accept", %{"decision" => params}, socket) do
    {:ok, application} =
      socket.assigns.application
      |> Ash.Changeset.for_update(:not_accept, %{
        review_notes: params["review_notes"],
        decision_note: params["decision_note"]
      })
      |> Ash.update(authorize?: false)

    {:noreply, assign(socket, application: application)}
  end

  def handle_event("accept", %{"decision" => params}, socket) do
    attrs = %{
      review_notes: params["review_notes"],
      decision_note: params["decision_note"],
      accepted_pay_rate_cents: parse_int(params["accepted_pay_rate_cents"]) || 2500,
      accepted_pay_rate_pct: parse_pct(params["accepted_pay_rate_pct"]),
      assigned_zone: parse_zone(params["assigned_zone"]),
      van_id: blank_to_nil(params["van_id"]),
      active: params["active"] in ["true", "on", true]
    }

    {:ok, application} =
      socket.assigns.application
      |> Ash.Changeset.for_update(:accept, attrs)
      |> Ash.update(authorize?: false)

    {:noreply,
     socket
     |> assign(application: application)
     |> put_flash(:info, "Applicant accepted and technician account activated.")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_customer}>
      <main class="mx-auto max-w-6xl px-4 py-8">
        <section :if={@live_action == :index} id="tech-applications" class="space-y-5">
          <div>
            <h1 class="text-3xl font-bold">Tech Applications</h1>
            <p class="mt-2 text-base-content/70">Review applicants and promote accepted customers to technicians.</p>
          </div>

          <div class="overflow-x-auto rounded-lg border border-base-300 bg-base-100">
            <table class="table">
              <thead>
                <tr>
                  <th>Applicant</th>
                  <th>Status</th>
                  <th>Zone</th>
                  <th>Experience</th>
                  <th>Submitted</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                <tr :for={application <- @applications}>
                  <td>{application.preferred_name}</td>
                  <td>{status_label(application.status)}</td>
                  <td>{zone_label(application.preferred_zone)}</td>
                  <td>{experience_label(application.experience_level)}</td>
                  <td>{format_date(application.submitted_at)}</td>
                  <td>
                    <.link navigate={~p"/admin/tech-applications/#{application.id}"} class="btn btn-primary btn-sm">
                      Review
                    </.link>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>

        <section :if={@live_action == :show and @application} id="tech-application-review" class="space-y-6">
          <.link navigate={~p"/admin/tech-applications"} class="btn btn-ghost btn-sm">Back</.link>

          <div>
            <h1 class="text-3xl font-bold">{@application.preferred_name}</h1>
            <p class="mt-2 text-base-content/70">{@customer.email} · {status_label(@application.status)}</p>
          </div>

          <div class="grid gap-4 md:grid-cols-2">
            <div class="rounded-lg border border-base-300 bg-base-100 p-5">
              <h2 class="font-semibold">Application</h2>
              <dl class="mt-4 space-y-3 text-sm">
                <div><dt class="text-base-content/60">Phone</dt><dd>{@application.phone || @customer.phone}</dd></div>
                <div><dt class="text-base-content/60">Home ZIP</dt><dd>{@application.home_zip}</dd></div>
                <div><dt class="text-base-content/60">Preferred zone</dt><dd>{zone_label(@application.preferred_zone)}</dd></div>
                <div><dt class="text-base-content/60">Experience</dt><dd>{experience_label(@application.experience_level)}</dd></div>
                <div><dt class="text-base-content/60">Hours/week</dt><dd>{@application.desired_hours_per_week}</dd></div>
                <div><dt class="text-base-content/60">Why</dt><dd>{@application.why_work_with_us}</dd></div>
                <div><dt class="text-base-content/60">Experience notes</dt><dd>{@application.experience_notes}</dd></div>
                <div><dt class="text-base-content/60">Schedule notes</dt><dd>{@application.schedule_notes}</dd></div>
              </dl>
            </div>

            <div class="rounded-lg border border-base-300 bg-base-100 p-5">
              <h2 class="font-semibold">Decision</h2>
              <form id="accept-tech-application-form" phx-submit="accept" class="mt-4 space-y-3">
                <label class="form-control">
                  <span class="label-text">Internal review notes</span>
                  <textarea name="decision[review_notes]" class="textarea textarea-bordered w-full">{@application.review_notes}</textarea>
                </label>
                <label class="form-control">
                  <span class="label-text">Applicant-visible note</span>
                  <textarea name="decision[decision_note]" class="textarea textarea-bordered w-full">{@application.decision_note}</textarea>
                </label>
                <input name="decision[accepted_pay_rate_cents]" type="number" class="input input-bordered w-full" value={@application.accepted_pay_rate_cents || 2500} />
                <label class="form-control">
                  <span class="label-text">Percent pay rate</span>
                  <input name="decision[accepted_pay_rate_pct]" type="number" class="input input-bordered w-full" step="0.5" />
                </label>
                <select name="decision[assigned_zone]" class="select select-bordered w-full">
                  <option value="">Use preferred zone</option>
                  <option value="nw" selected={@application.assigned_zone == :nw}>NW</option>
                  <option value="ne" selected={@application.assigned_zone == :ne}>NE</option>
                  <option value="sw" selected={@application.assigned_zone == :sw}>SW</option>
                  <option value="se" selected={@application.assigned_zone == :se}>SE</option>
                </select>
                <select name="decision[van_id]" class="select select-bordered w-full">
                  <option value="">No van assigned</option>
                  <option :for={van <- @vans} value={van.id}>{van.name}</option>
                </select>
                <input type="hidden" name="decision[active]" value="true" />
                <div class="flex gap-2">
                  <button type="submit" class="btn btn-success">Accept</button>
                </div>
              </form>

              <form id="not-accept-tech-application-form" phx-submit="not_accept" class="mt-3 space-y-3">
                <input type="hidden" name="decision[review_notes]" value={@application.review_notes || ""} />
                <input type="hidden" name="decision[decision_note]" value={@application.decision_note || "Application not accepted at this time."} />
                <button type="submit" class="btn btn-error">Not accept</button>
              </form>

              <form id="review-tech-application-form" phx-submit="mark_reviewed" class="mt-3">
                <input type="hidden" name="review[review_notes]" value={@application.review_notes || ""} />
                <input type="hidden" name="review[decision_note]" value={@application.decision_note || ""} />
                <button type="submit" class="btn btn-ghost btn-sm">Mark reviewed</button>
              </form>
            </div>
          </div>
        </section>
      </main>
    </Layouts.app>
    """
  end

  defp load_applications do
    TechApplication
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.read!(authorize?: false)
  end

  defp load_vans do
    Van |> Ash.Query.sort(name: :asc) |> Ash.read!(authorize?: false)
  end

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil
  defp parse_int(value), do: elem(Integer.parse(value), 0)

  defp parse_pct(nil), do: nil
  defp parse_pct(""), do: nil
  defp parse_pct(value), do: Decimal.div(Decimal.new(value), Decimal.new(100))

  defp parse_zone(value) when value in ["nw", "ne", "sw", "se"], do: String.to_existing_atom(value)
  defp parse_zone(_), do: nil

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp status_label(:draft), do: "Draft"
  defp status_label(:pending_review), do: "Pending review"
  defp status_label(:reviewed), do: "Reviewed"
  defp status_label(:accepted), do: "Accepted"
  defp status_label(:not_accepted), do: "Not accepted"

  defp zone_label(nil), do: "Any"
  defp zone_label(zone), do: zone |> to_string() |> String.upcase()

  defp experience_label(:none), do: "None"
  defp experience_label(:some), do: "Some"
  defp experience_label(:professional), do: "Professional"

  defp format_date(nil), do: "Not submitted"
  defp format_date(%DateTime{} = dt), do: Calendar.strftime(dt, "%b %d, %Y")
end
```

- [ ] **Step 5: Run admin tests**

Run:

```bash
mix format lib/mobile_car_wash_web/live/admin/tech_applications_live.ex lib/mobile_car_wash_web/router.ex test/mobile_car_wash_web/live/admin/tech_applications_live_test.exs
mix test test/mobile_car_wash_web/live/admin/tech_applications_live_test.exs
```

Expected: tests pass.

- [ ] **Step 6: Commit**

Run:

```bash
git add lib/mobile_car_wash_web/live/admin/tech_applications_live.ex lib/mobile_car_wash_web/router.ex test/mobile_car_wash_web/live/admin/tech_applications_live_test.exs
git commit -m "Add admin tech application review"
```

---

### Task 4: Private Tech Profile Page

**Files:**
- Create: `lib/mobile_car_wash_web/live/tech/profile_live.ex`
- Test: `test/mobile_car_wash_web/live/tech/profile_live_test.exs`

**Interfaces:**
- Consumes route from Task 2: `GET /tech/profile`
- Consumes: `TechApplication`, `Technician`, `TechEarnings`
- Produces private applicant/technician profile UI

- [ ] **Step 1: Write failing profile tests**

Create `test/mobile_car_wash_web/live/tech/profile_live_test.exs`:

```elixir
defmodule MobileCarWashWeb.Tech.ProfileLiveTest do
  use MobileCarWashWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Operations.{TechApplication, Technician}

  defp customer_fixture(role \\ :customer) do
    {:ok, user} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "profile-#{System.unique_integer([:positive])}@example.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Profile User",
        phone: "+15125550400"
      })
      |> Ash.create()

    user
    |> Ash.Changeset.for_update(:update, %{role: role})
    |> Ash.update!(authorize?: false)
  end

  defp sign_in(conn, user) do
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> post("/auth/customer/password/sign_in", %{
      "customer" => %{
        "email" => to_string(user.email),
        "password" => "Password123!"
      }
    })
    |> recycle()
  end

  test "applicant profile shows application status", %{conn: conn} do
    user = customer_fixture()

    TechApplication
    |> Ash.Changeset.for_create(:create, %{
      preferred_name: "Profile Applicant",
      home_zip: "78259",
      status: :pending_review
    })
    |> Ash.Changeset.force_change_attribute(:customer_id, user.id)
    |> Ash.create!(authorize?: false)

    {:ok, view, _html} = live(sign_in(conn, user), ~p"/tech/profile")

    assert has_element?(view, "#tech-profile")
    assert render(view) =~ "Pending review"
    assert render(view) =~ "Profile Applicant"
  end

  test "accepted technician profile shows pay and zone", %{conn: conn} do
    user = customer_fixture(:technician)

    Technician
    |> Ash.Changeset.for_create(:create, %{
      name: "Profile Tech",
      phone: "+15125550400",
      zone: :ne,
      pay_rate_cents: 3200,
      active: true
    })
    |> Ash.Changeset.force_change_attribute(:user_account_id, user.id)
    |> Ash.create!(authorize?: false)

    {:ok, view, _html} = live(sign_in(conn, user), ~p"/tech/profile")

    assert render(view) =~ "Profile Tech"
    assert render(view) =~ "$32.00"
    assert render(view) =~ "NE"
  end
end
```

- [ ] **Step 2: Run failing tests**

Run:

```bash
mix test test/mobile_car_wash_web/live/tech/profile_live_test.exs
```

Expected: fail because `MobileCarWashWeb.Tech.ProfileLive` is missing.

- [ ] **Step 3: Implement profile LiveView**

Create `lib/mobile_car_wash_web/live/tech/profile_live.ex`:

```elixir
defmodule MobileCarWashWeb.Tech.ProfileLive do
  use MobileCarWashWeb, :live_view

  alias MobileCarWash.Operations.{TechApplication, TechEarnings, Technician}

  require Ash.Query

  @impl true
  def mount(_params, _session, socket) do
    customer = socket.assigns.current_customer
    application = application_for(customer)
    technician = technician_for(customer)
    earnings = if technician, do: TechEarnings.earnings_for_period(technician, :week), else: nil

    {:ok,
     assign(socket,
       page_title: "Tech Profile",
       application: application,
       technician: technician,
       earnings: earnings
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_customer}>
      <main id="tech-profile" class="mx-auto max-w-4xl px-4 py-8">
        <div class="mb-6">
          <p class="text-sm font-semibold uppercase tracking-wide text-primary">Private profile</p>
          <h1 class="text-3xl font-bold">{profile_name(@technician, @application, @current_customer)}</h1>
          <p class="mt-2 text-base-content/70">{@current_customer.email}</p>
        </div>

        <div class="grid gap-4 md:grid-cols-2">
          <section class="rounded-lg border border-base-300 bg-base-100 p-5 shadow-sm">
            <h2 class="font-semibold">Application</h2>
            <dl class="mt-4 space-y-3 text-sm">
              <div>
                <dt class="text-base-content/60">Status</dt>
                <dd class="font-semibold">{status_label(@application && @application.status)}</dd>
              </div>
              <div :if={@application}>
                <dt class="text-base-content/60">Preferred zone</dt>
                <dd class="font-semibold">{zone_label(@application.preferred_zone)}</dd>
              </div>
              <div :if={@application && @application.decision_note}>
                <dt class="text-base-content/60">Decision note</dt>
                <dd>{@application.decision_note}</dd>
              </div>
            </dl>
            <.link :if={!@application or @application.status == :draft} navigate={~p"/tech/apply"} class="btn btn-primary btn-sm mt-4">
              Continue application
            </.link>
          </section>

          <section class="rounded-lg border border-base-300 bg-base-100 p-5 shadow-sm">
            <h2 class="font-semibold">Technician</h2>
            <div :if={!@technician} class="mt-4 text-sm text-base-content/70">
              Technician access is not active yet.
            </div>
            <dl :if={@technician} class="mt-4 space-y-3 text-sm">
              <div>
                <dt class="text-base-content/60">Pay rate</dt>
                <dd class="font-semibold">{pay_label(@technician)}</dd>
              </div>
              <div>
                <dt class="text-base-content/60">Zone</dt>
                <dd class="font-semibold">{zone_label(@technician.zone)}</dd>
              </div>
              <div>
                <dt class="text-base-content/60">Active</dt>
                <dd class="font-semibold">{if @technician.active, do: "Yes", else: "No"}</dd>
              </div>
              <div>
                <dt class="text-base-content/60">Status</dt>
                <dd class="font-semibold">{duty_label(@technician.status)}</dd>
              </div>
            </dl>
          </section>
        </div>

        <section :if={@earnings} class="mt-6 rounded-lg border border-base-300 bg-base-100 p-5 shadow-sm">
          <h2 class="font-semibold">This Week</h2>
          <div class="mt-4 grid gap-4 sm:grid-cols-3">
            <div>
              <p class="text-sm text-base-content/60">Washes</p>
              <p class="text-2xl font-bold">{@earnings.washes_count}</p>
            </div>
            <div>
              <p class="text-sm text-base-content/60">Earned</p>
              <p class="text-2xl font-bold text-success">${format_dollars(@earnings.total_cents)}</p>
            </div>
            <div>
              <p class="text-sm text-base-content/60">Period</p>
              <p class="font-semibold">{Calendar.strftime(@earnings.period_start, "%b %d")} - {Calendar.strftime(@earnings.period_end, "%b %d")}</p>
            </div>
          </div>
        </section>
      </main>
    </Layouts.app>
    """
  end

  defp application_for(customer) do
    TechApplication
    |> Ash.Query.filter(customer_id == ^customer.id)
    |> Ash.read_one!(authorize?: false)
  end

  defp technician_for(customer) do
    Technician
    |> Ash.Query.filter(user_account_id == ^customer.id)
    |> Ash.read_one!(authorize?: false)
  end

  defp profile_name(technician, _application, _customer) when not is_nil(technician), do: technician.name
  defp profile_name(_technician, application, _customer) when not is_nil(application), do: application.preferred_name
  defp profile_name(_technician, _application, customer), do: customer.name

  defp status_label(nil), do: "No application"
  defp status_label(:draft), do: "Draft"
  defp status_label(:pending_review), do: "Pending review"
  defp status_label(:reviewed), do: "Reviewed"
  defp status_label(:accepted), do: "Accepted"
  defp status_label(:not_accepted), do: "Not accepted"

  defp zone_label(nil), do: "Any"
  defp zone_label(zone), do: zone |> to_string() |> String.upcase()

  defp duty_label(:off_duty), do: "Off duty"
  defp duty_label(:available), do: "Available"
  defp duty_label(:on_break), do: "On break"
  defp duty_label(_), do: "Unknown"

  defp pay_label(%{pay_rate_pct: %Decimal{} = pct}) do
    "#{Decimal.mult(pct, Decimal.new(100))}% of wash price"
  end

  defp pay_label(%{pay_rate_cents: cents}), do: "$#{format_dollars(cents || 2500)} flat / wash"

  defp format_dollars(cents) when is_integer(cents) do
    "#{div(cents, 100)}.#{String.pad_leading(to_string(rem(cents, 100)), 2, "0")}"
  end
end
```

- [ ] **Step 4: Run profile tests**

Run:

```bash
mix format lib/mobile_car_wash_web/live/tech/profile_live.ex test/mobile_car_wash_web/live/tech/profile_live_test.exs
mix test test/mobile_car_wash_web/live/tech/profile_live_test.exs
```

Expected: tests pass.

- [ ] **Step 5: Commit**

Run:

```bash
git add lib/mobile_car_wash_web/live/tech/profile_live.ex test/mobile_car_wash_web/live/tech/profile_live_test.exs
git commit -m "Add private tech profile"
```

---

### Task 5: Technician Job Brief Page

**Files:**
- Create: `lib/mobile_car_wash_web/live/tech/job_live.ex`
- Modify: `lib/mobile_car_wash_web/router.ex`
- Modify: `lib/mobile_car_wash_web/live/tech/tech_dashboard_live.ex`
- Test: `test/mobile_car_wash_web/live/tech/job_live_test.exs`

**Interfaces:**
- Produces route: `GET /tech/appointments/:id`
- Consumes appointment actions: `:depart`, `:arrive`, and `WashOrchestrator.start_wash/1`

- [ ] **Step 1: Write failing job brief tests**

Create `test/mobile_car_wash_web/live/tech/job_live_test.exs`:

```elixir
defmodule MobileCarWashWeb.Tech.JobLiveTest do
  use MobileCarWashWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Operations.Technician
  alias MobileCarWash.Scheduling.{Appointment, ServiceType}

  defp tech_user do
    {:ok, customer} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "job-tech-#{System.unique_integer([:positive])}@example.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Job Tech",
        phone: "+15125550500"
      })
      |> Ash.create()

    customer
    |> Ash.Changeset.for_update(:update, %{role: :technician})
    |> Ash.update!(authorize?: false)
  end

  defp sign_in(conn, customer) do
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> post("/auth/customer/password/sign_in", %{
      "customer" => %{
        "email" => to_string(customer.email),
        "password" => "Password123!"
      }
    })
    |> recycle()
  end

  defp appointment_fixture(tech, status) do
    {:ok, customer} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "job-customer-#{System.unique_integer([:positive])}@example.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Job Customer",
        phone: "+15125550501"
      })
      |> Ash.create()

    {:ok, service} =
      ServiceType
      |> Ash.Changeset.for_create(:create, %{
        name: "Job Wash",
        slug: "job-wash-#{System.unique_integer([:positive])}",
        base_price_cents: 5000,
        duration_minutes: 45
      })
      |> Ash.create()

    {:ok, vehicle} =
      MobileCarWash.Fleet.Vehicle
      |> Ash.Changeset.for_create(:create, %{make: "Toyota", model: "Camry"})
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create()

    {:ok, address} =
      MobileCarWash.Fleet.Address
      |> Ash.Changeset.for_create(:create, %{
        street: "100 Job Ave",
        city: "San Antonio",
        state: "TX",
        zip: "78259"
      })
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create()

    Appointment
    |> Ash.Changeset.for_create(:book, %{
      customer_id: customer.id,
      vehicle_id: vehicle.id,
      address_id: address.id,
      service_type_id: service.id,
      scheduled_at: DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second),
      price_cents: 5000,
      duration_minutes: 45
    })
    |> Ash.create!()
    |> Ash.Changeset.for_update(:update, %{})
    |> Ash.Changeset.force_change_attribute(:technician_id, tech.id)
    |> Ash.Changeset.force_change_attribute(:status, status)
    |> Ash.update!(authorize?: false)
  end

  test "job brief shows the next action for a confirmed job", %{conn: conn} do
    user = tech_user()

    tech =
      Technician
      |> Ash.Changeset.for_create(:create, %{name: user.name, phone: user.phone, active: true})
      |> Ash.Changeset.force_change_attribute(:user_account_id, user.id)
      |> Ash.create!(authorize?: false)

    appointment = appointment_fixture(tech, :confirmed)

    {:ok, view, _html} = live(sign_in(conn, user), ~p"/tech/appointments/#{appointment.id}")

    assert has_element?(view, "#tech-job-brief")
    assert render(view) =~ "Job Customer"
    assert render(view) =~ "Head out"
  end
end
```

- [ ] **Step 2: Run failing tests**

Run:

```bash
mix test test/mobile_car_wash_web/live/tech/job_live_test.exs
```

Expected: fail because job brief route and LiveView are missing.

- [ ] **Step 3: Add technician route**

In `lib/mobile_car_wash_web/router.ex`, inside the `live_session :technician` block, add:

```elixir
live "/appointments/:id", Tech.JobLive
```

- [ ] **Step 4: Implement JobLive**

Create `lib/mobile_car_wash_web/live/tech/job_live.ex` with ownership checks, appointment data loading, and CTA handlers mirroring `TechDashboardLive.transition_appointment/3` and `start_wash`.

Use these public elements in render for tests and future interaction:

```elixir
<Layouts.app flash={@flash} current_scope={@current_customer}>
  <main id="tech-job-brief" class="mx-auto max-w-3xl px-4 py-8">
    <.link navigate={~p"/tech"} class="btn btn-ghost btn-sm">Back to today</.link>
    <h1 class="mt-4 text-3xl font-bold">{@customer.name}</h1>
    <p class="text-base-content/70">{@service.name} · {Calendar.strftime(@appointment.scheduled_at, "%b %d · %I:%M %p")}</p>
    <section class="mt-6 rounded-lg border border-base-300 bg-base-100 p-5 shadow-sm">
      <h2 class="font-semibold">Vehicle and address</h2>
      <p class="mt-2">{@vehicle.make} {@vehicle.model}</p>
      <a href={maps_url(@address)} target="_blank" rel="noopener" class="link link-primary">
        {@address.street}, {@address.city}, {@address.state} {@address.zip}
      </a>
    </section>
    <section class="mt-6 flex gap-3">
      <button :if={@appointment.status == :confirmed} id="job-head-out" phx-click="depart" class="btn btn-primary">Head out</button>
      <button :if={@appointment.status == :en_route} id="job-arrived" phx-click="arrive" class="btn btn-info">Arrived</button>
      <button :if={@appointment.status == :on_site} id="job-start-wash" phx-click="start_wash" class="btn btn-warning">Start wash</button>
      <.link :if={@checklist_id} navigate={~p"/tech/checklist/#{@checklist_id}"} class="btn btn-primary">Open checklist</.link>
    </section>
  </main>
</Layouts.app>
```

- [ ] **Step 5: Link dashboard rows to job brief**

In `lib/mobile_car_wash_web/live/tech/tech_dashboard_live.ex`, change the primary appointment row CTA so non-active appointments route to `~p"/tech/appointments/#{@appointment.id}"` with label `View job`. Keep direct checklist links for active in-progress appointments with a checklist.

- [ ] **Step 6: Run job brief tests**

Run:

```bash
mix format lib/mobile_car_wash_web/live/tech/job_live.ex lib/mobile_car_wash_web/live/tech/tech_dashboard_live.ex lib/mobile_car_wash_web/router.ex test/mobile_car_wash_web/live/tech/job_live_test.exs
mix test test/mobile_car_wash_web/live/tech/job_live_test.exs test/mobile_car_wash_web/live/tech/tech_dashboard_live_test.exs
```

Expected: tests pass.

- [ ] **Step 7: Commit**

Run:

```bash
git add lib/mobile_car_wash_web/live/tech/job_live.ex lib/mobile_car_wash_web/live/tech/tech_dashboard_live.ex lib/mobile_car_wash_web/router.ex test/mobile_car_wash_web/live/tech/job_live_test.exs
git commit -m "Add technician job brief"
```

---

### Task 6: Focus Active Wash UX

**Files:**
- Modify: `lib/mobile_car_wash_web/live/checklist_live.ex`
- Test: `test/mobile_car_wash_web/live/checklist_live_test.exs`

**Interfaces:**
- Consumes existing checklist assigns and handlers.
- Produces stable DOM IDs: `#active-wash`, `#before-photo-progress`, `#active-step-card`, `#after-photo-progress`, `#wrap-up-panel`

- [ ] **Step 1: Add LiveView tests for stable active-wash regions**

Replace `test/mobile_car_wash_web/live/checklist_live_test.exs` with:

```elixir
defmodule MobileCarWashWeb.ChecklistLiveTest do
  use MobileCarWashWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Operations.{AppointmentChecklist, ChecklistItem, Procedure, ProcedureStep, Technician}
  alias MobileCarWash.Scheduling.{Appointment, ServiceType}

  defp tech_user do
    {:ok, user} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "checklist-live-#{System.unique_integer([:positive])}@example.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Checklist Tech",
        phone: "+15125550600"
      })
      |> Ash.create()

    user
    |> Ash.Changeset.for_update(:update, %{role: :technician})
    |> Ash.update!(authorize?: false)
  end

  defp sign_in(conn, user) do
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> post("/auth/customer/password/sign_in", %{
      "customer" => %{
        "email" => to_string(user.email),
        "password" => "Password123!"
      }
    })
    |> recycle()
  end

  defp checklist_fixture(user) do
    tech =
      Technician
      |> Ash.Changeset.for_create(:create, %{name: user.name, phone: user.phone, active: true})
      |> Ash.Changeset.force_change_attribute(:user_account_id, user.id)
      |> Ash.create!(authorize?: false)

    {:ok, customer} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "checklist-customer-#{System.unique_integer([:positive])}@example.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Checklist Customer",
        phone: "+15125550601"
      })
      |> Ash.create()

    service =
      ServiceType
      |> Ash.Changeset.for_create(:create, %{
        name: "Checklist Wash",
        slug: "checklist-live-#{System.unique_integer([:positive])}",
        base_price_cents: 5000,
        duration_minutes: 45
      })
      |> Ash.create!()

    vehicle =
      MobileCarWash.Fleet.Vehicle
      |> Ash.Changeset.for_create(:create, %{make: "Toyota", model: "Camry"})
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create!()

    address =
      MobileCarWash.Fleet.Address
      |> Ash.Changeset.for_create(:create, %{street: "100 Step Ave", city: "San Antonio", state: "TX", zip: "78259"})
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create!()

    appointment =
      Appointment
      |> Ash.Changeset.for_create(:book, %{
        customer_id: customer.id,
        vehicle_id: vehicle.id,
        address_id: address.id,
        service_type_id: service.id,
        scheduled_at: DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second),
        price_cents: 5000,
        duration_minutes: 45
      })
      |> Ash.create!()
      |> Ash.Changeset.for_update(:update, %{})
      |> Ash.Changeset.force_change_attribute(:technician_id, tech.id)
      |> Ash.Changeset.force_change_attribute(:status, :in_progress)
      |> Ash.update!(authorize?: false)

    procedure =
      Procedure
      |> Ash.Changeset.for_create(:create, %{name: "Checklist SOP", slug: "checklist-sop-#{System.unique_integer([:positive])}"})
      |> Ash.Changeset.force_change_attribute(:service_type_id, service.id)
      |> Ash.create!()

    step =
      ProcedureStep
      |> Ash.Changeset.for_create(:create, %{step_number: 1, title: "Rinse", estimated_minutes: 5})
      |> Ash.Changeset.force_change_attribute(:procedure_id, procedure.id)
      |> Ash.create!()

    checklist =
      AppointmentChecklist
      |> Ash.Changeset.for_create(:create, %{status: :in_progress})
      |> Ash.Changeset.force_change_attribute(:appointment_id, appointment.id)
      |> Ash.Changeset.force_change_attribute(:procedure_id, procedure.id)
      |> Ash.create!()

    ChecklistItem
    |> Ash.Changeset.for_create(:create, %{step_number: 1, title: "Rinse", estimated_minutes: 5, required: true})
    |> Ash.Changeset.force_change_attribute(:checklist_id, checklist.id)
    |> Ash.Changeset.force_change_attribute(:procedure_step_id, step.id)
    |> Ash.create!()

    checklist
  end

  test "renders active-wash regions", %{conn: conn} do
    user = tech_user()
    checklist = checklist_fixture(user)

    {:ok, view, _html} = live(sign_in(conn, user), ~p"/tech/checklist/#{checklist.id}")

    assert has_element?(view, "#active-wash")
    assert has_element?(view, "#before-photo-progress")
    assert has_element?(view, "#active-step-card")
    assert has_element?(view, "#all-steps-list")
    assert has_element?(view, "#after-photo-progress")
  end
end
```

- [ ] **Step 2: Run focused checklist tests**

Run:

```bash
mix test test/mobile_car_wash_web/live/checklist_live_test.exs
```

Expected: fail until the stable regions are added.

- [ ] **Step 3: Refactor checklist render into clear regions**

In `lib/mobile_car_wash_web/live/checklist_live.ex`, keep handlers unchanged and reorganize render around these sections:

```elixir
<div id="active-wash" class="mx-auto max-w-lg px-4 py-4">
  <section id="wash-progress-header" class="mb-5">
    <h1 class="text-xl font-bold">Wash Checklist</h1>
    <progress class="progress progress-primary w-full" value={@pct} max="100"></progress>
  </section>

  <section id="before-photo-progress" class="mb-6">
    <h2 class="font-bold">Before Photos</h2>
  </section>

  <section id="active-step-card" class="mb-6 rounded-lg border border-base-300 bg-base-100 p-4 shadow-sm">
    <h2 class="font-bold">{active_step_title(@items)}</h2>
  </section>

  <section id="all-steps-list" class="space-y-2">
  </section>

  <section id="after-photo-progress" class="mt-6">
    <h2 class="font-bold">After Photos</h2>
  </section>

  <section :if={@checklist.status == :completed} id="wrap-up-panel" class="mt-6 rounded-lg border border-success/30 bg-success/10 p-4">
    <h2 class="text-xl font-bold text-success">Checklist Complete</h2>
  </section>
</div>
```

Move the existing before-photo grid into `#before-photo-progress`, the existing item list into `#all-steps-list`, the existing after-photo grid into `#after-photo-progress`, and the existing complete banner into `#wrap-up-panel`.

- [ ] **Step 4: Add helper for active step title**

In `ChecklistLive`, add:

```elixir
defp active_step_title(items) do
  case current_progress_item(items) do
    nil -> "No active step"
    item -> item.title
  end
end
```

- [ ] **Step 5: Run checklist tests**

Run:

```bash
mix format lib/mobile_car_wash_web/live/checklist_live.ex test/mobile_car_wash_web/live/checklist_live_test.exs
mix test test/mobile_car_wash_web/live/checklist_live_test.exs
```

Expected: tests pass.

- [ ] **Step 6: Commit**

Run:

```bash
git add lib/mobile_car_wash_web/live/checklist_live.ex test/mobile_car_wash_web/live/checklist_live_test.exs
git commit -m "Focus technician checklist flow"
```

---

### Task 7: Final Verification

**Files:**
- No new files.

**Interfaces:**
- Verifies all tasks together.

- [ ] **Step 1: Run focused tech and admin test set**

Run:

```bash
mix test \
  test/mobile_car_wash/operations/tech_application_test.exs \
  test/mobile_car_wash_web/live/tech/application_live_test.exs \
  test/mobile_car_wash_web/live/admin/tech_applications_live_test.exs \
  test/mobile_car_wash_web/live/tech/profile_live_test.exs \
  test/mobile_car_wash_web/live/tech/job_live_test.exs \
  test/mobile_car_wash_web/live/tech/tech_dashboard_live_test.exs \
  test/mobile_car_wash_web/live/checklist_live_test.exs
```

Expected: all listed tests pass.

- [ ] **Step 2: Run project precommit**

Run:

```bash
mix precommit
```

Expected: compile, dependency check, format, and test suite pass.

- [ ] **Step 3: Inspect worktree**

Run:

```bash
git status --short
```

Expected: only intentional files from the final task are modified or the worktree is clean after commits.

- [ ] **Step 4: Commit final fixes if precommit changed formatting**

If `mix format` changed files during `mix precommit`, run:

```bash
git add lib test priv/repo/migrations
git commit -m "Polish tech applicant flow"
```

Expected: commit succeeds or there are no formatting changes to commit.
