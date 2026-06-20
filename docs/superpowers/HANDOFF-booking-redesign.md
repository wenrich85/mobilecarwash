# Handoff — Booking Flow Redesign

**Last updated:** 2026-06-20
**Author:** previous agent session
**Branch:** `main` (Phases 1 & 2 merged locally, **not pushed**)

---

## TL;DR for the next agent

The customer booking wizard is being redesigned in phases from a single
approved design spec. **Phases 1 (live price) and 2 (add-ons) are DONE and
merged into local `main`.** Phases 3 (NHTSA vehicle) and 4 (geocoder address)
are designed but **not yet planned or built**. Start with Phase 3.

- **Design spec (source of truth):** `docs/superpowers/specs/2026-06-19-booking-flow-redesign-design.md`
- **Phase 1 plan (done):** `docs/superpowers/plans/2026-06-19-booking-redesign-phase-1-pricing.md`
- **Phase 2 plan (done):** `docs/superpowers/plans/2026-06-20-booking-redesign-phase-2-addons.md`
- **Phase 3 & 4:** no plan yet — write them with the `writing-plans` skill (one per phase, after the prior lands, so each references real interfaces).

---

## ⚠️ Repo state you must know before doing anything

1. **`main` is ahead of `origin/main` by 11 commits and NOT pushed.** The user
   explicitly asked to merge locally without pushing (both phases). Do **not**
   push unless the user asks.
