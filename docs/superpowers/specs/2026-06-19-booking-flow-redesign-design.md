# Booking Flow Redesign — Design Spec

**Date:** 2026-06-19
**Status:** Draft for review
**Goal:** Reduce booking friction with a full visual overhaul of the customer
booking wizard, anchored by a prominent live price that builds from the
service's base price, plus smart auto-fill for vehicle (NHTSA) and address
(free geocoder).

---

## 1. Goals & non-goals

**Goals**
- Show the price prominently and immediately, building it up live as the
  customer picks a larger vehicle or adds services.
- Slash the two highest-friction steps (vehicle, address) with auto-fill.
- Introduce à-la-carte **add-ons** so customers can grow their package.
- Re-skin every step into a cohesive, mobile-first, premium experience.

**Non-goals**
- No payment-provider changes (Stripe checkout unchanged).
- No change to scheduling/availability logic (restyle only).
- No new auth system (sign-in dead-end already fixed separately).

---

## 2. Redesigned flow

Current order: `select_service → auth → vehicle → address → photos → schedule → review → confirmed`

New order (one new step, **`add_ons`**, after service):

```
service → add_ons → auth → vehicle → address → photos → schedule → review → confirmed
```

- `add_ons` is **optional** (forward guard always passes; default = none).
- `auth` still auto-skips for signed-in customers (unchanged).
- The price is live from `service` onward and visibly grows at `add_ons`
  (extras) and `vehicle` (size multiplier).

---

## 3. Visual system (applies to every step)

- **Shell:** stepper, one focused step per screen, mobile-first; sticky
  bottom **Continue** bar.
- **Hero price header (treatment 1):** a large animated total pinned to the
  top of every step. On change it briefly flashes a delta (e.g. `▲ +$10 SUV`).
  Tapping it expands an **itemized receipt** (base, size, each add-on,
  discounts, total).
- **Progress:** numbered step dots with completed/active/upcoming states.
- **Cards & micro-interactions:** card-based selections, toggles for add-ons,
  swatches for color, smooth step transitions and number count-up animation.
- The hero header and receipt are a single reusable component fed by the
  pricing engine (§6c), shared across all steps.

---

## 4. Step-by-step design

