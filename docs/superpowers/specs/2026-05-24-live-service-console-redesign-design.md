# Live Service Console Redesign

Date: 2026-05-24
Status: Approved design direction
Mockup: `docs/mockups/live-service-console-mockups-v2.svg`

## Goal

Redesign the iOS appointment-in-progress experience so the technician and customer views feel connected, polished, and operationally useful while staying clear about each user's next action.

The approved direction is a premium field-operations console: confident typography, layered surfaces, crisp status color, subtle route/service linework, and evidence/photo capture integrated directly into the live appointment flow.

## Scope

- iOS technician appointment detail
- iOS technician checklist and photo channels
- iOS customer live appointment status
- Light and dark mode treatments for the same flows

This spec does not introduce new backend API requirements. It should use the existing appointment progress, checklist, photo channel, and photo upload data already implemented.

## Design Principles

- Tech views are action-first, one-hand friendly, and optimized for repeated field use.
- Customer views are calm, status-focused, and trust-building.
- Photos are treated as proof embedded in the workflow, not as a separate afterthought.
- The same appointment state should be translated differently by audience: operational for techs, reassuring for customers.
- Visual polish should support scanning and confidence, not make the UI feel like marketing.

## Light Mode

- Base: warm neutral app background with white elevated panels.
- Primary: electric service blue for navigation, active state, and live appointment emphasis.
- Success: saturated green for completed work and passed steps.
- Attention: amber for in-progress, route, wait, or reconnect states.
- Error: clear red, used sparingly and with direct recovery language.
- Detail: thin borders, soft shadows, and faint service-route linework to add depth without clutter.

## Dark Mode

- Base: near-black background with layered charcoal panels.
- Primary and semantic colors remain recognizable but slightly brighter for contrast.
- Surfaces should feel dimensional through borders, blur-like depth, and restrained glow on active service elements.
- Avoid heavy gradients or large decorative color blocks. Dark mode should feel premium and practical.

## Tech Job Detail

The tech detail screen should make the current appointment state obvious within the first viewport.

Required elements:

- Customer, vehicle, package, and status in a compact hero header.
- A large primary job action card that changes by state, such as start, continue, open checklist, mark complete, or review proof.
- Live service pulse showing current state, progress, ETA, and sync status.
- Evidence board with before, during, after, and issue counts.
- Compact customer/contact/address actions with tappable call, message, and navigation controls.
- Secondary appointment metadata below the primary action area.

Empty, disabled, and offline states must explain what the tech can do next. Disabled actions should never feel like broken buttons.

## Tech Checklist And Photo Channels

The checklist screen should feel like a focused work cockpit.

Required elements:

- Active step card with current step, status, elapsed or expected time, and progress.
- Clear primary controls for start, pause, complete, and add proof.
- Photo channel dock with before, during, after, and issue channels.
- During-work filmstrip for newly uploaded photos.
- Required before/after slots when the workflow demands them.
- Step timeline that shows completed, active, blocked, and remaining items.
- Add Step Photo disabled until a checklist item is active, with helper copy that explains why.

The photo experience should preserve channel context. When a tech uploads from a step, the selected channel and step should stay visible after upload.

## Customer Live Status

The customer screen should reassure without exposing internal workflow complexity.

Required elements:

- Live hero with appointment state, vehicle, service, and friendly status copy.
- ETA and progress cards that update as the technician moves through the appointment.
- "What is happening now" card that maps checklist progress into customer-readable language.
- Latest proof/photo preview when appropriate.
- Completed state that transitions into a before/after proof gallery.
- Clear support/contact option that does not compete with the main status.

The customer should see progress changes and new photos without needing to refresh or navigate away.

## Core Components

- `LiveServicePalette`: semantic colors and surfaces for light/dark mode.
- `ServicePulseHeader`: appointment status, ETA, and sync state.
- `PrimaryJobActionCard`: state-driven primary technician action.
- `EvidenceBoard`: channel counts and upload progress.
- `ChecklistCockpitCard`: active step, controls, and progress.
- `PhotoChannelDock`: before/during/after/issue channel selector.
- `ProofFilmstrip`: compact photo previews with upload states.
- `CustomerLiveHero`: customer-facing status hero and progress summary.

Component names are directional, not mandatory. Prefer existing iOS naming patterns if they already provide a better fit.

## Interactions

- Use 150-250ms transitions for status changes, channel switching, and photo insertions.
- Keep layout stable when progress counts or upload states change.
- Add haptic feedback for technician primary state changes where appropriate.
- Use skeleton or shimmer loading only for network-bound content, not static placeholders.
- Respect reduced motion by simplifying animated progress and pulse treatments.

## Accessibility

- Support Dynamic Type without text overlap.
- Maintain at least 44pt tap targets for all primary controls.
- Preserve contrast in both color schemes.
- Use VoiceOver labels that include state and next action, especially on segmented controls and icon buttons.
- Do not rely on color alone to communicate appointment or checklist state.

## Implementation Notes

- Implement with SwiftUI semantic colors and `ColorScheme` support.
- Reuse the existing appointment progress, checklist, photo channel, and appointment photo models.
- Keep backend behavior unchanged unless implementation reveals a missing field that cannot be derived client-side.
- Avoid broad navigation rewrites; focus on the three appointment-in-progress flows.
- Keep copy concise and state-driven.

## Test Guidance

The project preference is to minimize TDD and add tests only where they clearly reduce risk.

- Add or adjust view-model tests only if behavior changes, such as action enablement, state mapping, or photo channel selection.
- Prefer simulator visual checks for light/dark mode, customer/tech sync, and small/large iPhone layouts.
- No snapshot test requirement for this pass.

## Out Of Scope

- New backend APIs
- Admin web redesign
- Full camera capture replacement beyond the existing picker/upload flow
- Payment, invoice, or earnings redesign
- Marketing or onboarding screens
