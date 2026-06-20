# Read-only Vehicle Type + Model-loading State Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the customer's ability to pick the vehicle type (show the auto-detected type read-only) and show a loading state while the NHTSA model list is being fetched.

**Architecture:** Both changes live in the booking LiveView's `:vehicle` step. The size radios are replaced by a read-only badge fed by a `size_badge/1` helper; `size` is still carried in `vehicle_form` (auto-set from VIN/model) and submitted via a hidden input. The model fetch becomes asynchronous via LiveView `start_async`/`handle_async` with a `loading_models` flag driving a spinner; the VIN button uses the built-in `phx-disable-with`.

**Tech Stack:** Phoenix LiveView (`start_async`/`handle_async`, `render_async`), Tailwind/daisyUI.

## Global Constraints

- **TDD mandatory:** failing tests → implement → green. Capture RED/GREEN evidence.
- **`mix precommit` green** before done (`compile --warnings-as-errors`, `deps.unlock --unused`, `format`, `test`). Benign noise (NOT failures): Ash "missed notifications" warnings; occasional `Postgrex ... disconnected`.
- **Pricing stays server-authoritative:** `size` remains the single pricing driver; it is auto-detected only, persisted via the hidden `vehicle[size]` field. `save_vehicle` and pricing logic are unchanged.
- **No manual vehicle-type control** by design — there must be NO size radio/button after this change. The auto-detected type is shown read-only.
- **Type display:** read-only badge per size — `:car` → `🚗 Car · +0`, `:suv_van` → `🚙 SUV / Van · +20%`, `:pickup` → `🚛 Pickup · +50%`. Shown only when `vehicle_form["model"] != ""` or `vehicle_form["vin"] != ""`; otherwise a muted hint "Pick your model and we'll detect the type."
- **Loading:** model fetch is async; while waiting, the model `<select>` is disabled and shows "Loading models…". Async error/exit → empty list + flag cleared (never blocks). VIN button uses `phx-disable-with="Decoding…"`.
- **Tests never hit the network** (mock already wired); use `render_async/1` to await the async fetch.
- Do NOT push. Do NOT touch `config/dev.exs`, `AGENTS.md`, `docs/customer-flows.html`. Do NOT modify the state machine, pricing, or `save_vehicle` logic.

---

## File structure

| File | Responsibility |
|------|----------------|
| `lib/mobile_car_wash_web/live/booking_live.ex` (modify) | mount assign `loading_models`; template (remove size radios, add hidden size + read-only badge + hint, model-select loading UI, VIN `phx-disable-with`); `size_badge/1` helper; `vehicle_form_change` → async; `handle_async(:load_models, …)` |
| `test/mobile_car_wash_web/live/booking_vehicle_step_test.exs` (modify) | update model-load + VIN + auto-detect tests for badge/async; remove the obsolete "user-editable" test; add badge-hint, no-radio, loading, and async-error tests |

This is a single cohesive task: both behaviors rewrite the same handler, template region, and tests.

---

## Task 1: Read-only vehicle type + async model-loading state

**Files:**
- Modify: `lib/mobile_car_wash_web/live/booking_live.ex`
- Test: `test/mobile_car_wash_web/live/booking_vehicle_step_test.exs`

**Interfaces:**
- Consumes: `NhtsaClient.models_for_make_year/2 :: {:ok, [%{name, size}]} | {:error, term()}` (unchanged); `NhtsaClientMock.put_models/3` (enriched shape, unchanged).
- Produces: assign `loading_models :: boolean()`; private `size_badge(size_string) :: %{icon: String.t(), label: String.t(), modifier: String.t()}`; `handle_async(:load_models, …)` callback. The `:vehicle` step no longer renders any `type="radio" name="vehicle[size]"` input; size is submitted via `<input type="hidden" name="vehicle[size]">`.

> **Implementer note:** read the named regions in `booking_live.ex` before editing (~1500 lines). Do not disturb other steps, the state machine, pricing, or `save_vehicle`.

- [ ] **Step 1: Update the tests (RED)**

In `test/mobile_car_wash_web/live/booking_vehicle_step_test.exs`:

(1a) **Update** the "choosing make + year loads models" test to await the async fetch. Replace its two `render_change(...)` blocks so each make/year change is followed by `render_async/1`:

```elixir
    render_change(view, "vehicle_form_change", %{
      "vehicle" => %{"make" => "Toyota", "year" => "2021", "model" => "", "color" => ""}
    })

    html = render_async(view)
    assert html =~ "Camry"
    assert html =~ "RAV4"

    render_change(view, "vehicle_form_change", %{
      "vehicle" => %{"make" => "Honda", "year" => "2021", "model" => "", "color" => ""}
    })

    html = render_async(view)
    assert html =~ "Accord"
    assert html =~ "Civic"
```

