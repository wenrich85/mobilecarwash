# Admin Tech Invite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let admins create technician login accounts from `/admin/technicians`, email or copy a setup link, keep invited techs inactive until they accept, and let the same account see applicant/status/profile pages.

**Architecture:** Keep applicant/self-serve applications and admin-created techs in the same `TechApplication`/`Customer`/`Technician` model. Add a `TechInvite` resource plus an orchestration module that creates the customer, accepted admin-sourced application, inactive technician record, and pending token in one transaction-like flow. Public setup lives at `/tech/invite/:token`; logged-in status/profile remains on existing `/tech/application` and `/tech/profile`.

**Tech Stack:** Phoenix LiveView, Ash 3.23, AshPostgres 2.8, AshAuthentication password strategy, Swoosh, Oban, ExUnit/LiveViewTest.

## Global Constraints

- Admin approval is required before a technician gets technician tools.
- Invited technicians stay inactive until the invite is accepted and a password is set.
- Status vocabulary stays `draft | pending_review | reviewed | accepted | not_accepted`.
- Applicant/profile pages are authenticated only.
- Admin-created technicians use the same account model as applicants, not a parallel login system.
- `demographics` means data about the technician: contact details, availability, experience, requirements, emergency contact, notes, zone, and pay.
- No public technician directory in this slice.
- No temporary passwords.
- Existing customer email collisions are rejected in this slice.

---

## File Structure

- Modify `lib/mobile_car_wash/accounts/customer.ex`: add an admin-only customer creation action without a password and an invite password setup action.
- Modify `lib/mobile_car_wash/operations/tech_application.ex`: add `source` and an admin invite create action that stores accepted profile data without running the self-serve review transition.
- Create `lib/mobile_car_wash/operations/tech_invite.ex`: Ash resource for invite token hash/status/expiration timestamps.
- Create `lib/mobile_car_wash/operations/tech_invites.ex`: orchestration API for create/resend/accept/lookup.
- Modify `lib/mobile_car_wash/operations/operations.ex`: register `TechInvite`.
- Modify `lib/mobile_car_wash/notifications/email.ex`: add the setup email template.
- Create `lib/mobile_car_wash/notifications/tech_invite_email_worker.ex`: Oban worker that sends the invite email.
- Modify `lib/mobile_car_wash_web/router.ex`: add public `/tech/invite/:token`.
- Create `lib/mobile_car_wash_web/live/tech/invite_live.ex`: password setup LiveView.
- Modify `lib/mobile_car_wash_web/live/admin/technicians_live.ex`: replace the old inline technician add form with account invite UX and invite status rows.
- Modify `lib/mobile_car_wash_web/live/tech/profile_live.ex`: show application `source` as applicant/admin invite.
- Create migrations:
  - `priv/repo/migrations/*_add_source_to_tech_applications.exs`
  - `priv/repo/migrations/*_create_tech_invites.exs`
- Add tests:
  - `test/mobile_car_wash/operations/tech_invites_test.exs`
  - `test/mobile_car_wash/notifications/tech_invite_email_worker_test.exs`
  - `test/mobile_car_wash_web/live/admin/technicians_live_test.exs`
  - `test/mobile_car_wash_web/live/tech/invite_live_test.exs`

---

### Task 1: Invite Data Model And Account Actions

**Files:**
- Modify: `lib/mobile_car_wash/accounts/customer.ex`
- Modify: `lib/mobile_car_wash/operations/tech_application.ex`
- Create: `lib/mobile_car_wash/operations/tech_invite.ex`
- Modify: `lib/mobile_car_wash/operations/operations.ex`
- Create: `priv/repo/migrations/*_add_source_to_tech_applications.exs`
- Create: `priv/repo/migrations/*_create_tech_invites.exs`
- Test: `test/mobile_car_wash/operations/tech_invites_test.exs`

**Interfaces:**
- Produces: `MobileCarWash.Operations.TechInvite` with statuses `:pending | :accepted | :revoked | :expired`.
- Produces: `Customer` create action `:create_technician_invitee`.
- Produces: `Customer` update action `:set_invite_password`.
- Produces: `TechApplication` create action `:create_admin_invite`.

- [ ] **Step 1: Write failing model/orchestration-shape tests**

