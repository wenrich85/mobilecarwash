# Handoff — Booking Flow Redesign

**Last updated:** 2026-06-20 (evening)
**Branch:** `main` (everything merged locally, **NOT pushed** — `main` is ~45 commits ahead of `origin/main`)

---

## TL;DR for the next agent

The customer booking flow has been progressively redesigned and is now a
**single, progressively-revealed scrolling page**. Phases 1–3 plus the
single-page rewrite (Sub-project 1) are **DONE and merged into local `main`
(not pushed)**. The one remaining planned piece is **Sub-project 2 — geocoder
address autocomplete + confirmation map** (designed, not built). Start there.

- **Current design spec (source of truth):** `docs/superpowers/specs/2026-06-20-booking-single-page-redesign-design.md` (covers both sub-projects; §4.3 is Sub-project 2)
- **Single-page plan (done):** `docs/superpowers/plans/2026-06-20-booking-single-page-redesign.md`
- **Sub-project 2:** no plan yet — write it with `writing-plans` from spec §4.3.
- Older specs/plans (`2026-06-19*`, the per-phase `2026-06-20-*vehicle*`/`*addons*`/`*size*`/`*type*` files) are the completed earlier phases.

---

## ⚠️ Repo / environment gotchas (read before doing anything)

1. **Not pushed.** `main` is ~45 commits ahead of `origin/main`, all intentionally local. Do **not** push unless the user asks.
2. **Three permanently-uncommitted working-tree files** — `config/dev.exs` (PORT 4010 override), `AGENTS.md`, `docs/customer-flows.html`. Established pattern: **stash them before a branch merge and pop after** (`git stash push -u -m "convention files" config/dev.exs AGENTS.md docs/customer-flows.html`). Never commit them.
3. **The project is on an EXTERNAL drive** (`/Volumes/mac_external`). It has disconnected mid-session before — if paths vanish, the drive unmounted; have the user reconnect it. Writes that don't flush before a disconnect can be lost (re-create from context).
4. **Subagents don't run `mix format`.** After a subagent task, `mix precommit`'s format step often leaves reflow-only changes uncommitted — commit them as a `style:` commit (this has bitten the merge step twice). Always run `mix precommit` and commit any format reflows BEFORE merging.
5. **Run the app:** `PORT=4010 mix phx.server` → http://localhost:4010 (port 4000 is the user's other project). After UI/CSS changes, the user may need a **hard refresh** (Cmd+Shift+R) — stale CSS caused several phantom "it's broken" reports.
6. **Runaway asset watchers:** orphaned `esbuild --watch`/`tailwind --watch` processes (from this + other projects) accumulated and starved CPU, causing stale CSS. They were cleaned up; if "recent classes aren't applying," check `ps aux | grep -E "esbuild|tailwind"` for old orphans and `mix assets.build`.
7. **Known benign test noise (NOT failures):** Ash "missed notifications" warnings; `Postgrex ... disconnected` under async. `test/mobile_car_wash/operations/photo_upload_test.exs` can fail under full-suite load (Ecto sandbox) but **passes in isolation** — re-run it alone to confirm.

---

## Process (how this work is run)

- **brainstorming → writing-plans → subagent-driven-development → finishing-a-development-branch.** Each piece: spec section → plan → fresh feature branch off `main` → task-by-task subagents (implement + two-stage review) → `mix precommit` → merge `--no-ff` locally → delete branch.
- **TDD mandatory.** Every task: failing test → implement → green. `mix precommit` (`compile --warnings-as-errors`, `deps.unlock --unused`, `format`, `test`) green before merge.
- **SDD ledger:** `.superpowers/sdd/progress.md` (git-ignored) tracks per-task completion across this whole session — trust it + `git log` after any compaction.
- **Mockable external clients** (pattern: `Notifications.TwilioClient`): server-side `Req`, swapped via `config :mobile_car_wash, :<name>_client` in `config/test.exs`. Tests never hit the network.

