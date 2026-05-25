# Admin Dispatch Command Center

Date: 2026-05-25
Status: Approved design direction
Mockup: Browser companion option A, "Live Command Board"

## Goal

Redesign the admin Dispatch Center into a live operations board for same-day service control.

The approved direction is the Live Command Board: live appointment monitoring first, fast assignment and triage second. The screen should answer three questions immediately:

- What is happening right now?
- What needs attention?
- Who can take the next job?

## Scope

- Existing Phoenix admin dispatch route and LiveView
- Same-day appointment operations
- Technician availability and workload visibility
- Active appointment progress, customer-visible sync, photo/checklist readiness, and exception surfacing
- Light and dark mode-ready visual treatment using the web app's existing styling stack

This spec does not introduce duplicate backend endpoints. Implementation should use existing contexts, schemas, broadcasts, checklist progress, appointment photos, technician tracking, and admin dispatch actions unless a missing field is discovered and cannot be derived safely.

## Design Principles

- Dispatch should feel like a command center, not a static list.
- Live state should be more prominent than historical or setup data.
- Assignment actions should be visible exactly where the decision is made.
- Exceptions should be impossible to miss but calm enough to work through.
- The map is useful context, not the primary control surface for the first implementation slice.
- Technician management should remain available without dominating the daily operations view.

## Layout

The first viewport should be dense, scannable, and operational.

Required regions:

- Command bar with date, live connection state, refresh state, total jobs, on-duty technicians, and exception count.
- Live status cards for in progress, unassigned/ready to assign, completed, and blocked/needs attention.
- Active service board showing appointments currently en route, on site, or in progress.
- Assignment queue for pending/unassigned work sorted by urgency.
- Technician workload rail showing availability, duty state, current appointment, zone, and workload pressure.
- Map/context panel using the existing dispatch map as supporting context.
- Exceptions panel for late appointments, missing assignment, missing required photos, stalled checklist progress, customer flags, and tech/customer sync mismatches.

On desktop, the recommended structure is:

- Top: command bar and status cards.
- Main left: active service board and assignment queue.
- Right rail: technician workload, map context, and exceptions.
- Lower section: Kanban or status columns as a secondary planning view.

On narrower screens, regions should stack in this order: command bar, exceptions, active service board, assignment queue, technician rail, map, status columns.

## Core Components

Component names are directional. Prefer existing Phoenix module conventions if they provide better names.

- `dispatch_command_bar`: live date, refresh, connection, and summary chips.
- `dispatch_metric_cards`: counts and status summaries.
- `active_service_board`: current service rows/cards with progress and next action.
- `active_service_row`: appointment, technician, customer-visible state, checklist/photo progress, ETA, and quick links.
- `assignment_queue`: pending and unassigned jobs sorted by urgency.
- `assignment_card`: appointment summary, zone, schedule pressure, customer/vehicle/service, recommended assignment actions.
- `technician_workload_rail`: technician duty state, workload, current job, and assignment fit.
- `exception_panel`: attention items grouped by severity and recovery action.
- `map_context_panel`: existing map hook wrapped in a lighter operational shell.
- `status_kanban`: existing Kanban board retained as a secondary planning tool.

## Data Flow

The LiveView should continue to own data loading, subscriptions, filters, and events.

Use existing data where possible:

- Appointments, statuses, scheduled times, assigned technicians, services, customers, vehicles, addresses, zones, and customer tags.
- Technician tracker status for on-duty, available, break, active appointment, and zone signals.
- Checklist progress and appointment photo/channel data from the recent service progress work.
- Appointment update, technician status, and tech request broadcasts already used by dispatch.

Derived values should stay close to `Admin.DispatchLive` until they prove reusable:

- Needs-action reason
- Assignment priority
- Live progress summary
- Technician workload pressure
- Customer/tech sync status
- Required-photo readiness

If a derived value becomes complex, extract a small pure helper module with focused tests.

## Admin Actions

Required actions:

- Assign or reassign a technician.
- Confirm a pending assigned appointment.
- Filter by date, status, technician, zone, and needs-action.
- Open the live appointment/service console.
- Open customer, technician, and appointment context from the relevant card.
- Keep technician management accessible without making it the center of the page.

Nice-to-have actions for a later slice:

- Batch assignment or batch confirm.
- Suggested best technician ranking.
- Route pressure optimization.
- Manual exception dismissal or acknowledgement.

## Exception States

The command center should surface operational risks clearly:

- Pending appointment with no technician assigned.
- Pending appointment assigned but not confirmed.
- Appointment starting soon without required readiness.
- In-progress appointment with missing required before/after photos.
- Checklist progress stalled or not started after arrival.
- Customer-visible status out of sync with technician progress.
- Technician request waiting for admin response.
- Flagged customer or do-not-service tag.
- Backend reconnecting while stale data remains visible.

Each exception should include a short reason and the most likely recovery action.

## Visual Direction

Light mode:

- Crisp white and soft gray base.
- High-contrast black type.
- Blue for live/assignment emphasis.
- Green for completed/healthy states.
- Amber and red for attention states.
- Thin borders, compact shadows, and status rails for scan speed.

Dark mode:

- Charcoal base with elevated panels.
- Slightly brighter semantic colors for contrast.
- Subtle glow or border treatment only around active/live elements.
- Avoid heavy gradients, novelty visuals, or decorative noise.

The page should feel professional and a little more creative than a stock admin table: operational cards, status rails, progress bars, compact maps, and live activity markers.

## Interactions

- Keep assignment controls inline with appointment cards.
- Use stable card dimensions so live progress updates do not shift the page.
- Use short transitions for updated counts, active appointment progress, and exception arrival.
- Preserve visible stale data during reconnecting states and label it clearly.
- Keep filters fast and reversible.
- Avoid requiring modal hops for common same-day actions.

## Accessibility

- Use semantic buttons and links for all actions.
- Maintain contrast in light and dark mode.
- Do not rely on color alone for status; include labels or icons.
- Keep touch/click targets comfortable in dense layouts.
- Use stable DOM IDs on key controls and cards for LiveView tests.

## Implementation Notes

- Start by redesigning the existing `MobileCarWashWeb.Admin.DispatchLive` and `MobileCarWashWeb.Admin.DispatchComponents`.
- Do not create a parallel dispatch route unless implementation reveals a hard reason.
- Preserve existing subscriptions and refresh behavior.
- Keep the existing map hook, but place it in a more intentional context panel.
- Avoid duplicating endpoints or backend actions that already exist.
- Keep the first implementation focused on the command center surface; route optimization and batch actions can follow.

## Test Guidance

Project preference is to minimize TDD and add tests only where they clearly reduce risk.

Recommended coverage:

- Component tests for active service, unassigned assignment, exception, and technician workload states.
- One LiveView interaction test for assign/confirm if existing selectors are stable.
- Pure helper tests only if assignment priority, exception derivation, or sync status becomes non-trivial.

Avoid broad visual snapshot tests and brittle copy assertions.

## Out Of Scope

- New dispatch backend endpoints by default
- Full route optimization engine
- Batch operations
- Billing, earnings, history, marketing, or customer booking redesign
- Replacing the existing map provider or hook
- Full technician management redesign beyond making it accessible from dispatch