(1b) **Replace** the "VIN autofill populates the form and auto-selects size from body class" assertion that checked a radio. Change the final assertion from the `~r/name="vehicle\[size\]" value="car"[^>]*checked/` regex to assert the read-only badge:

```elixir
    # Read-only badge shows the detected type (no radio to check anymore)
    assert html =~ "Car"
    refute html =~ ~s(type="radio" name="vehicle[size]")
```

(1c) **Replace** the "selecting a model auto-fills the size from its NHTSA vehicle type" test body so it awaits async and asserts the badge instead of a radio:

```elixir
  test "selecting a model shows the auto-detected type read-only", %{conn: conn} do
    NhtsaClientMock.put_models("Ford", 2023, [
      %{name: "F-150", size: :pickup},
      %{name: "Focus", size: :car},
      %{name: "Escape", size: :suv_van}
    ])

    {:ok, view, _} = live(conn, "/book")
    to_vehicle_step(view)

    render_change(view, "vehicle_form_change", %{
      "vehicle" => %{"make" => "Ford", "year" => "2023", "model" => "", "color" => ""}
    })

    render_async(view)

    # Pick a pickup → badge shows Pickup +50%
    html =
      render_change(view, "vehicle_form_change", %{
        "vehicle" => %{"make" => "Ford", "year" => "2023", "model" => "F-150", "color" => ""}
      })

    assert html =~ "Pickup"
    assert html =~ "+50%"
    refute html =~ ~s(type="radio" name="vehicle[size]")

    # Pick an SUV → badge shows SUV / Van +20%
    html =
      render_change(view, "vehicle_form_change", %{
        "vehicle" => %{"make" => "Ford", "year" => "2023", "model" => "Escape", "color" => ""}
      })

    assert html =~ "SUV / Van"
    assert html =~ "+20%"
  end
```

(1d) **Delete** the entire "an auto-filled size remains user-editable" test — manual override no longer exists by design.

(1e) **Add** these new tests before the final `end` of the module:

```elixir
  test "before a model or VIN is chosen, a hint shows and no type badge", %{conn: conn} do
    {:ok, view, _} = live(conn, "/book")
    html = to_vehicle_step(view)

    assert html =~ "Pick your model and we&#39;ll detect the type"
    refute html =~ ~s(type="radio" name="vehicle[size]")
  end

  test "the model field shows a loading state while the fetch is in flight", %{conn: conn} do
    NhtsaClientMock.put_models("Toyota", 2021, [%{name: "Camry", size: :car}])

    {:ok, view, _} = live(conn, "/book")
    to_vehicle_step(view)

    # The change handler sets loading before the async result arrives
    html =
      render_change(view, "vehicle_form_change", %{
        "vehicle" => %{"make" => "Toyota", "year" => "2021", "model" => "", "color" => ""}
      })

    assert html =~ "Loading models"

    # After the async fetch completes, models render and loading clears
    html = render_async(view)
    assert html =~ "Camry"
    refute html =~ "Loading models"
  end

  test "saving still persists the auto-detected size via the hidden field", %{conn: conn, customer: customer} do
    NhtsaClientMock.put_models("Ford", 2023, [%{name: "F-150", size: :pickup}])

    {:ok, view, _} = live(conn, "/book")
    to_vehicle_step(view)

    render_change(view, "vehicle_form_change", %{
      "vehicle" => %{"make" => "Ford", "year" => "2023", "model" => "", "color" => ""}
    })

    render_async(view)

    # Select the pickup model → size auto-detected to pickup in form state
    render_change(view, "vehicle_form_change", %{
      "vehicle" => %{"make" => "Ford", "year" => "2023", "model" => "F-150", "color" => "Silver"}
    })

    # Submit only the fields the form now carries (size flows via the hidden input)
    render_submit(view, "save_vehicle", %{
      "vehicle" => %{
        "make" => "Ford",
        "model" => "F-150",
        "year" => "2023",
        "color" => "Silver",
        "size" => "pickup",
        "vin" => "",
        "body_class" => ""
      }
    })

    vehicle =
      Vehicle
      |> Ash.Query.filter(customer_id == ^customer.id)
      |> Ash.read!()
      |> hd()

    assert vehicle.size == :pickup
  end
```

> Note: the existing "saving a vehicle from the dropdowns persists it and advances" test passes `size` directly in the submit params, so it continues to pass unchanged (the hidden field mirrors that). Leave it as-is.

- [ ] **Step 2: Run tests to verify they fail**

