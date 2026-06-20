# Design Spec — Read-only vehicle type + model-loading state

**Date:** 2026-06-20
**Status:** Approved
**Builds on:** `docs/superpowers/specs/2026-06-20-vehicle-size-autodetect-design.md` (size auto-detect) and the Phase 3 NHTSA vehicle step.

---

## 1. Goal & non-goals

**Goals:**
1. The customer can **no longer manually choose** the vehicle type/size. Size is always auto-detected (from the VIN decode or the selected model) and shown **read-only**.
2. The vehicle step shows a **loading state** while it waits for the NHTSA model list (and the VIN decode), instead of appearing frozen/empty.

**Non-goals:**
- No change to the pricing model — `size` remains the single pricing driver; this only removes the manual control and persists the auto-detected value.
- No change to the VIN-decode or model-size-detection logic itself (already built).
- No camera/OCR VIN scanning.

## 2. Behavior

### 2a. Read-only vehicle type
- The three size radio buttons are removed.
- `size` stays in `vehicle_form` (auto-set from VIN decode or model selection) and is submitted via a **hidden** `vehicle[size]` input, so `save_vehicle` and pricing are unchanged.
- A **read-only badge** displays the detected type and its price modifier:
  - `:car` → `🚗 Car · +0`
  - `:suv_van` → `🚙 SUV / Van · +20%`
  - `:pickup` → `🚛 Pickup · +50%`
- The badge shows only once a type has been detected — i.e. a model is selected (`vehicle_form["model"] != ""`) **or** a VIN was decoded (`vehicle_form["vin"] != ""`). Before that, a muted hint reads: "Pick your model and we'll detect the type."
- There is no override control by design.

### 2b. Loading state (async model fetch)
- The model lookup (`NhtsaClient.models_for_make_year/2`, now 3 sequential NHTSA calls on a cold cache) runs **asynchronously** so the step stays responsive.
- New assign `loading_models` (boolean, default `false`).
- On a make+year change (both present): set `loading_models: true`, clear `vehicle_models`, reset `vehicle_form["model"]` to `""`, reply immediately; then `start_async` the fetch.
- `handle_async`:
  - `{:ok, {:ok, models}}` → `vehicle_models: models, loading_models: false`
  - `{:ok, {:error, _}}` or `{:exit, _}` → `vehicle_models: [], loading_models: false` (manual fallback / retry still possible; never blocks)
- The model `<select>` is disabled and shows a spinner / "Loading models…" while `loading_models` is `true`.
- The VIN autofill submit button uses `phx-disable-with="Decoding…"` (built-in) for its (single, faster) call.

## 3. Component design

### `MobileCarWashWeb.BookingLive` (`:vehicle` step) — the only file changed
- **Template:**
  - Remove the size radio group; add `<input type="hidden" name="vehicle[size]" value={@vehicle_form["size"]} />`.
  - Add the read-only type badge (shown when model or vin present) + the muted hint otherwise, driven by a `size_badge/1` helper returning `%{label, icon, modifier}` (or a tuple) for the current `vehicle_form["size"]`.
  - Model `<select>`: disabled and showing a loading indicator when `@loading_models`.
  - VIN submit button: add `phx-disable-with="Decoding…"`.
- **`vehicle_form_change`:** on make/year change, set `loading_models: true`, clear models, reset model, and `start_async(:load_models, fn -> NhtsaClient.models_for_make_year(make, year) end)`. The existing auto-fill-size-on-model-select branch is unchanged (models are already in assigns by then). The `vin_error` clear stays.
- **`handle_async(:load_models, …)`:** as in §2b.
- **Helper `size_badge/1`** (private, pure): `"car" -> {…}`, `"suv_van" -> {…}`, `"pickup" -> {…}`.

No changes to `NhtsaClient`, the state machine, pricing, `save_vehicle`'s logic (it already reads `vehicle[size]`), or the VIN-decode handler's core behavior.

## 4. Testing strategy
- **Read-only type:** after selecting a model tagged `:pickup`, the page shows the Pickup badge (label + `+50%`) and contains **no** `name="vehicle[size]"` radio input; saving still persists `size: :pickup` (hidden field submits). Same for `:suv_van`. Before any selection, the hint shows and no badge.
- **No manual override:** there is no size radio/button to click (assert absence of the radio inputs).
- **Loading state:** on make+year change, `loading_models` is set and the model field renders the loading indicator (assert the "Loading models…" text / disabled state) before the async result; after `handle_async` success, models render and the indicator is gone.
- **Async degradation:** an async error/exit clears the flag and leaves an empty model list without crashing.
- TDD per repo convention; `mix precommit` green before merge. Tests must not hit the network (mock the client; `start_async` runs the mocked call).

## 5. Error handling & fallbacks
- Model fetch async error/exit → empty list, `loading_models` cleared, manual hint; the customer can re-pick make/year to retry.
- Size that can't be detected defaults to `:car` (accepted: no manual override by design).
- All existing NHTSA/cache resilience (graceful cache, fallback bucket) unchanged.

## 6. Security & privacy
- Unchanged: all calls server-side via `Req`, no client keys, CSP unchanged.