### 4.1 Service
Single-select service cards (today's `ServiceType`). Selecting sets the base
price; the hero shows it immediately (e.g. `$50.00`).

### 4.2 Add-ons (NEW)
Toggle cards from the admin-managed `AddOn` menu (icon, name, `+$price`).
Each toggle adds a receipt line and flashes the hero delta. Fully optional.
Starter menu (editable in admin): Wax & shine +$15, Interior shampoo +$25,
Pet hair removal +$10, Engine bay clean +$20, Headlight restore +$30.

### 4.3 Auth
Unchanged behavior (guest checkout + working sign-in link, already fixed).
Restyled to match the new shell.

### 4.4 Vehicle — **dropdowns-first + VIN shortcut**
- Saved-vehicle chips for returning customers (one tap to reuse).
- **VIN shortcut** pinned top-right ("⚡ Autofill from VIN", with 📷 scan on
  mobile via the device camera/file input). Decoding fills make/model/year and
  infers size.
- **Manual path (primary):** `Make ▾` (popular makes first) → `Year ▾` →
  `Model ▾`, sourced from NHTSA (§6a). Year precedes model because NHTSA's
  model list is keyed by make **and** year; the UI orders fields to match.
- **Color:** tappable swatches (maps to the existing free-text `color`).
- **Size:** three buttons (Car +0 / SUV·Van +20% / Pickup +50%) with live $
  impact; auto-selected from the decoded NHTSA body class, always editable.

### 4.5 Address — **autocomplete + confirmation map**
- Saved-address chips for returning customers.
- Single autocomplete field; suggestions stream as the user types (debounced
  `phx-change`, server-proxied geocoder, §6b).
- On select: auto-fill city/state/zip, drop a **Leaflet pin** (existing map
  infra) for confirmation, and resolve the **service zone** instantly
  (existing `Zones` zip map, refined by the geocoded result). Store
  `latitude`/`longitude` (columns already exist on `Address`).
- Zone feedback: `✓ In service area · Northwest zone` or
  `⚠ Outside our service area — we'll confirm or refund` (proceed allowed).

### 4.6 Photos / 4.7 Schedule / 4.8 Review
Restyled to the new shell; behavior unchanged. Review shows the full itemized
receipt (now including add-ons) before pay.

---

## 5. Data model changes

- **`AddOn` resource** (new, admin-managed, mirrors `ServiceType`):
  `name, slug, price_cents, active, icon, sort_order`. CRUD in admin.
- **Appointment ↔ AddOns:** join table `appointment_add_ons` (many-to-many),
  capturing the price per add-on at booking time (price snapshot for history).
- **Appointment pricing:** persist a breakdown — `base_price_cents`,
  `size_multiplier`/`sized_price_cents`, `addons_total_cents`,
  `discount_cents`, `total_cents` — so receipts/refunds are reconstructable.
- **Vehicle:** add optional `vin` (string) and `body_class` (string, from
  NHTSA) for provenance; `size` stays the pricing driver.
- **Address:** no schema change — `latitude`/`longitude`/`zone` already exist.

---

## 6. Smart-fill architecture

All external calls are **server-side via `Req`**, mirroring the existing
mockable client pattern (`Notifications.TwilioClient`) — so `connect-src`/CSP
is unchanged and there are no client-side keys.

### 6a. NHTSA vPIC client — `MobileCarWash.Vehicles.NhtsaClient`
- Free, no API key. Base: `https://vpic.nhtsa.dot.gov/api/vehicles/`.
- **VIN decode:** `DecodeVinValues/{vin}?format=json` → make, model, model
  year, body class → map body class → `:car | :suv_van | :pickup`.
- **Models:** `GetModelsForMakeYear/make/{make}/modelyear/{year}?format=json`.
- **Makes:** curated list of ~40 popular makes (seeded constant) shown first;
  full `GetAllMakes` available as a "more" fallback.
- **Caching:** cache makes/models responses (ETS or a small DB table, TTL ~30
  days) to keep dropdowns instant and limit external calls.
- Mockable via `config :mobile_car_wash, :nhtsa_client`.

### 6b. Geocoding client — `MobileCarWash.Fleet.GeocoderClient`
- Free, no key, server-proxied. Provider: **US Census Geocoder**
  (`geocoding.geo.census.gov`, `onelineaddress`) as primary; Photon/OSM as a
  documented fallback. (Provider is swappable behind this module.)
- **Autocomplete:** LiveView debounced `phx-change` → client → ranked
  suggestions (formatted line + components + lat/lng).
- **On select:** returns components + lat/lng; we fill the address, store
  coords, and compute zone (zip → `Zones`, refined by coords if needed).
- Mockable via `config :mobile_car_wash, :geocoder_client`.

### 6c. Live pricing engine — extend `MobileCarWash.Billing.Pricing`
Pure functions; single source of truth for the hero number, the receipt, and
the persisted appointment total.

```
sized_service = round(base_price_cents * size_multiplier)   # 1.0 / 1.2 / 1.5
addons_total  = Σ selected add-on price_cents               # flat, not size-scaled
subtotal      = sized_service + addons_total
discount      = subscription + loyalty + referral            # as today, on service portion
total         = max(subtotal - discount, 0)
```
Returns a structured breakdown `{base, size, addons:[...], discount, total}`
that the hero/receipt renders directly. `$0` totals (loyalty/subscription)
still skip Stripe (existing behavior).

---

## 7. State machine changes

`MobileCarWash.Booking.StateMachine`:
- Insert `:add_ons` between `:service` and `:auth` in `@steps`, `raw_next`,
  `raw_prev`.
- `:add_ons` forward guard always passes (optional). `can_be_on?(:add_ons)`
  requires a selected service.
- `selected_add_ons` (list, default `[]`) added to the context map and to
  `SessionCache` persistence so it survives reconnect/sign-in round-trips.

---

## 8. Component boundaries (isolation)

| Unit | Responsibility | Depends on |
|------|----------------|-----------|
| `NhtsaClient` | VIN decode + makes/models, cached | Req, cache |
| `GeocoderClient` | address suggestions + coords | Req |
| `Pricing` (extended) | pure totals + breakdown | — |
| `AddOn` resource | admin-managed add-on menu | Ash |
| Hero-price/receipt component | render live total + breakdown | Pricing |
| Per-step LiveView components | each step's UI + events | clients, Pricing |

Each is independently testable with the others mocked/stubbed.

---

## 9. Error handling & fallbacks

- **NHTSA down / VIN invalid:** dropdowns and manual entry always work; VIN
  errors show "couldn't read that VIN — enter manually" and never block.
- **Geocoder down / no matches:** fall back to manual street/city/state/zip
  entry (today's fields) with zip→zone still computed.
- **Outside service zone:** warn but allow (admin confirms/refunds) — today's
  behavior, made explicit in the UI.
- **Cache miss / slow API:** show a lightweight loading state on dropdowns;
  never block the sticky Continue for optional data.

---

## 10. Testing strategy

- **Pricing:** pure unit tests across size × add-ons × discounts, incl. `$0`.
- **NhtsaClient / GeocoderClient:** unit tests against recorded fixtures via
  the mock config; no live network in tests.
- **StateMachine:** `:add_ons` insertion, optional skip, context persistence.
- **LiveView:** each redesigned step (incl. the previously-crashing render
  paths), VIN-decode autofill, address-select autofill + zone, add-on toggles
  updating the hero, full guest happy-path to review.
- TDD per repo convention; `mix precommit` green before merge.

---

## 11. Security & privacy

- All third-party calls are server-side; no client keys; CSP unchanged.
- VIN stored only when provided; treated as vehicle metadata.
- Geocoded coordinates already part of the `Address` model; no new PII class.
- Map tiles already allowlisted in CSP (OSM/Carto/Stadia).

---

## 12. Phasing (suggested build order)

1. **Pricing engine + hero-price component** (foundation; visible value).
2. **AddOn resource + admin CRUD + add-ons step** (price build-up).
3. **NHTSA vehicle step** (VIN + dropdowns + swatches + auto-size).
4. **Geocoder address step** (autocomplete + map + zone).
5. **Full re-skin of remaining steps** + transitions/polish.

Each phase ships independently behind the same flow and is separately testable.

---

## 13. Open questions

- Add-ons are flat-priced (not size-scaled) — confirm that's desired.
- Census Geocoder vs Photon as the default provider (both free; Census is
  US-only which is fine for SA). Defaulting to Census; swappable.