```elixir
defmodule MobileCarWash.Operations.TechInvitesTest do
  use MobileCarWash.DataCase, async: true

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Operations.{TechApplication, TechInvite, Technician}

  describe "admin invite data model" do
    test "admin-created application records source and starts accepted" do
      {:ok, customer} =
        Customer
        |> Ash.Changeset.for_create(:create_technician_invitee, %{
          email: "invite-model-#{System.unique_integer([:positive])}@example.com",
          name: "Invite Model",
          phone: "+15125551000"
        })
        |> Ash.create(authorize?: false)

      {:ok, application} =
        TechApplication
        |> Ash.Changeset.for_create(:create_admin_invite, %{
          preferred_name: "Invite Model",
          phone: "+15125551000",
          home_zip: "78259",
          preferred_zone: :nw,
          desired_hours_per_week: 25,
          has_valid_driver_license: true,
          has_reliable_transportation: true,
          can_lift_supplies: true,
          accepted_pay_rate_cents: 3000,
          assigned_zone: :nw
        })
        |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
        |> Ash.create(authorize?: false)

      assert application.source == :admin_invite
      assert application.status == :accepted
      assert application.decided_at
    end

    test "tech invite stores only a token hash and links account plus technician" do
      customer = create_invitee_customer!()
      technician = create_inactive_technician!(customer)

      {:ok, invite} =
        TechInvite
        |> Ash.Changeset.for_create(:create, %{
          token_hash: :crypto.hash(:sha256, "raw-token") |> Base.encode16(case: :lower),
          expires_at: DateTime.add(DateTime.utc_now(), 7, :day)
        })
        |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
        |> Ash.Changeset.force_change_attribute(:technician_id, technician.id)
        |> Ash.create(authorize?: false)

      assert invite.status == :pending
      assert invite.customer_id == customer.id
      assert invite.technician_id == technician.id
      refute Map.has_key?(Map.from_struct(invite), :token)
    end
  end

  defp create_invitee_customer! do
    Customer
    |> Ash.Changeset.for_create(:create_technician_invitee, %{
      email: "invitee-#{System.unique_integer([:positive])}@example.com",
      name: "Invitee",
      phone: "+15125551001"
    })
    |> Ash.create!(authorize?: false)
  end

  defp create_inactive_technician!(customer) do
    Technician
    |> Ash.Changeset.for_create(:create, %{
      name: customer.name,
      phone: customer.phone,
      active: false,
      pay_rate_cents: 3000,
      zone: :nw
    })
    |> Ash.Changeset.force_change_attribute(:user_account_id, customer.id)
    |> Ash.create!(authorize?: false)
  end
end
```

- [ ] **Step 2: Run test to verify RED**

Run: `mix test test/mobile_car_wash/operations/tech_invites_test.exs`

Expected: FAIL because `:create_technician_invitee`, `:create_admin_invite`, and `TechInvite` do not exist.

- [ ] **Step 3: Add schema/resource code**

Implement:
- `Customer` action `:create_technician_invitee` accepting `:email, :name, :phone`, setting `role: :technician`, no password.
- `Customer` update `:set_invite_password` with password validation matching current create validation and bcrypt-backed hashing via AshAuthentication password utilities or `Bcrypt.hash_pwd_salt/1`.
- `TechApplication.source` atom with `[:applicant, :admin_invite]`, default `:applicant`.
- `TechApplication.create :create_admin_invite` accepting applicant fields plus accepted pay/zone/active fields, setting `status: :accepted`, `source: :admin_invite`, `decided_at: DateTime.utc_now()`.
- `TechInvite` resource with token hash and statuses.

- [ ] **Step 4: Add migrations**

Create migrations equivalent to:

```elixir
alter table(:tech_applications) do
  add :source, :text, null: false, default: "applicant"
end

create index(:tech_applications, [:source])

create table(:tech_invites, primary_key: false) do
  add :id, :uuid, primary_key: true
  add :customer_id, references(:customers, type: :uuid, on_delete: :delete_all), null: false
  add :technician_id, references(:technicians, type: :uuid, on_delete: :delete_all), null: false
  add :token_hash, :text, null: false
  add :status, :text, null: false, default: "pending"
  add :expires_at, :utc_datetime_usec, null: false
  add :accepted_at, :utc_datetime_usec
  add :revoked_at, :utc_datetime_usec
  timestamps(type: :utc_datetime_usec)
end

create unique_index(:tech_invites, [:token_hash])
create index(:tech_invites, [:customer_id])
create index(:tech_invites, [:technician_id])
create index(:tech_invites, [:status])
```

- [ ] **Step 5: Run migrations and test GREEN**

Run: `mix ecto.migrate`

