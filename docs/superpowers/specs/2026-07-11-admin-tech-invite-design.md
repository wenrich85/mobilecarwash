# Admin Tech Invite Design

## Goal

Give admins a direct way to create a full technician account and send a secure setup invite without handling a password. The technician should be visible to admins as an invited, inactive technician, but should not be schedulable until they accept the invite and set their password.

## User Stories

- As an admin, I can invite a technician from the admin technicians area without asking the technician to submit an application first.
- As an admin, I can enter the technician's full profile details up front: contact info, demographics, availability, experience, eligibility flags, emergency contact, operational zone, pay rate, optional van, and internal notes.
- As an admin, I can send the invite by email and also copy the setup link manually.
- As an admin, I can see whether the technician is waiting for setup, active, expired, or already accepted.
- As an invited technician, I can open a one-time setup link, set my password, and land in my private technician profile/dashboard.
- As the business, invited technicians cannot receive assignments until setup is accepted.

## Scope

In scope:

- Admin-facing invite form for full technician creation.
- Inactive technician records created from invites.
- One-time setup token and password setup page.
- Invite email plus copyable fallback URL.
- Invite status display and resend action.
- Tests for invite creation, setup acceptance, activation, and expired/invalid token handling.

Out of scope:

- Public technician directory pages.
- Bulk CSV imports.
- Background onboarding tasks beyond the first invite email.
- Changing the applicant self-service flow.
- Letting admins see or set a technician's password.

## Recommended Flow

1. Admin opens `/admin/technicians` and clicks `Invite technician`.
2. Admin fills one form with full profile and operational data.
3. On submit, the system creates a customer account with role `:technician`, a linked inactive technician record, an audit/profile record containing the demographic application data, and a one-time invite token.
4. The success view shows `Waiting for setup`, a copyable setup URL, and a `Resend invite` action.
5. The system sends an invite email with the setup URL.
6. Technician opens the link, sets a password, and accepts the invite.
7. System marks the invite accepted, activates the technician, and routes the technician to `/tech/profile` or `/tech`.

## Data Model

Add a dedicated invite resource rather than overloading password reset tokens. This keeps admin-created tech onboarding auditable and lets the admin UI show invite state directly.

`TechInvite` fields:

- `id`
- `customer_id`
- `technician_id`
- `token_hash`
- `status`: `:pending | :accepted | :expired | :revoked`
- `sent_at`
- `accepted_at`
- `expires_at`
- `created_by_admin_id`
- `last_sent_at`

The raw token is generated only at creation/resend time and never stored. The database stores the hash. Setup URLs include the raw token.

Use `TechApplication` as the audit/profile carrier for the full demographic data. Add a `source` field with values `:applicant` and `:admin_invite`; self-service applications default to `:applicant`, and admin-created invites write `source: :admin_invite` with `status: :accepted`.

## Account Rules

- Customer account is created with role `:technician`.
- Technician record is created with `active: false`.
- Technician does not appear in schedulable technician lists while inactive.
- Accepting a valid invite sets the password and activates the technician.
- Existing customer email collisions are handled deliberately:
  - If the email belongs to an existing technician, show an error with a link to that technician.
  - If the email belongs to an existing customer, allow the admin to convert/invite only after an explicit confirmation step in a later slice. First slice should return a clear error to avoid surprising role changes.

## Admin UI

Entry points:

- `/admin/technicians` gets an `Invite technician` action.
- Optional follow-up entry from `/admin/tech-applications`, but the first slice should focus on the technicians page.

Invite form sections:

- Identity: legal/display name, email, phone.
- Demographics: home ZIP, preferred zone, availability, desired hours, earliest start date.
- Experience and requirements: experience level, experience notes, schedule notes, valid driver's license, reliable transportation, can lift supplies.
- Emergency contact: name and phone.
- Operations: assigned zone, pay rate cents or percent, optional van, active after setup defaults to true.
- Admin notes: internal onboarding/review notes.

Success and detail states:

- Show invite status and expiration date.
- Show copyable setup URL immediately after create/resend.
- Provide resend action for pending or expired invites.
- Do not show the raw setup URL after the LiveView state is lost unless a new resend regenerates a token.

## Technician Setup UI

Route:

- `/tech/invite/:token`

Behavior:

- Valid pending token shows password and password confirmation fields.
- Invalid, revoked, accepted, or expired token shows a safe error and a support/contact note.
- Successful setup signs the tech in if consistent with existing auth behavior; otherwise redirects to `/sign-in` with a success flash.
- After setup, route to `/tech/profile` or `/tech`.

## Email

Send an invite email on creation and resend. Email content should include:

- Business name.
- Invited technician name.
- Setup link.
- Expiration date.
- Support/contact language.

The admin UI must also show a copyable setup URL as fallback because email deliverability can lag or fail in production.

## Security

- Never store raw invite tokens.
- Tokens expire, with a default of 7 days.
- Resend rotates the token.
- Accepted tokens cannot be reused.
- Setup action validates token status and expiration server-side.
- Password is set only through the existing customer password hashing/authentication mechanism.
- Admin-created accounts must remain inactive until setup succeeds.
- The invite setup page must not leak whether unrelated customer emails exist.

## Testing

Resource tests:

- Creating an invite creates a customer role `:technician`, inactive technician, profile/audit data, and pending invite token.
- Duplicate technician email is rejected.
- Accepting a valid invite sets password, marks invite accepted, activates technician, and prevents token reuse.
- Expired/revoked tokens cannot be accepted.
- Resend rotates token and updates sent timestamps.

LiveView tests:

- Admin can open invite form from `/admin/technicians`.
- Admin can create a full invite and sees copyable URL plus waiting status.
- Admin can resend a pending/expired invite.
- Invited tech can set password from a valid setup URL.
- Invalid/expired setup URL shows a safe error.
- Inactive invited technicians do not appear in scheduling/assignment lists until accepted.

Email tests:

- Invite creation triggers the invite email.
- Resend triggers a new email with a rotated URL.

## Implementation Notes

- Follow existing Ash resource patterns and LiveView route/session conventions.
- Keep applicant self-service untouched.
- Prefer a small, explicit `TechInvite` resource over adding generic token logic to unrelated modules.
- Run `mix precommit` before merge.
