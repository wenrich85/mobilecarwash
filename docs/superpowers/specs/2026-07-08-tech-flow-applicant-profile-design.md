# Tech Flow, Applicant Portal, and Private Profile Design

Date: 2026-07-08
Status: Approved for planning

## Goal

Improve the technician experience around two connected journeys:

1. The field workflow for accepted technicians doing appointments.
2. The private applicant/profile workflow for customers who want to become technicians.

The app already has strong operational primitives: `Customer` accounts, `Technician` records, role-based auth, appointment transitions, checklists, photos, earnings, and admin technician screens. This design keeps those primitives and reshapes the UX around user stories.

## Current Structure

Existing strengths:

- `Customer` is the login identity and supports roles `:customer`, `:technician`, `:admin`, and `:guest`.
- `Technician` supports name, phone, active flag, pay rate, zone, duty status, van assignment, and an optional `user_account_id`.
- `/tech` already shows a technician dashboard for users with role `:technician` or `:admin`.
- `/tech/checklist/:id` already supports before photos, step timers, notes, optional skips, after photos, and completion logic.
- `/admin/technicians` and `/admin/technicians/:id` already support technician operations management.

Current gaps:

- No applicant intake flow.
- No applicant status page.
- No admin application review queue.
- No single approval action that promotes an existing customer account to technician.
- No private tech-facing profile page.
- No dedicated job brief page.
- The current dashboard and checklist are capable but carry too many responsibilities at once.

## Product Model

Add a `TechApplication` resource tied to an existing `Customer`.

Applicants use the same account they use as customers. While their application is in progress or not accepted, their `Customer.role` remains `:customer`. When an admin accepts them, the system promotes that same account to `:technician` and creates or links a `Technician` record.

Application statuses:

- `draft`: applicant is still filling it out.
- `pending_review`: applicant submitted and is waiting for admin review.
- `reviewed`: admin has reviewed but has not made a final decision.
- `accepted`: applicant is approved and should have a linked `Technician`.
- `not_accepted`: applicant was declined and remains a normal customer.

## Application Fields

Applicant-editable structured fields:

- Preferred name
- Phone confirmation
- Home ZIP or service base ZIP
- Preferred zone
- Availability: weekdays, weekends, mornings, afternoons, evenings
- Experience level: none, some, professional
- Has valid driver license
- Has reliable transportation
- Can lift and carry supplies
- Desired hours per week
- Earliest start date
- Emergency contact name
- Emergency contact phone

Applicant-editable narrative prompts:

- Why do you want to work with us?
- What car wash or detailing experience do you have?
- Anything we should know about your schedule or transportation?

Admin-only review fields:

- Internal review notes
- Decision note visible to applicant
- Accepted pay type and pay value
- Assigned zone
- Van assignment
- Active flag

## Applicant and Tech Routes

Add or refine these authenticated pages:

- `/tech/apply`
  - If the signed-in customer has no application, create or initialize a draft.
  - If they have a draft, resume the editable application.
  - If they have submitted, show the read-only status state or redirect to `/tech/application`.

- `/tech/application`
  - Shows application status, submitted data, decision note, and next steps.
  - Available to the owner of the application and admins.

- `/tech/profile`
  - Before acceptance, shows private applicant profile and status.
  - After acceptance, shows technician profile data: account info, pay rate, assigned zone, active status, van assignment, and performance summary.

Keep these existing pages:

- `/tech`
  - Operational dashboard for accepted technicians only.

- `/admin/technicians`
  - Operational technician list.

- `/admin/technicians/:id`
  - Operational admin technician profile.

## Admin Routes

Add:

- `/admin/tech-applications`
  - Application queue grouped and filterable by status.

- `/admin/tech-applications/:id`
  - Review detail page.
  - Admin can mark reviewed, accept, not accept, add notes, and set technician creation values.

Acceptance behavior:

- Update the linked `Customer.role` to `:technician`.
- Create a `Technician` record if one does not exist.
- Link `Technician.user_account_id` to the applicant `Customer`.
- Copy practical fields such as preferred name, phone, zone, and pay settings.
- Keep the customer account and booking history intact.

## Access Rules

- Anonymous visitors to `/tech/apply` are redirected to sign in or register, then returned.
- Signed-in customers can create and view only their own application.
- Non-accepted applicants cannot access the operational `/tech` dashboard.
- Accepted technicians can access `/tech`, `/tech/profile`, customer pages, and their own application history.
- Admins can access all applications and all technician profiles.
- Declined applicants remain customers and can continue booking services.

## Improved Technician Work Flow

The field workflow should be organized into four modes plus profile:

1. Today
   - Shift status
   - Next job
   - Route/map
   - Today queue
   - Dispatch changes and requested jobs

2. Job Brief
   - One appointment at a time
   - Customer, vehicle, service, address, notes, and problem photos
   - One clear next action: `Head out`, `Arrived`, or `Start wash`

3. Active Wash
   - Before photo progress
   - One active step at a time
   - Timer, notes, optional skip, and during-photo action
   - After photo progress

4. Wrap-Up
   - Completion confirmation
   - Supply logging
   - Final notes
   - Earnings impact
   - Next job

5. Profile
   - Private profile and application status
   - Pay rate
   - Zone
   - Account info
   - Performance summary

The tech should always see one obvious next action based on state:

- Off duty: Start shift
- Available with next confirmed job: View job
- Confirmed job: Head out
- En route: Mark arrived
- On site: Start wash
- Wash active with missing before photos: Finish before photos
- Active step: Complete step
- Required steps done: Take after photos
- After photos done: Finish job or wrap up
- Job completed: Log supplies or view next job

## Implementation Boundaries

Use existing patterns:

- Ash resources for `TechApplication` and state transitions.
- Phoenix LiveViews for applicant, profile, and admin screens.
- Existing `Customer` auth instead of a separate applicant identity.
- Existing `Technician` resource for accepted technician operations.
- Existing `Photo` and `PhotoUpload` only for appointment evidence; applicant demographics are structured fields, not media uploads.

Do not build:

- Public technician profile pages.
- A public technician directory.
- Background-check integrations.
- A full HR/recruiting module.
- Separate applicant login identities.

## Testing Strategy

Focused tests should cover:

- A signed-in customer can create, save, and submit a draft application.
- A customer can only view their own application.
- A pending applicant cannot access `/tech`.
- Admin can review, accept, and not accept applications.
- Acceptance creates or links `Technician` and promotes `Customer.role` to `:technician`.
- Accepted tech can access `/tech` and `/tech/profile`.
- Declined applicant remains a customer.
- Admin technician creation remains compatible with direct technician management.

## Success Criteria

- A customer can apply to become a tech without creating a second account.
- An applicant can log in and clearly see their status.
- Admin can approve an applicant and produce a working technician account in one flow.
- Accepted technicians have a private profile that explains pay, zone, account, and work summary.
- The field tech workflow becomes easier to reason about by separating Today, Job Brief, Active Wash, Wrap-Up, and Profile.