Run: `mix test test/mobile_car_wash/operations/tech_invites_test.exs`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/mobile_car_wash/accounts/customer.ex lib/mobile_car_wash/operations/tech_application.ex lib/mobile_car_wash/operations/tech_invite.ex lib/mobile_car_wash/operations/operations.ex priv/repo/migrations test/mobile_car_wash/operations/tech_invites_test.exs
git commit -m "Add tech invite data model"
```

---

### Task 2: Invite Orchestration And Email Worker

**Files:**
- Create: `lib/mobile_car_wash/operations/tech_invites.ex`
- Modify: `lib/mobile_car_wash/notifications/email.ex`
- Create: `lib/mobile_car_wash/notifications/tech_invite_email_worker.ex`
- Test: `test/mobile_car_wash/operations/tech_invites_test.exs`
- Test: `test/mobile_car_wash/notifications/tech_invite_email_worker_test.exs`

**Interfaces:**
- Produces: `TechInvites.create_admin_invite(attrs, opts \\ []) :: {:ok, %{customer: Customer.t(), technician: Technician.t(), application: TechApplication.t(), invite: TechInvite.t(), raw_token: String.t(), invite_url: String.t()}} | {:error, term()}`
- Produces: `TechInvites.accept_invite(token, password, password_confirmation) :: {:ok, %{customer: Customer.t(), technician: Technician.t(), invite: TechInvite.t()}} | {:error, atom() | term()}`
- Produces: `TechInvites.invite_url(token) :: String.t()`

- [ ] **Step 1: Add failing orchestration tests**

Append tests that assert:
- `create_admin_invite/2` rejects an email already present in `customers`.
- `create_admin_invite/2` creates a technician customer with nil `hashed_password`, an accepted admin-sourced application, an inactive technician, and a pending invite.
- `accept_invite/3` sets `hashed_password`, marks invite accepted, activates technician, and allows sign-in with `:sign_in_with_password`.
- expired/reused tokens fail.

- [ ] **Step 2: Run tests RED**

Run: `mix test test/mobile_car_wash/operations/tech_invites_test.exs`

Expected: FAIL because `TechInvites` does not exist.

- [ ] **Step 3: Implement orchestration**

Use `Ecto.Multi` through `MobileCarWash.Repo.transaction/1` for all database writes. Generate raw tokens with `:crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)` and store only `:crypto.hash(:sha256, raw_token) |> Base.encode16(case: :lower)`.

- [ ] **Step 4: Add failing email worker test**

Write a worker test using `Oban.Testing.perform_job/2` and `Swoosh.TestAssertions.assert_email_sent/1` to verify the email contains `/tech/invite/`.

- [ ] **Step 5: Implement email template and worker**

Add `Email.tech_invite(customer, invite_url, expires_at)` and `TechInviteEmailWorker.perform/1` that loads the invite/customer and delivers the setup email when pending.

- [ ] **Step 6: Run GREEN**

Run:
- `mix test test/mobile_car_wash/operations/tech_invites_test.exs`
- `mix test test/mobile_car_wash/notifications/tech_invite_email_worker_test.exs`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/mobile_car_wash/operations/tech_invites.ex lib/mobile_car_wash/notifications/email.ex lib/mobile_car_wash/notifications/tech_invite_email_worker.ex test/mobile_car_wash/operations/tech_invites_test.exs test/mobile_car_wash/notifications/tech_invite_email_worker_test.exs
git commit -m "Add admin tech invite orchestration"
```

---

### Task 3: Public Invite Acceptance Screen

**Files:**
- Modify: `lib/mobile_car_wash_web/router.ex`
- Create: `lib/mobile_car_wash_web/live/tech/invite_live.ex`
- Test: `test/mobile_car_wash_web/live/tech/invite_live_test.exs`

**Interfaces:**
- Consumes: `TechInvites.accept_invite/3`
- Produces: public route `GET /tech/invite/:token`

- [ ] **Step 1: Write failing LiveView tests**

Test:
- valid pending token renders a password setup form.
- mismatched/weak password keeps the form and shows an error.
- valid password redirects to `/sign-in` with success.
- expired or accepted token renders an invalid/expired state.

- [ ] **Step 2: Run tests RED**

Run: `mix test test/mobile_car_wash_web/live/tech/invite_live_test.exs`

Expected: FAIL because route/LiveView are missing.

- [ ] **Step 3: Implement LiveView**

Add public live route inside the public live session:

```elixir
live "/tech/invite/:token", Tech.InviteLive
```

Render a direct password setup form with fields `password` and `password_confirmation`, calling `TechInvites.accept_invite/3` on submit.

- [ ] **Step 4: Run tests GREEN**

