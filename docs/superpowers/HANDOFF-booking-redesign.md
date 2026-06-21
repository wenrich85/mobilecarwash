# Handoff — Booking Geocoder + Stripe Fixes

**Last updated:** 2026-06-21 (midday)
**Branches:** two unmerged feature branches off `main`; **nothing merged this session**, `main` untouched (still ~46 commits ahead of `origin/main`, intentionally **not pushed**).

---

## TL;DR for the next agent

Two independent work streams are complete-but-unmerged. The user said **"no"** to merging/precommit for now — do **not** merge or run the finish flow unless they ask.

1. **Geocoder address autocomplete (booking Sub-project 2)** — DONE on `feature/booking-geocoder-address`. Full SDD cycle + final review + a post-review service-area filter. Verified live in the booking UI.
2. **Stripe payment/subscription fixes** — DONE on `fix/stripe-payment-confirmation` (off `main`, split out from the geocoder branch). **Four pre-existing production bugs** found by live test-mode testing and fixed; all verified end-to-end against the Stripe sandbox.

Both branches are green (focused suites + `compile --warnings-as-errors`). Neither has had a **full `mix precommit`** run yet — do that before any merge.

---

## ⚠️ Repo / environment gotchas (read first)

1. **External drive.** Project lives on `/Volumes/mac_external`. It **unmounted mid-session** at least once — if paths vanish, the drive dropped; have the user reconnect, then continue. Commit often: unflushed writes can be lost on disconnect. (All work below is committed.)
2. **Three permanently-uncommitted convention files** — `config/dev.exs`, `AGENTS.md`, `docs/customer-flows.html`. Never commit them. Stash before a branch merge, pop after. **Note:** `config/dev.exs` currently carries **local Stripe test edits** (see Stripe setup below) — keep them.
3. **Not pushed.** `main` is ~46 ahead of `origin/main`, all intentionally local. Don't push unless asked.
4. **Run the app:** `PORT=4010 mix phx.server` → http://localhost:4010 (port 4000 is the user's other project). Hard-refresh (Cmd+Shift+R) after CSS/JS changes.
5. **Subagents don't run `mix format`** — commit format reflows as a `style:` commit before merging.
6. **Orphaned `esbuild`/`tailwind --watch`** processes accumulate and starve CPU → stale CSS. Check `ps aux | grep -E "esbuild|tailwind"` and kill stale ones (leave other projects' alone).
7. **Known benign test noise:** Ash "missed notifications" warnings; `Postgrex ... disconnected` under async; `photo_upload_test.exs` flakes under full-suite load but passes alone. A `stripity_stripe` `Stripe.Event.__struct__()` deprecation warning is from the dependency, not app code.

---

## Branch 1 — `feature/booking-geocoder-address` (geocoder, DONE, unmerged)

Off `main`. Commits (oldest→newest): `0a089a9` plan · `874ad53` GeocoderClient+mock+config · `14d949c` AddressMap hook + shared leaflet loader · `6f5af21` address typeahead/autofill/zone/map · `d1c2082` persist geocoded coords · `674818c` review-fix (signed-in save failure) · `2f15f20` **service-area hard filter + query bias**.

- **`MobileCarWash.Fleet.GeocoderClient`** (`lib/mobile_car_wash/fleet/geocoder_client.ex`) — mockable server-side `Req` client (mirror of `NhtsaClient`), US Census default + Photon/OSM fallback. Mock at `test/support/geocoder_client_mock.ex`, wired in `config/test.exs`. **Hard-filters suggestions to service-area ZIPs** (`Zones.serviced_zip?/1`) and biases queries to San Antonio (Census query + Photon bbox/latlng). `filter_to_service_area/1` and `census_query/1` are public + unit-tested.
- **Address section** rewritten in `lib/mobile_car_wash_web/live/booking_live.ex`: debounced (`phx-debounce=250`) typeahead → `start_async(:geocode_suggest)` → suggestions → select autofills street/city/state/zip + lat/lng, resolves zone **via `zone_for_zip` only** (nil = outside area; `zone_for_coordinates` would wrongly mark out-of-area in-area), drops a Leaflet pin via a new dedicated **`AddressMap`** hook (`assets/js/hooks/address_map.js`, shares `assets/js/hooks/leaflet_loader.js` with `DispatchMap`). Manual entry (`<details>`) + saved-address chips remain as fallback. Guest selections held in-memory and persisted at Pay (coords included).
- **Tests:** `test/mobile_car_wash/fleet/geocoder_client_test.exs`, additions in `test/mobile_car_wash_web/live/booking_single_page_test.exs`. Final whole-branch review passed (one fix applied: signed-in save-failure no longer moves the map pin). Minor follow-ups logged in the SDD ledger (loader `onerror`, etc.).
- Spec: `docs/superpowers/specs/2026-06-20-booking-single-page-redesign-design.md` §4.3. Plan: `docs/superpowers/plans/2026-06-20-booking-geocoder-address.md`.

---

## Branch 2 — `fix/stripe-payment-confirmation` (4 Stripe bugs, DONE, unmerged)

Off `main`. Commits: `40dd6c9` raw body · `234104d` payment Ash.read! · `f6607ee` gitignore `.env*.local` · `5671941` subscription create. **All four were pre-existing bugs that would break real payments/subscriptions in production** (Stripe charges, the app records nothing). Found by connecting the test-mode sandbox and exercising flows live.

1. **Webhook raw body** (`40dd6c9`) — `Plug.Parsers` consumed the body before the in-router `RawBody` plug re-read it → signature verified over empty bytes → **every webhook 400'd**. Fixed with a `Plug.Parsers :body_reader` (`lib/mobile_car_wash_web/plugs/cache_body_reader.ex`) that captures the raw body for `/webhooks/stripe`; deleted the dead `RawBody` plug; `endpoint.ex` + `router.ex` updated. Test: `test/mobile_car_wash_web/controllers/stripe_webhook_controller_test.exs`.
2. **Payment confirmation** (`234104d`) — `Booking.complete_payment/2` + `fail_payment/1` called `Ash.read!(Payment, action:, arguments:)`; `:arguments` is not a valid `Ash.read!` option → `Ash.Error.Unknown`. Fixed via `Ash.Query.for_read/3`. Test: `test/mobile_car_wash/scheduling/booking_payment_test.exs`.
3. **Subscription metadata access** (`5671941`) — `SubscriptionOrchestrator.create_from_checkout` used `get_in(session, [:metadata,...])` on a `%Stripe.Checkout.Session{}` struct (structs don't implement `Access`) → raised. Fixed with struct-field + map access.
4. **Subscription actorless authz** (`5671941`) — `find_and_link_customer` ran `Ash.read!`/`Ash.update` on `Customer` without `authorize?: false` → `Ash.Error.Forbidden` in the actorless webhook context. Fixed (Stripe is the trusted source). Test: `test/mobile_car_wash/billing/subscription_orchestrator_test.exs` (uses a real `Stripe.Checkout.Session` struct so a plain map can't mask it; seeds the 5 cash-flow accounts the test DB lacks).

**Verified end-to-end against the live sandbox:** one-time payment → appointment confirmed; subscription checkout → local `Subscription` created (Standard plan, `customer@demo.com`); lifecycle `customer.subscription.updated`/`deleted` mutate the local row; `checkout.session.expired` + invoice events route cleanly. Signature verification holds for all event types. `compile --warnings-as-errors` clean; billing suite 56/0.

---

## Local Stripe test-mode setup (how to reproduce)

- **Stripe CLI** installed via Homebrew (`stripe`, v1.42.x). The user ran `stripe login` (CLI is authenticated).
- **`.env.dev.local`** (gitignored via `.env*.local`) holds the user's **test-mode** `STRIPE_SECRET_KEY` (`sk_test_…`) and a `STRIPE_WEBHOOK_SECRET` captured from `stripe listen`.
- **`config/dev.exs`** (uncommitted convention file) was edited locally: `config :stripity_stripe, api_key: System.get_env("STRIPE_SECRET_KEY") || "sk_test_placeholder"` and `base_url` → `http://localhost:4010` (was 4000 — would misdirect the post-payment redirect). Keep these.
- **Run the server with keys:** `set -a; . ./.env.dev.local; set +a; PORT=4010 mix phx.server`.
- **Webhook forwarding:** `stripe listen --forward-to localhost:4010/webhooks/stripe` (prints the `whsec_`).
- **Catalog:** `mix backfill_stripe_catalog` populated test-mode Stripe product/price ids for the 2 ServiceTypes + 3 SubscriptionPlans (plans were `nil` before — subscription checkout would've failed).
- **`.env` (committed-ignored) holds LIVE keys** (`sk_live`/`pk_live`) — production secrets; never run dev/tests against them. `runtime.exs` is prod-gated and `raise`s if keys missing.
- **Test card:** `4242 4242 4242 4242`, any future expiry, any CVC, ZIP `78261`. Demo accounts: `customer@demo.com` / `tech@demo.com` / `admin@mobilecarwash.com` — all `Password123!`.
- **Production readiness (operational, not code):** confirm live keys valid; register the webhook in the Stripe dashboard → `https://<host>/webhooks/stripe` with matching `whsec`; do one live-mode smoke test.

---

## Currently running background processes

- `stripe listen` → task `bp67dn7n3` (forwarding to localhost:4010).
- Dev server on 4010 → task `b8c0y898u` (on the `fix/stripe-payment-confirmation` branch, with test keys loaded).
- Leave or stop as needed; nothing depends on them persisting.

---

## Open decisions / suggested next steps

1. **Finish the branches** (user deferred — only on request): for each, stash convention files → full `mix precommit` → merge `--no-ff` into local `main` → pop → delete branch. They're independent and touch different files, so order doesn't matter. The 4 Stripe fixes are production-critical — worth landing.
2. The geocoder branch's **Minor follow-ups** (loader `onerror`, etc.) are in the SDD ledger — triage before/after merge.
3. **"Price always visible"** booking question from a prior session is resolved ("price is gtg") — no action.
4. Local test data note: the demo customer's test subscription was set to `cancelled` locally via a lifecycle webhook test; the Stripe-side test subscription may still be active. Harmless.

## Useful files & commands
- Geocoder: `lib/mobile_car_wash/fleet/geocoder_client.ex` · `assets/js/hooks/address_map.js` · `lib/mobile_car_wash/zones.ex`
- Stripe: `lib/mobile_car_wash/billing/stripe_client.ex` · `lib/mobile_car_wash_web/controllers/stripe_webhook_controller.ex` · `lib/mobile_car_wash_web/plugs/cache_body_reader.ex` · `lib/mobile_car_wash/billing/subscription_orchestrator.ex` · `lib/mobile_car_wash/scheduling/booking.ex`
- SDD ledger (git-ignored, trust it + `git log` after compaction): `.superpowers/sdd/progress.md`
- Focused test: `MIX_ENV=test mix test path/to/test.exs` · Full gate: `mix precommit` (~5 min)