---

## What's DONE (all merged to local `main`)

### Phase 1 — Live price hero
`Billing.Pricing.breakdown/1` + `format_cents/1` + `subscription_discount_cents/3`; `PriceHeader` hero (animated total + tap-to-expand receipt); display==charge invariant across size + subscription/loyalty/referral.

### Phase 2 — Add-ons
`Scheduling.AddOn` (admin catalog, **no Stripe product** — dynamic `unit_amount`), `AppointmentAddOn` price-snapshot join, server-authoritative folding into `price_cents`, admin CRUD, seeds.

### Phase 3 — NHTSA vehicle step + enhancements
- `Vehicles.NhtsaClient` (mockable, VIN decode + makes/models, BodyClass→size), `Vehicles.NhtsaCache` (ETS TTL, **degrades gracefully if the table is absent**), `Vehicle` gained optional `vin`/`body_class`.
- Vehicle UI: Make→Year→Model dropdowns + typed-VIN autofill + color swatches + size.
- **Size auto-detect:** `models_for_make_year/2` returns size-tagged `[%{name,size}]` via NHTSA `vehicleType` buckets (car→:car, truck→:pickup, mpv→:suv_van); selecting a model auto-fills size.
- **Read-only vehicle type:** the manual size selector was removed — type is auto-detected, shown as a read-only badge, persisted via a hidden field. Async model loading (`start_async`/`handle_async` + `loading_models`).
- Fixes: VIN/make URL path-encoding; color swatches render via inline size/shape (CSP/cache-independent).

