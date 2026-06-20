# Design Spec — Single-page booking flow + geocoder address autocomplete

**Date:** 2026-06-20
**Status:** Approved
**Supersedes the wizard flow from:** `docs/superpowers/specs/2026-06-19-booking-flow-redesign-design.md` (§2 step flow). Builds on Phase 1–3 work (live pricing, add-ons, NHTSA vehicle step) already merged into `main`.

---

## 1. Goal & non-goals

**Goal:** Replace the multi-step booking wizard with a **single, continuously scrolling page** that reveals sections progressively, and add **as-you-type address autocomplete** with a confirmation map.

**Non-goals:**
- No change to the server-authoritative pricing or the Stripe payment backend (`Booking.create_booking/1` + dynamic `unit_amount`).
- No change to the NHTSA vehicle section's internals (dropdowns/VIN/size/loading) — it is re-homed as a section, not rewritten.
- No camera/OCR VIN scanning.
- Photos are **removed** from the booking flow (the photo subsystem elsewhere is untouched).

## 2. Decisions (from brainstorming)

- **Progressive reveal**, one scroll: sections unlock in order as prerequisites are met; locked sections render as muted placeholders.
- **Freely editable:** completed sections stay open/editable; editing one live-updates the price and preserves still-valid later selections.
- **Auth:** an optional "Sign in" prompt pinned near the top (returning customers → saved vehicles/addresses prefill); **guests enter contact (name/email/phone) at the bottom** in Review & Pay; the guest customer is created at pay time.
- **Photos dropped** from booking.
- **Address autocomplete + confirmation map** (US Census geocoder default; Photon/OSM fallback).

## 3. Section order (single page)

Sticky **price hero** (existing `PriceHeader`) at top, then optional **Sign in** prompt, then:

1. **Service** (required)
2. **Add-ons** (optional)
3. **Vehicle** (required) — existing NHTSA section
4. **Address** (required) — geocoder autocomplete + map (Sub-project 2)
5. **Schedule** (required)
6. **Review & Pay** (required) — guest contact fields + Pay button

Each section has status `:locked → :active → :complete`. A required section is `:complete` when its selection is present; the **Pay** button enables only when all required sections are complete and contact is present.

---

## 4. Architecture

### 4.1 Decomposition (two sub-projects, two plans)

- **Sub-project 1 — Single-page progressive-reveal redesign** (built first). Restructures `BookingLive` into stacked sections driven by a pure status module; address uses the existing saved-list+manual form for now.
- **Sub-project 2 — Geocoder address autocomplete + map** (built second). Adds `Fleet.GeocoderClient` and replaces the address section body with typeahead/autofill/zone/Leaflet pin.

### 4.2 Sub-project 1 components

- **`MobileCarWash.Booking.BookingSections`** (new, pure; replaces the linear `StateMachine` for the UI): given the accumulated context (`selected_service`, `selected_add_ons`, `selected_vehicle`, `selected_address`, `selected_slot`, `current_customer`/contact), returns each section's status (`:locked | :active | :complete`) and whether the order is payable. Reuses the existing `present?` guard semantics. Pure, no Phoenix/Ash deps, unit-tested. (The old `StateMachine` may remain for any non-UI callers but the single page no longer uses `transition/3`.)
- **`MobileCarWashWeb.BookingLive`** (rewritten render + state): one `/book` route, one LiveView. Renders the sticky hero + sign-in prompt + the six section cards, each gated by its `BookingSections` status. Removes the step indicator and `next_step`/`prev_step`/photos upload configs. Reuses existing event handlers (`select_service`, `toggle_add_on`, vehicle handlers incl. `vehicle_form_change`/`decode_vin`/`handle_async`, address handlers, schedule/slot handlers) and `assign_price_breakdown`. On completing a section, pushes a small client scroll-to-next.
- **Auth:** the top "Sign in" reuses the existing `/book/sign-in` route (stashes `return_to=/book`); on return, saved vehicles/addresses prefill. Guest contact captured in Review & Pay; guest customer created at submit via the existing `create_guest` path (today's `guest_checkout` logic, relocated to the pay submit).
- **Pay:** Review & Pay submit runs the existing `Booking.create_booking/1` + Stripe checkout, unchanged.
- **Persistence:** keep the DB-backed `SessionCache` (resume a half-filled page across reconnect/sign-in).

### 4.3 Sub-project 2 components

- **`MobileCarWash.Fleet.GeocoderClient`** (new, mockable, server-side `Req`; mirrors `Vehicles.NhtsaClient`/`Notifications.TwilioClient`). Mockable via `config :mobile_car_wash, :geocoder_client`.
  - `suggest(query :: String.t()) :: {:ok, [%{label, street, city, state, zip, lat, lng}]} | {:error, term()}`.
  - Default provider **US Census** (`geocoding.geo.census.gov`, free, no key, US-only); **Photon/OSM fallback** behind the same module. No client-side keys; CSP/`connect-src` unchanged (server-proxied).
- **Address section rework:** a debounced (`phx-change`, ~250ms) text input streams suggestions; selecting one autofills street/city/state/zip, stores `latitude`/`longitude` (columns already on `Address`), resolves the service zone via `MobileCarWash.Zones`, and drops a **Leaflet pin** via the existing `DispatchMap` hook (CSP already allows OSM/Carto/Stadia tiles). Manual entry + saved-address chips remain as fallback. Zone feedback: `✓ In service area · <zone>` or `⚠ Outside our service area — we'll confirm or refund` (proceed allowed).
- **Test mock:** `Fleet.GeocoderClientMock` (ETS-backed staging, like `NhtsaClientMock`) so tests never hit the network.

### 4.4 Loading/responsiveness
- Remote lookups (NHTSA models already; geocoder suggestions) run without freezing the UI — async/`start_async` with a lightweight loading indicator, consistent with the vehicle section. Geocoder input is debounced to limit calls.

## 5. Error handling & fallbacks
- **Section gating:** sections can't complete out of order; Pay disabled until all required sections complete + contact present.
- **Geocoder down / no matches:** fall back to manual street/city/state/zip entry; zip→zone still computed.
- **Outside service zone:** warn but allow (admin confirms/refunds) — today's behavior, explicit in the UI.
- **Resume:** `SessionCache` restores a partially filled page.
- Existing NHTSA/cache resilience retained.

## 6. Testing strategy
- **`BookingSections`** (pure): unit tests across status transitions (locked→active→complete; payable gating; editing-an-earlier-section effects).
- **`GeocoderClient`/mock:** unit tests via the mock; no live network.
- **LiveView (single page):** progressive reveal (later sections locked until prereqs), edit-an-earlier-section updates price + preserves valid later state, signed-in prefill, guest contact-at-end + pay happy path, address typeahead → select → autofill + zone + map-hook present.
- TDD per repo convention; `mix precommit` green before each plan merges.

## 7. Security & privacy
- All third-party calls (NHTSA, geocoder) server-side via `Req`, mockable; no client keys; CSP unchanged. Geocoded coordinates already part of `Address`; no new PII class.

## 8. Build order
1. Sub-project 1 (single-page redesign) — its own plan, branch, merge.
2. Sub-project 2 (geocoder address + map) — its own plan, branch, merge; layers onto the new address section.
