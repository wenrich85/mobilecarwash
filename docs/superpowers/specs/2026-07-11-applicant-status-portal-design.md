# Applicant Status Portal Design

## Goal

Improve the logged-in technician applicant experience on the existing `/tech/application` route so applicants can clearly understand their current status, what happens next, and what information is on file.

## Scope

In scope:

- Applicant-facing UX on `/tech/application`.
- Status-aware guidance for `draft`, `pending_review`, `reviewed`, `accepted`, and `not_accepted`.
- Clear actions for drafts, accepted applicants, and applicants without an application.
- Readable submitted details: contact, zone, availability, requirements, narrative, submitted/reviewed/decided timestamps.
- Applicant-visible decision note when a final decision exists.
- Tests that verify each status state renders the right guidance and actions.

Out of scope:

- Changing admin review transitions.
- Adding new application statuses.
- Adding a new route.
- Editing submitted applications after submission.
- Public applicant pages.
- Notifications or email.
- A separate applicant account model.

## Current State

The data model, route, and admin transitions already exist:

- `MobileCarWash.Operations.TechApplication` supports `draft`, `pending_review`, `reviewed`, `accepted`, and `not_accepted`.
- `/tech/apply` lets a signed-in customer save and submit a draft.
- `/tech/application` shows a basic status page.
- `/tech/profile` shows broader applicant and technician profile details.
- `/admin/tech-applications` lets admins review, accept, or decline.

The gap is that `/tech/application` reads like a basic status card instead of a real applicant portal. Applicants need a more guided page that answers, "Where am I, what is next, and what did I submit?"

## User Stories

- As a signed-in customer with no application, I can see that I have not started and can begin the application.
- As a draft applicant, I can see that my application is not submitted yet and can continue editing it.
- As a pending applicant, I can see that admin has my application and that no action is needed right now.
- As a reviewed applicant, I can see that review happened and a final decision is still pending.
- As an accepted applicant, I can see that I am accepted and can move to technician profile/tools.
- As a not accepted applicant, I can see the applicant-visible decision note without seeing internal review notes.
- As any applicant, I can review the core details attached to my account.

## Design

Keep `/tech/application` as the applicant status hub. The page should have four clear regions:

1. Header
   - Page title: "Application Status".
   - Status badge using the existing status vocabulary.
   - Short status-specific summary.

2. Status journey
   - A horizontal or stacked step list with these stages:
     - Draft
     - Pending review
     - Reviewed
     - Decision
   - The active/completed state is derived from `TechApplication.status`.
   - Accepted and not accepted both complete the Decision step, with different labels.
   - No application shows all steps as upcoming.

3. Next action
   - No application: primary action to start `/tech/apply`.
   - Draft: primary action to continue `/tech/apply`.
   - Pending review: no action needed; explain admin review.
   - Reviewed: no action needed; explain final decision is pending.
   - Accepted: primary action to `/tech/profile` and secondary action to `/tech`.
   - Not accepted: no technician action; show applicant-visible decision note if present.

4. Submitted details
   - For existing applications, show applicant-facing details:
     - preferred name, phone, home ZIP, preferred zone
     - desired hours, earliest start date, experience
     - availability days and times
     - driver license, transportation, lifting supplies flags
     - emergency contact
     - why work with us, experience notes, schedule notes
     - submitted, reviewed, decided timestamps
   - Do not show internal `review_notes` on `/tech/application`.
   - Show `decision_note` only when status is `accepted` or `not_accepted`, or when a final decision has been made.

## Status Copy

No application:

- Summary: "Start an application to share your availability and technician details."
- Next step: "Fill out the application and save a draft before submitting it for review."

Draft:

- Summary: "Your application is saved, but it has not been submitted yet."
- Next step: "Finish any remaining details and submit when ready."

Pending review:

- Summary: "Your application is in the admin queue."
- Next step: "No action needed right now. We will review your application and update this page."

Reviewed:

- Summary: "Your application has been reviewed."
- Next step: "A final decision is still pending. Watch this page for the next update."

Accepted:

- Summary: "You have been accepted."
- Next step: "Your technician profile is ready. Use your profile to review pay, zone, and account details."

Not accepted:

- Summary: "Your application was not accepted at this time."
- Next step: "You can keep using this customer account normally. Any applicant-visible note from the team appears below."

## Architecture

This is a LiveView-only slice backed by the existing `TechApplication` resource.

- Modify `MobileCarWashWeb.Tech.ApplicationLive`.
- Extend `test/mobile_car_wash_web/live/tech/application_live_test.exs`.
- Reuse existing helper patterns in the LiveView for labels, badges, date formatting, boolean formatting, and route links.
- Do not add migrations or Ash actions.

## Data Rules

- `TechApplication.status` remains the source of truth.
- `review_notes` are internal and must not render on `/tech/application`.
- `decision_note` is applicant-visible only once there is a final decision.
- Applicant ownership continues to use `:for_customer` with the signed-in customer id.
- Submitted applications still redirect away from `/tech/apply` unless status is `draft`.

## Testing

Add or extend LiveView tests for:

- No application shows a start action.
- Draft shows a continue action and the draft status journey.
- Pending review shows no action needed and no internal review notes.
- Reviewed shows reviewed timestamp and final-decision-pending copy.
- Accepted shows links to `/tech/profile` and `/tech`.
- Not accepted shows the applicant-visible decision note and hides internal review notes.
- Submitted details render for an applicant-owned application.

## Acceptance Criteria

- `/tech/application` clearly communicates every supported status.
- Applicants can find their next action in one scan.
- Internal admin review notes are not exposed on the applicant status page.
- Accepted applicants have a clear path to technician profile/tools.
- Existing `/tech/apply`, `/tech/profile`, and admin review behavior continues to pass tests.