2. **Three uncommitted files in the working tree, intentionally left alone:**
   - `config/dev.exs` — a local `PORT` env override so the app can run on
     `:4010` alongside the user's other project on `:4000`. Keep it; do not
     commit. Run the app with `PORT=4010 mix phx.server`.
   - `AGENTS.md` — pre-existing local change from before this work.
   - `docs/customer-flows.html` — a standalone success/failure flow graph
     (deliverable from an earlier task), plus there's a friction heatmap in it.
   When finishing a branch, **stash these three before merging and pop after**
   (that's the established pattern this session used).
3. **The new design specs/plans live under `docs/superpowers/`.** Older
   `2026-04*`/`2026-05*` plans are unrelated prior work.

---

## How this work is being run (process)

- **brainstorming → writing-plans → subagent-driven-development → finishing-a-development-branch.** Each phase is its own spec section → plan → fresh feature branch off `main` → task-by-task subagents → final whole-branch review → merge.
- **TDD is mandatory** (repo convention + skill). Every task: failing test → implement → green.
- **`mix precommit`** (`compile --warnings-as-errors`, `deps.unlock --unused`, `format`, `test`) must be green before a phase is done.
- **Known benign noise in the suite:** Ash "missed notifications" warnings and occasional `Postgrex ... disconnected` lines under async — these are pre-existing and are NOT failures. If `precommit` shows a single failure, re-run `mix test --failed`; it's almost always that flake.
- **SDD ledger:** `.superpowers/sdd/progress.md` tracks per-task completion. It currently holds Phase 2's log. After compaction, trust the ledger + `git log` over memory. `.superpowers/` is git-ignored.
- **Migrations:** Ash — `mix ash.codegen <name>` then `mix ecto.migrate` AND `MIX_ENV=test mix ecto.migrate`. **GOTCHA:** `ash.codegen` previously bundled a *stale photos `alter table`* into a new migration (snapshot drift). Always inspect the generated migration and strip any unrelated DDL. The photos snapshot has since been reconciled, so it should not recur — but verify every codegen output.

---

## What's DONE

### Pre-work: booking sign-in dead-end (branch `fix/booking-signin-deadend`, merged in Phase 1)
- Returning customers could not sign in mid-booking (disabled "coming soon" stub) and guest checkout rejected known emails with no escape. Fixed: real `/book/sign-in` route stashing `return_to`, honored in `AuthController.success/4` (local-path-guarded); guest-collision now offers a sign-in CTA.
- Also fixed a latent crash: the custom `<.input>` component had `attr :value` with no default, crashing every booking step that omitted `value`. Now `default: nil`.

### Phase 1 — Live price (merge `7050502`)
- `MobileCarWash.Billing.Pricing.breakdown/1` (pure) + `format_cents/1` (integer-cents) + `subscription_discount_cents/3`.
- `MobileCarWashWeb.PriceHeader` hero component (big animated total + tap-to-expand itemized receipt) rendered on **every** booking step.
- `BookingLive` recomputes the breakdown on service/vehicle/loyalty/referral/subscription changes; review step + `confirm_booking` use the breakdown.
- **Display == charge invariant**: the hero reflects vehicle-size multiplier (car 1.0×/suv_van 1.2×/pickup 1.5×) AND subscription/loyalty/referral discounts. Server (`Booking`) and hero share `Pricing.subscription_discount_cents/3`.
- Count-up JS hook: `assets/js/hooks/price_count_up.js` (registered in `app.js`).
- Fixed a session-restore nil-breakdown crash (mount now computes the breakdown so a restored `:review` doesn't blow up).

### Phase 2 — Add-ons (merge `ddb249f`)
- `MobileCarWash.Scheduling.AddOn` resource (admin catalog: name, slug, description, price_cents, icon, active, sort_order). **No Stripe product** — see "Pricing model" below.
- `MobileCarWash.Scheduling.AppointmentAddOn` join with **price snapshot** at booking time; `Appointment has_many :appointment_add_ons`.
- `Pricing.addons_total_cents/1` + `addon_lines/1` (flat sum / line items).
- **Server-authoritative pricing:** `Booking.create_booking/1` accepts `add_on_ids`, folds the flat add-on total into `price_cents` **after** discounts and **before** `create_appointment` (so the `price_cents == 0` subscription-covered auto-confirm branch stays correct), and persists join rows in-transaction. `load_add_ons` filters `active == true` so deactivated add-ons are never charged.
- State machine: optional `:add_ons` step inserted **between `:select_service` and `:auth`** (`select_service → add_ons → auth → vehicle → address → photos → schedule → review → confirmed`).
- `BookingLive`: `:add_ons` step UI (toggle cards), hero reflects selections live, selection threaded through context/persist(`addon_ids`)/restore/`confirm_booking`.
- Admin add-ons CRUD in `lib/mobile_car_wash_web/live/admin/settings_live.ex`; seeds add a starter menu (Wax/Interior/Pet hair/Engine bay/Headlight).
- **Bonus bug fix:** `SubscriptionUsage` create rejected the non-public `subscription_id` (`create: :*` only accepts public attrs) → **any subscriber booking crashed**. Untested until Phase 2. Fixed via `force_change_attribute`, with a regression test.

---

## What's NEXT (not started)

Both are fully described in §4.4 / §4.5 and §6 of the design spec.

### Phase 3 — Vehicle step: dropdowns-first + VIN shortcut (NHTSA)
- Decided UX: **Make → Year → Model** dropdowns (NHTSA vPIC) as the primary path, with a **VIN decode shortcut** (📷 scan on mobile) pinned top; color swatches; **size auto-detected from NHTSA BodyClass** but editable. Saved-vehicle chips for returning customers.
- Architecture (spec §6a): `MobileCarWash.Vehicles.NhtsaClient` — server-side `Req` (no key, no CSP change), **mockable** via `config :mobile_car_wash, :nhtsa_client` (mirror `Notifications.TwilioClient`). VIN: `DecodeVinValues/{vin}`. Models: `GetModelsForMakeYear/make/{make}/modelyear/{year}` (note: keyed by make **and** year → that's why the dropdown order is Make→Year→Model). Curated ~40 popular makes seeded; cache makes/models (ETS or small table, ~30d TTL).
- Vehicle resource may gain optional `vin` + `body_class` (provenance); `size` stays the pricing driver. Map BodyClass → `:car | :suv_van | :pickup`.

### Phase 4 — Address step: autocomplete + confirmation map (free geocoder)
- Decided UX: single autocomplete field (debounced `phx-change`), suggestions stream from a **free server-proxied geocoder** (default **US Census** `geocoding.geo.census.gov`, Photon/OSM as fallback — swappable behind the module), on select auto-fills city/state/zip + drops a **Leaflet pin** (reuse the existing `DispatchMap` hook / CSP already allows OSM/Carto/Stadia tiles) + resolves the **service zone instantly** (reuse `MobileCarWash.Zones` zip map; `Address` already has `latitude`/`longitude` columns).
- Architecture (spec §6b): `MobileCarWash.Fleet.GeocoderClient` — server-side `Req`, mockable via `config :mobile_car_wash, :geocoder_client`.

### Later / deferred polish (from reviews — not blockers)
- Surface selected add-ons in the **review step + technician/admin appointment views** (they're persisted via `appointment_add_ons` but not yet displayed there).
- Render `add_on.icon` in the booking step (currently hardcoded `hero-sparkles`; the per-add-on icon field is decorative on the customer side) — or drop the field.
- `AddOn.price_cents` / `AppointmentAddOn.price_cents` have no `min: 0` constraint (admin-only; low risk).
- Full visual re-skin of all steps is in the approved scope ("full overhaul") — Phases 1–2 added the hero + add-ons; the broader re-skin/transitions can be its own phase.

---

## Key architecture facts (don't re-derive these)

- **Pricing is server-authoritative.** The LiveView never sends a trusted price — only ids (`add_on_ids`, `subscription_id`, `referral_code`, `loyalty_redeem`). `Booking.create_booking/1` computes the charge. Keep it that way for Phases 3/4.
- **Stripe charge is a DYNAMIC amount.** `StripeClient.create_checkout_session/3` and `create_mobile_payment_intent/2` bill `appointment.price_cents` via `price_data`/`unit_amount` — NOT a fixed `stripe_price_id`. That's why add-ons need no Stripe product. Anything that changes the total just needs to land in `price_cents`.
- **Discount stacking order (server == hero):** subscription discount (off base) → loyalty (zeroes the service remainder) OR referral (capped at the post-subscription service price) → **then** add-ons added flat on top. The single source for subscription discount is `Pricing.subscription_discount_cents/3`. If you touch pricing, preserve `display == charge` and add a test across {none, subscription, loyalty, referral} × add-ons (a Phase 1 review caught a real subscription divergence here).
- **External calls go server-side via `Req`, mockable via app config.** Pattern: `lib/mobile_car_wash/notifications/twilio_client.ex`. This keeps CSP/`connect-src` unchanged and tests offline. Use it for NHTSA + geocoder.
- **Booking state:** pure `MobileCarWash.Booking.StateMachine` (steps, guards, skip-auth-when-signed-in). `BookingLive` persists/restores via `MobileCarWash.Booking.SessionCache` (DB-backed, keyed on `booking_<csrf>`, 2h TTL). When you add a step, edit `@steps`, `raw_next/prev`, `can_be_on?`, `validate_forward_guard`, and any `maybe_skip`.
- **Catalog live-reload:** `MobileCarWash.CatalogBroadcaster` (services/plans/add_ons updated → `BookingLive` `handle_info` reloads).

## Useful files
- Booking LiveView: `lib/mobile_car_wash_web/live/booking_live.ex` (~1450 lines — read regions before editing; it's been the subject of careful work).
- Booking orchestrator: `lib/mobile_car_wash/scheduling/booking.ex`
- Pricing (pure): `lib/mobile_car_wash/billing/pricing.ex`
- State machine: `lib/mobile_car_wash/booking/state_machine.ex`
- Admin settings (catalog CRUD pattern): `lib/mobile_car_wash_web/live/admin/settings_live.ex`
- Zones: `lib/mobile_car_wash/zones.ex` · Vehicle/Address: `lib/mobile_car_wash/fleet/`
- Seeds: `priv/repo/seeds.exs`
- Demo accounts (README): customer@demo.com / tech@demo.com / admin@mobilecarwash.com — all `Password123!`

## Test/run commands
- Focused: `MIX_ENV=test mix test path/to/test.exs`
- Full gate: `mix precommit`
- Run app: `PORT=4010 mix phx.server` → http://localhost:4010 (port 4000 is the user's other project)

---

## Suggested first moves for the next agent
1. Read the design spec (§4.4–4.5, §6) and this handoff.
2. Confirm with the user: push the 11 unpushed `main` commits now, or keep local? Start Phase 3 (vehicle) or Phase 4 (address) first? (Spec build order is 3 then 4.)
3. Use `writing-plans` to author the Phase 3 plan, then `subagent-driven-development` to execute on a fresh `feature/booking-vehicle-nhtsa` branch off `main`.
4. Build the `NhtsaClient` mockable from the start (tests must not hit the network).