Run: `MIX_ENV=test mix test test/mobile_car_wash_web/live/booking_vehicle_step_test.exs`
Expected: FAIL — badge text/hint not present, `loading_models`/`handle_async` not implemented, size radios still rendered.

- [ ] **Step 3: Add the `loading_models` mount assign**

In `lib/mobile_car_wash_web/live/booking_live.ex`, in the mount base-assigns block, add `loading_models: false` right after `vehicle_models: []` (~line 96):

```elixir
        vehicle_models: [],
        loading_models: false,
```

- [ ] **Step 4: Update the model `<select>` to show the loading state**

Replace the model `<select>` block (the `<select name="vehicle[model]" ...>` element and its options):

```heex
            <label class="form-control w-full">
              <span class="label-text font-semibold mb-1">Model</span>
              <select
                name="vehicle[model]"
                class="select select-bordered w-full"
                required
                disabled={@loading_models or @vehicle_models == []}
              >
                <option value="" disabled selected={@vehicle_form["model"] == ""}>
                  {cond do
                    @loading_models -> "Loading models…"
                    @vehicle_models == [] -> "Pick make & year first"
                    true -> "Select model"
                  end}
                </option>
                <option
                  :for={md <- @vehicle_models}
                  value={md.name}
                  selected={@vehicle_form["model"] == md.name}
                >
                  {md.name}
                </option>
              </select>
              <span :if={@loading_models} class="text-xs text-base-content/60 mt-1 flex items-center gap-1">
                <span class="loading loading-spinner loading-xs"></span> Loading models…
              </span>
            </label>
```

- [ ] **Step 5: Replace the size radio group with a read-only badge + hidden field**

Replace the entire `<div>` containing the "Vehicle type" `<label>` and the three size radio `<label>`s with:

```heex
          <div>
            <label class="text-sm font-semibold text-base-content mb-2 block">Vehicle type</label>
            <div
              :if={@vehicle_form["model"] != "" or @vehicle_form["vin"] != ""}
              class="inline-flex items-center gap-2 rounded-lg border border-base-300 bg-base-200 px-3 py-2"
            >
              <span class="text-lg">{size_badge(@vehicle_form["size"]).icon}</span>
              <span class="text-sm font-semibold">{size_badge(@vehicle_form["size"]).label}</span>
              <span class="text-xs text-warning">{size_badge(@vehicle_form["size"]).modifier}</span>
              <span class="text-xs text-base-content/50">· auto-detected</span>
            </div>
            <p
              :if={@vehicle_form["model"] == "" and @vehicle_form["vin"] == ""}
              class="text-sm text-base-content/50"
            >
              Pick your model and we'll detect the type.
            </p>
          </div>
```

Then add the hidden size field next to the existing hidden vin/body_class fields (which are just above the "Save vehicle" button):

```heex
          <input type="hidden" name="vehicle[size]" value={@vehicle_form["size"]} />
          <input type="hidden" name="vehicle[vin]" value={@vehicle_form["vin"]} />
          <input type="hidden" name="vehicle[body_class]" value={@vehicle_form["body_class"]} />
```

- [ ] **Step 6: Add `phx-disable-with` to the VIN autofill button**

Replace the VIN submit button:

```heex
            <button type="submit" class="btn btn-secondary" phx-disable-with="Decoding…">Autofill</button>
```

- [ ] **Step 7: Add the `size_badge/1` helper**

Add near the other private helpers (e.g. next to `vehicle_colors/0`):

```elixir
  defp size_badge("suv_van"), do: %{icon: "🚙", label: "SUV / Van", modifier: "+20%"}
  defp size_badge("pickup"), do: %{icon: "🚛", label: "Pickup", modifier: "+50%"}
  defp size_badge(_), do: %{icon: "🚗", label: "Car", modifier: "+0"}
```

- [ ] **Step 8: Rewrite `vehicle_form_change` to fetch models asynchronously**

Replace the entire `vehicle_form_change` handler with:

```elixir
  def handle_event("vehicle_form_change", %{"vehicle" => params}, socket) do
    prev = socket.assigns.vehicle_form
    incoming = Map.take(params, ~w(make year model color))
    form = Map.merge(prev, incoming)

    make_year_changed? = {form["make"], form["year"]} != {prev["make"], prev["year"]}

    cond do
      # Make+year both chosen and changed → fetch models asynchronously.
      make_year_changed? and form["make"] != "" and form["year"] != "" ->
        make = form["make"]
        year = form["year"]
        form = Map.put(form, "model", "")

        socket =
          socket
          |> assign(
            vehicle_form: form,
            vehicle_models: [],
            loading_models: true,
            vin_error: nil
          )
          |> start_async(:load_models, fn ->
            NhtsaClient.models_for_make_year(make, year)
          end)

        {:noreply, socket}

      # Make or year cleared → nothing to fetch.
      make_year_changed? ->
        {:noreply,
         assign(socket,
           vehicle_form: Map.put(form, "model", ""),
           vehicle_models: [],
           loading_models: false,
           vin_error: nil
         )}

      # Model (or color) changed → auto-detect size from the selected model.
      true ->
        form =
          if form["model"] != "" and form["model"] != prev["model"] do
            case Enum.find(socket.assigns.vehicle_models, &(&1.name == form["model"])) do
              %{size: size} -> Map.put(form, "size", to_string(size))
              nil -> form
            end
          else
            form
          end

        {:noreply, assign(socket, vehicle_form: form, vin_error: nil)}
    end
  end
```

