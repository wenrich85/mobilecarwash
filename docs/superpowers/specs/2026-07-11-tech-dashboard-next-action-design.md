# Tech Dashboard Next Action Design

## Goal

Make `/tech` feel like a field technician's workday home screen. A technician should immediately know whether they are on shift, which job matters next, and what single action to take now.

This slice improves hierarchy and decision logic in the existing dashboard. It does not change the technician data model, appointment state machine, checklist internals, route optimization, or earnings calculations.

## Current State

The existing `/tech` dashboard already has useful operational pieces:

- Duty status controls.
- Today, tomorrow, and upcoming appointment lists.
- Appointment actions for depart, arrive, checklist start/continue, and supply logging.
- A route map.
- Available appointments in the technician's zone.
- Requested appointments awaiting dispatch.
- Earnings summaries.

The problem is hierarchy. On mobile, these sections compete for attention, and the first viewport does not consistently answer "what do I do next?"

## User Stories

- As an off-duty technician with work today, I can start my shift from the first screen.
- As an available technician, I can see my next assigned job and open it without scanning the whole schedule.
- As a technician en route, I can mark myself arrived from the dashboard.
- As a technician on site, I can start the wash from the dashboard.
- As a technician with an active checklist, I can continue the checklist from the dashboard.
- As a technician with no remaining work today, I can see that clearly without hunting through empty sections.
- As an admin viewing `/tech` without a linked technician record, I keep the existing admin-view behavior rather than receiving a personal workday card.

## Recommended Approach

Use a "Next Action First" dashboard.

Keep the existing dashboard capabilities, but reorganize the top of `/tech` around a new Workday Command Card. The card should show:

- Duty status.
- Primary work item, if one exists.
- Appointment time, customer, service, vehicle, and location summary.
- One primary CTA.
- Short supporting copy explaining why that action is next.

The rest of the dashboard remains available below the command card, with quieter section hierarchy:

1. Today queue.
2. Route map.
3. Tomorrow.
4. Upcoming.
5. Requested appointments.
6. Available in your zone.
7. Earnings.

This keeps the existing functionality while making the first viewport action-oriented.

## Command Card Rules

The dashboard should derive a small internal view model for the command card from the already-loaded technician record, today's appointments, and checklist progress.

Priority order:

1. If the tech is `:off_duty` and has actionable work today, show `Start shift`.
2. Prefer active work over future work:
   - `:in_progress`
   - `:on_site`
   - `:en_route`
   - `:confirmed`
3. If multiple appointments share the same priority, use the earliest scheduled appointment.
4. `:pending` appointments appear in the queue but do not become the primary CTA unless there are no actionable jobs.
5. Completed appointments may surface only when supply logging is still relevant and there are no active or next jobs.
6. If no actionable jobs remain today, show a calm done/empty state.
7. Admins without a linked technician record do not receive a personal command card.

Primary CTA mapping:

- `:off_duty` with actionable work: `Start shift`.
- `:available` with a confirmed next job: `View job`.
- Confirmed appointment from command card: `View job`, with the job brief handling `Head out`.
- `:en_route`: `Mark arrived`.
- `:on_site`: `Start wash`.
- `:in_progress` with checklist: `Continue checklist`.
- Completed appointment with no active/next jobs: `Log supplies`.
- No actionable work: no destructive or fake action; show profile and earnings links if helpful.

The command card should avoid showing multiple equivalent primary actions. Secondary links are acceptable only when they support the primary action, such as "View profile".

## Today Queue

Keep the appointment row component, but make it easier to scan:

- Label the command-card appointment as `Next` or `Active`.
- Preserve existing row actions for job brief, checklist, pending copy, and supply logging.
- Do not duplicate the command card's primary action in a confusing way; if both appear, the row action should use the same destination or event.
- Keep tomorrow and upcoming sections below today's work.

## Map Placement

Move the map below the command card and today queue. The map remains useful for route awareness, but it should not compete with the technician's immediate action.

The existing map hook and pin-building behavior should remain intact.

## Data And Architecture

Use existing resources and LiveView patterns:

- Main file: `MobileCarWashWeb.TechDashboardLive`.
- Existing resources: `Technician`, `Appointment`, `ServiceType`, `Customer`, `Address`, `Vehicle`.
- Existing helpers: `Dispatch.checklist_progress/1`, appointment transition actions, `WashOrchestrator.start_wash/1`.
- Existing PubSub reload behavior for assignment and appointment updates.

Add small private helpers in `TechDashboardLive` for:

- Building the command-card state.
- Choosing the primary appointment.
- Formatting the command-card label and CTA.
- Determining whether a row is active/next.

Do not extract a new module unless the helper logic becomes large enough that the LiveView becomes harder to understand. This slice should stay close to the existing dashboard.

## Error Handling

- Appointment transition failures keep using flash errors.
- Missing technician records keep the existing warning state.
- Missing customer/service/address/vehicle data should degrade to existing fallback labels.
- Checklist progress missing from the progress map should use the existing empty progress fallback.
- Unknown statuses should render a safe "Review schedule" state rather than crashing.

## Testing

Extend `test/mobile_car_wash_web/live/tech/tech_dashboard_live_test.exs`.

Coverage should include:

- Off-duty tech with a today confirmed job sees the command card and `Start shift`.
- Available tech with a confirmed job sees the job as next and can open the job brief.
- En-route job shows `Mark arrived`.
- On-site job shows `Start wash`.
- In-progress job with checklist shows `Continue checklist`.
- No today jobs shows the empty/done state.
- Admin without a linked technician record keeps the admin warning and does not render a personal command card.
- Existing today, tomorrow, and upcoming appointment rows still render.
- Duty status changes still update the dashboard.
- Appointment transitions still reload the dashboard.

Focused tests should run before the full suite:

```bash
mix test test/mobile_car_wash_web/live/tech/tech_dashboard_live_test.exs
```

Full verification before merge:

```bash
mix precommit
```

## Acceptance Criteria

- `/tech` opens with a clear Workday Command Card for linked technicians.
- The card shows exactly one primary next action when actionable work exists.
- Active or next appointment selection is deterministic and status-aware.
- Today, tomorrow, upcoming, zone requests, map, supply logging, and earnings remain available.
- Admin and missing-technician fallback states continue to work.
- Existing job brief and checklist flows are linked rather than rebuilt.
