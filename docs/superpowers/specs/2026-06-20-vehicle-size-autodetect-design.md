# Design Spec — Auto-detect vehicle size on the dropdown path

**Date:** 2026-06-20
**Status:** Approved
**Builds on:** Phase 3 (NHTSA vehicle step) — `docs/superpowers/plans/2026-06-20-booking-redesign-phase-3-vehicle-nhtsa.md`

---

## 1. Goal & non-goals

**Goal:** The booking wizard's vehicle **type/size** (`:car` / `:suv_van` / `:pickup`) should auto-populate on **both** entry paths — the typed-VIN shortcut (already does) **and** the Make→Year→Model dropdowns (currently does not). It must remain user-editable on both paths.

**Non-goals:**
- No camera/OCR VIN scanning (still out of scope).
- No change to the pricing model — `size` remains the single pricing driver; this only changes how `size` is *pre-filled*.
- No change to the VIN decode path's behavior (it already auto-sets size from BodyClass).

## 2. Why this needs a data source

The NHTSA `GetModelsForMakeYear` endpoint returns model **names only** — no body class. So size cannot be derived from the model name alone. NHTSA's `vehicleType` path filter (`/GetModelsForMakeYear/make/{make}/modelyear/{year}/vehicleType/{type}`) returns the models for a make+year that belong to a given vehicle type. Verified live:

- BMW 2025 → `car`: 27 (sedans), `truck`: 0, `mpv`: 9 (X1–X6 SUVs)
- Ford 2023 → `car`: 8, `truck`: 10 (F-150…), `mpv`: 11 (Bronco, Edge, Escape…)

Mapping: `car → :car`, `truck → :pickup`, `mpv → :suv_van` (MPV covers SUVs, vans, minivans).

## 3. Approach (chosen)

**NHTSA vehicleType buckets.** When models load for a make+year, query the three vehicle types (`car`, `truck`, `mpv`), tag each returned model with its mapped size, and merge into one sorted list of `%{name, size}`. Selecting a model sets the size from that tag. Cached 30 days, so the extra calls amortize to ~zero.

Rejected alternatives:
- **Model-name heuristic** (keyword map): no extra calls but inaccurate, brittle, large maintenance surface, silently wrong on unknown models.
- **Leave dropdown size manual:** that is the behavior being changed.

## 4. Component design

### 4a. `MobileCarWash.Vehicles.NhtsaClient`
- **`vehicle_type_to_size/1`** (new, pure): `"car" → :car`, `"truck" → :pickup`, `"mpv" → :suv_van`. Case-insensitive on the NHTSA `VehicleTypeName`/filter token.
- **`models_for_make_year/2`** (changed return shape): now returns `{:ok, [%{name: String.t(), size: :car | :suv_van | :pickup}]}` (sorted by `name`, deduped by name) or `{:error, reason}`.
  - Real path: issue three typed requests (`vehicleType` = `car`, `truck`, `mpv`). Tag each model with the type's size. Merge; on a name collision across buckets, precedence is **`:pickup` > `:suv_van` > `:car`** (bias to the larger/pricier classification).
  - **Fallback:** if every typed request fails/errors, fall back to the existing untyped `GetModelsForMakeYear` (names only) and tag each with `size: :car`, so the dropdown still works (never blocks).
  - **Cache:** the merged enriched list is cached in `NhtsaCache` keyed `{:models, downcased_make, year_string}` (same key, new value shape). Cache hit short-circuits before any HTTP call.
- **`body_class_to_size/1`** and the VIN decode path are **unchanged**.

### 4b. `MobileCarWashWeb.BookingLive` (`:vehicle` step)
- The model `<select>` options render from the enriched list's `.name`.
- **`vehicle_form_change`:** when the selected model changes to a non-empty model, set `vehicle_form["size"]` from the matching `%{name, size}` entry in the loaded list. Size stays editable — the size radio buttons remain and a later user click overrides it.
- Make/year change still resets the model and reloads the enriched list (existing behavior).
- **VIN decode path:** unchanged auto-set; the decoded model (which may not be in the list) is prepended as `%{name: decoded.model, size: decoded.size}` so it is selectable and consistent with the list shape.

### 4c. `MobileCarWash.Vehicles.NhtsaClientMock` (test)
- `put_models(make, year, models)` accepts the enriched shape (`[%{name, size}]`).
- `models_for_make_year/2` returns `{:ok, enriched_list}` or `{:ok, []}` on miss.

## 5. Testing strategy
- **Client unit:** `vehicle_type_to_size/1` mapping (all three + unknown→:car); `models_for_make_year/2` returns the enriched shape via the mock; (the multi-bucket merge/precedence and live HTTP remain mock-bypassed in tests, consistent with Phase 3 — note the gap, don't fake a network call).
- **LiveView:** selecting a model tagged `:pickup` sets the size to pickup (and `:suv_van` likewise); the size remains overridable (click a different size after auto-set, value sticks); VIN path still auto-sets; make-change still resets model.
- TDD per repo convention; `mix precommit` green before merge.

## 6. Error handling & fallbacks
- All typed calls fail → untyped names-only fallback, size `:car` (manual selection still available).
- Cache absent (e.g. GenServer down) → live calls run uncached (graceful-degradation fix already in `NhtsaCache`).
- Unknown/empty model selection → size left at its current value; never crash.

## 7. Security & privacy
- Unchanged from Phase 3: all calls server-side via `Req`, no client keys, CSP unchanged, no new PII.