### Single-page redesign (Sub-project 1)
- `Booking.BookingSections` (pure): per-section status `:locked|:active|:complete` + `payable?/1`.
- `BookingLive` rewritten: one scrolling page, sticky price hero, sign-in at top, six sections (Service · Add-ons · Vehicle · Address · Schedule · Review & Pay) that unlock in order and stay freely editable. **Step wizard and photos removed from booking** (photo subsystem elsewhere untouched).
- **Guest checkout:** vehicle/address held as **unsaved in-memory structs**, persisted at Pay right after the guest customer is created (`ensure_customer/1` → `persist_pending_records/1`). Signed-in users persist immediately. Server-side `payable?` guard on `confirm_booking` (a crafted Pay event can't crash it).
- Stripe Checkout is now **globally mocked in tests** (`config/test.exs` `:stripe_checkout_module` → `StripeCheckoutSessionMock`), consistent with the other Stripe mocks.
- Price hero sticks at **`top-16`** (below the sticky navbar, `layouts.ex` `sticky top-0 z-50`).

---

## What's NEXT — Sub-project 2: geocoder address autocomplete + map

Fully designed in spec §4.3. The current address section is the **manual saved-list + form** (no autocomplete yet — this is the gap the user flagged as "address does not auto populate").

- **`MobileCarWash.Fleet.GeocoderClient`** (new, mockable via `config :mobile_car_wash, :geocoder_client`, server-side `Req`; mirror `NhtsaClient`): `suggest(query) :: {:ok, [%{label, street, city, state, zip, lat, lng}]} | {:error, term()}`. Default **US Census** (`geocoding.geo.census.gov`, free, no key, US-only); **Photon/OSM fallback** behind the same module. Add `Fleet.GeocoderClientMock` (ETS-backed) + wire in `config/test.exs`.
- **Address section rework:** debounced (`phx-change`, ~250ms) typeahead input → suggestions; on select → autofill street/city/state/zip, store `latitude`/`longitude` (columns already on `Address`), resolve zone via `MobileCarWash.Zones.zone_for_zip/1` (or `zone_for_coordinates/2`), drop a **Leaflet pin** via the existing `DispatchMap` hook (CSP already allows OSM/Carto/Stadia tiles). Keep manual entry + saved-address chips as fallback. Zone banner: `✓ In service area · <zone>` / `⚠ Outside our service area — we'll confirm or refund` (proceed allowed).
- Suggestion lookups should be async/non-blocking (consistent with the vehicle section's `start_async` model) + debounced.

### Other open / deferred items
- **Guest unsaved selections don't survive a LiveView reconnect** (`SessionCache` restores by DB id; an in-memory `id: nil` struct restores as nil). Acceptable for now; revisit if guests report losing vehicle/address on reconnect. (Sub-project 2 could store geocoded address attrs in the cache to help.)
- **"Price always visible" (OPEN):** the hero is sticky `top-16` (pins below the navbar when scrolling). The user asked for it to be "ALWAYS visible" and a clarifying question (sticky-is-fine vs fixed-top-bar vs fixed-bottom-bar) was interrupted — **confirm the desired treatment** before changing it again.
- Guest address shows no zone banner until Pay today (the in-memory struct gets zone-from-zip set in `save_address`, so it does show for guests now — verify after Sub-project 2 reworks the section).

---

## Key architecture facts (don't re-derive)

- **Pricing is server-authoritative.** LiveView sends only ids/selections; `Booking.create_booking/1` computes the charge. Stripe bills a **dynamic `unit_amount`** (no fixed price id), so anything affecting the total just needs to land in `price_cents`.
- **Single-page state:** `Booking.BookingSections.status/2` + `payable?/1` derive section gating from the context map (`build_context/1`: `selected_service`, `selected_add_ons`, `selected_vehicle`, `selected_address`, `selected_slot`, `current_customer`, `guest_form`). No more `StateMachine.transition` / `next_step` / `current_step` in `BookingLive`.
- **External calls** go server-side via `Req`, mockable via app config. `NhtsaClient`, (soon) `GeocoderClient`. Keeps CSP/`connect-src` unchanged.
- **Persistence:** `Booking.SessionCache` (DB-backed, keyed `booking_<csrf>`, restores by id).
- **Migrations:** Ash — `mix ash.codegen <name>` then `mix ecto.migrate` AND `MIX_ENV=test mix ecto.migrate`. Inspect generated migrations for stale unrelated DDL (snapshot drift has happened).

## Useful files
- Booking LiveView: `lib/mobile_car_wash_web/live/booking_live.ex` (single-page; read regions before editing).
- Section status: `lib/mobile_car_wash/booking/booking_sections.ex`
- Section wrapper component: `lib/mobile_car_wash_web/live/components/booking_components.ex` (`booking_section/1`)
- Price hero: `lib/mobile_car_wash_web/components/price_header.ex`
- NHTSA: `lib/mobile_car_wash/vehicles/nhtsa_client.ex` · `nhtsa_cache.ex` · mock `test/support/nhtsa_client_mock.ex`
- Booking orchestrator / pricing / zones: `lib/mobile_car_wash/scheduling/booking.ex` · `lib/mobile_car_wash/billing/pricing.ex` · `lib/mobile_car_wash/zones.ex`
- Vehicle/Address: `lib/mobile_car_wash/fleet/` · navbar: `lib/mobile_car_wash_web/components/layouts.ex`
- Seeds: `priv/repo/seeds.exs`
- Demo accounts: customer@demo.com / tech@demo.com / admin@mobilecarwash.com — all `Password123!`

## Test / run commands
- Focused: `MIX_ENV=test mix test path/to/test.exs`
- Full gate: `mix precommit`  (~5 min; last green: 1257 tests, 0 failures)
- Run app: `PORT=4010 mix phx.server`

## Suggested first moves for the next agent
1. Read the design spec (§4.3) and this handoff.
2. Confirm with the user: the "price always visible" treatment (open question) and whether to start Sub-project 2.
3. Use `writing-plans` for Sub-project 2 (GeocoderClient mockable-from-the-start), then `subagent-driven-development` on a fresh `feature/booking-geocoder-address` branch off `main`.
4. Build `GeocoderClient` + mock first (tests must not hit the network), then rework the address section (typeahead → autofill → zone → Leaflet pin).
