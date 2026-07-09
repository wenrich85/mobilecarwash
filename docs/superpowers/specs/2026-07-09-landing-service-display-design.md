# Landing Service Display Control Design

## Goal

Render the landing page product/pricing section from the active services list instead of hardcoded service slugs, and give admins a service-level option that controls whether a service appears on the landing page only.

## Current Problem

`LandingLive` says the pricing area has two tiers, but it only renders cards for hardcoded slugs: `basic_wash`, `deep_clean_detail`, or `premium`. The seeded second service uses `deep_clean`, so the page can show one card while the copy implies two.

The booking page should not be affected. `/book` remains the full active service catalog.

## Data Model

Add `show_on_landing:boolean` to `service_types`.

- Default: `true`
- Public Ash attribute: yes
- Accepted on `ServiceType` create and update actions
- Existing services become visible on the landing page after migration

## Public Landing Page

`LandingLive` will load services using both conditions:

- `active == true`
- `show_on_landing == true`

It will sort by `base_price_cents` and render one card per service. The pricing heading should not hardcode "Two tiers"; it should use count-safe copy such as "Choose the detail that fits today."

The service card should display each service's own:

- `name`
- `base_price_cents`
- `duration_minutes`
- `description`
- booking CTA to `/book?service=<slug>`

The first or most prominent card styling can stay simple and deterministic; no service should require a magic slug to appear.

## Admin Settings

In `/admin/settings`, the Services tab will add a checkbox for both Add Service and Edit Service:

- Label: "Show on landing page"
- Default checked when creating a service
- When unchecked, the service remains active and bookable if `active == true`, but disappears from the landing page

The existing Activate/Deactivate control remains separate and continues to affect both landing and booking visibility through the existing `active` filter.

## Tests

Use TDD.

1. Add a failing landing LiveView test proving the landing page renders all active services with `show_on_landing == true`, including the seeded `deep_clean` slug.
2. Add a failing landing LiveView test proving an active service with `show_on_landing == false` does not render on `/`.
3. Add or update admin/service resource coverage so `show_on_landing` can be set on create and update.
4. Verify `/book` still renders active services regardless of `show_on_landing`.

Run focused tests first, then `mix precommit` before completion.

## Out Of Scope

- Custom landing-only service copy independent of service records
- Drag-and-drop landing ordering
- Hiding services from `/book`
- Subscription plan display changes