Run: `mix test test/mobile_car_wash_web/live/tech/invite_live_test.exs`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/mobile_car_wash_web/router.ex lib/mobile_car_wash_web/live/tech/invite_live.ex test/mobile_car_wash_web/live/tech/invite_live_test.exs
git commit -m "Add technician invite setup page"
```

---

### Task 4: Admin Technician Invite UX

**Files:**
- Modify: `lib/mobile_car_wash_web/live/admin/technicians_live.ex`
- Test: `test/mobile_car_wash_web/live/admin/technicians_live_test.exs`

**Interfaces:**
- Consumes: `TechInvites.create_admin_invite/2`
- Consumes: `TechInvites.invite_url/1`

- [ ] **Step 1: Write failing admin LiveView tests**

Test:
- admin can create an invite with email, profile demographics, zone, and pay rate.
- duplicate email shows an error and does not create records.
- created invite row shows `Pending invite`, inactive technician state, and setup link text.

- [ ] **Step 2: Run tests RED**

Run: `mix test test/mobile_car_wash_web/live/admin/technicians_live_test.exs`

Expected: FAIL because the current form creates an active technician without an account.

- [ ] **Step 3: Replace old add form with invite form**

The form should collect:
- email, name/preferred name, phone, home ZIP
- preferred/assigned zone
- flat pay rate cents and optional percent
- weekday/weekend and time availability booleans
- license/transportation/lifting flags
- desired hours, emergency contact, notes

On submit, call `TechInvites.create_admin_invite/2`, reload technicians/invites, and show a copyable setup URL in the success flash or row.

- [ ] **Step 4: Run tests GREEN**

Run: `mix test test/mobile_car_wash_web/live/admin/technicians_live_test.exs`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/mobile_car_wash_web/live/admin/technicians_live.ex test/mobile_car_wash_web/live/admin/technicians_live_test.exs
git commit -m "Add admin technician invite form"
```

---

### Task 5: Profile Status Polish And Scheduling Guard

**Files:**
- Modify: `lib/mobile_car_wash_web/live/tech/profile_live.ex`
- Modify only if needed: active technician query call sites found by `rg "active_technicians|filter\\(active == true" lib`
- Test: `test/mobile_car_wash_web/live/tech/profile_live_test.exs`

**Interfaces:**
- Consumes: `TechApplication.source`
- Confirms inactive invited techs do not appear in assignable active tech rosters.

- [ ] **Step 1: Write failing profile test**

Add a test that an accepted admin invite displays pathway `Admin invite`, accepted status, pay rate, assigned zone, and `Active No` before acceptance.

- [ ] **Step 2: Run test RED**

Run: `mix test test/mobile_car_wash_web/live/tech/profile_live_test.exs`

Expected: FAIL because source-specific pathway copy is not implemented.

- [ ] **Step 3: Implement profile copy**

Change `pathway_label/2` to return `"Admin invite"` when `application.source == :admin_invite`, otherwise preserve `"Applicant"` and `"Accepted technician"`.

- [ ] **Step 4: Verify active roster guards**

Run: `rg -n "filter\\(active == true|active_technicians|technicians do" lib/mobile_car_wash lib/mobile_car_wash_web`

If any assignment or block-generation roster includes inactive technicians, add focused tests and filter by `active == true`.

- [ ] **Step 5: Run tests GREEN**

Run:
- `mix test test/mobile_car_wash_web/live/tech/profile_live_test.exs`
- `mix test test/mobile_car_wash_web/live/admin/dispatch_live_tech_strip_test.exs test/mobile_car_wash_web/live/admin/blocks_live_calendar_test.exs`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/mobile_car_wash_web/live/tech/profile_live.ex test/mobile_car_wash_web/live/tech/profile_live_test.exs
git commit -m "Polish admin invite technician profile status"
```

---

## Final Verification

- [ ] Run `mix format`
- [ ] Run `mix test test/mobile_car_wash/operations/tech_invites_test.exs test/mobile_car_wash/notifications/tech_invite_email_worker_test.exs test/mobile_car_wash_web/live/tech/invite_live_test.exs test/mobile_car_wash_web/live/admin/technicians_live_test.exs test/mobile_car_wash_web/live/tech/profile_live_test.exs`
- [ ] Run `mix precommit`
- [ ] Open `/admin/technicians` locally and manually create one invite.
- [ ] Open the copied setup URL, set password, sign in, verify `/tech/profile` shows admin invite details and `/tech` is available only after acceptance.

## Self-Review

- Spec coverage: admin create flow, same account, approval required, inactive until accepted, email/copy link, applicant status/profile access, admin-invite source, duplicate email rejection, no temp passwords, no public directory.
- Placeholder scan: no TBD/TODO placeholders.
- Type consistency: all later tasks consume `TechInvites.create_admin_invite/2`, `TechInvites.accept_invite/3`, `TechInvites.invite_url/1`, and `TechApplication.source` from earlier tasks.