- [ ] **Step 9: Add the `handle_async(:load_models, …)` callbacks**

Add these next to the `vehicle_form_change` handler (a new callback group):

```elixir
  @impl true
  def handle_async(:load_models, {:ok, {:ok, models}}, socket) do
    {:noreply, assign(socket, vehicle_models: models, loading_models: false)}
  end

  def handle_async(:load_models, {:ok, {:error, _reason}}, socket) do
    {:noreply, assign(socket, vehicle_models: [], loading_models: false)}
  end

  def handle_async(:load_models, {:exit, _reason}, socket) do
    {:noreply, assign(socket, vehicle_models: [], loading_models: false)}
  end
```

- [ ] **Step 10: Run the vehicle-step tests**

Run: `MIX_ENV=test mix test test/mobile_car_wash_web/live/booking_vehicle_step_test.exs`
Expected: PASS (updated + new tests; the removed "user-editable" test is gone).

- [ ] **Step 11: Run the live/ regression suite**

Run: `MIX_ENV=test mix test test/mobile_car_wash_web/live/`
Expected: PASS — other booking tests unaffected.

- [ ] **Step 12: Confirm clean compile**

Run: `MIX_ENV=test mix compile --warnings-as-errors`
Expected: clean (no unused `make_year_changed?`/var warnings; `@impl true` on `handle_async` is valid).

- [ ] **Step 13: Commit**

```bash
git add lib/mobile_car_wash_web/live/booking_live.ex test/mobile_car_wash_web/live/booking_vehicle_step_test.exs
git commit -m "feat: read-only auto-detected vehicle type + async model-loading state"
```

---

## Final verification (before declaring done)

- [ ] **Full gate:** `mix precommit` green (re-run `mix test --failed` once if a known flake appears).
- [ ] **Manual smoke (recommended):** `PORT=4010 mix phx.server`, sign in, reach the vehicle step. Select a make+year → the model field shows "Loading models…" briefly, then fills. Select a model → the **read-only** type badge appears (e.g. F-150 → 🚛 Pickup · +50%) with no way to change it. Decode a VIN → badge reflects the decoded type; the Autofill button shows "Decoding…" while it works. Confirm the price hero matches the detected type.
- [ ] **Then** invoke `superpowers:finishing-a-development-branch` (stash `config/dev.exs`, `AGENTS.md`, `docs/customer-flows.html` before merging, pop after; do not push unless asked).

---

## Self-review (author)

- **Spec coverage:** §2a remove radios + hidden size field + read-only badge + hint (Steps 5, 7) ✓; badge mapping car/suv_van/pickup (Step 7, matches spec values) ✓; badge shown only when model or vin set, else hint (Step 5 `:if` conditions) ✓; no override control (radios removed; "user-editable" test deleted in 1d) ✓; §2b async fetch with `loading_models`, `start_async`, `handle_async` success/error/exit (Steps 3, 8, 9) ✓; model select disabled + "Loading models…" while loading (Step 4) ✓; VIN `phx-disable-with` (Step 6) ✓; §4 tests: badge per size, no radio, hint-before-selection, hidden-field save, loading state, async via `render_async` (Step 1) ✓; size still persisted/priced (hidden field + unchanged `save_vehicle`) ✓.
- **Placeholder scan:** none — every code step has full code.
- **Type consistency:** `size_badge/1` takes the string `vehicle_form["size"]` (e.g. `"pickup"`) and the size auto-fill writes `to_string(size)` strings; `handle_async` matches the `{:ok, [%{name, size}]}`/`{:error, _}` shape from `models_for_make_year/2`; `loading_models` assign is set in mount, the handler, and all `handle_async` clauses, and read in the template.
- **Note:** the existing "saving a vehicle …" test and the VIN-error test are unaffected (no size-radio assertions); the make-dropdown test is unaffected. The hidden `name="vehicle[size]"` input means tests assert absence of the *radio* specifically (`type="radio" name="vehicle[size]"`), not the bare name.
