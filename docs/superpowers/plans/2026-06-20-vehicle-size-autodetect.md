# Auto-detect Vehicle Size on the Dropdown Path — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Auto-populate the vehicle type/size (`:car`/`:suv_van`/`:pickup`) when a customer picks a model from the Make→Year→Model dropdowns (it already auto-fills on the VIN path), while keeping it user-editable.

**Architecture:** When models load for a make+year, `NhtsaClient.models_for_make_year/2` now queries NHTSA's `vehicleType` filter for the `car`/`truck`/`mpv` buckets and returns a merged, size-tagged list `[%{name, size}]`. The booking LiveView renders model option names from that list and, on model selection, sets the size from the chosen model's tag. The VIN decode path is unchanged. Everything stays server-side and cached.

**Tech Stack:** Elixir, Phoenix LiveView, Req (HTTP), ETS cache, Ash.

## Global Constraints

- **TDD mandatory:** failing test → implement → green, per task. Capture RED/GREEN evidence.
- **`mix precommit` must be green** before the phase is done (`compile --warnings-as-errors`, `deps.unlock --unused`, `format`, `test`). Benign noise (NOT failures): Ash "missed notifications" warnings; occasional `Postgrex ... disconnected` lines under async.
- **All third-party calls server-side via `Req`, mockable** via `config :mobile_car_wash, :nhtsa_client`. No client-side keys; CSP unchanged. Tests must NEVER hit the network (the mock is already wired in `config/test.exs`).
- **Pricing stays server-authoritative:** `size` remains the single pricing driver; this only changes how `size` is pre-filled. The auto-filled size MUST stay user-editable (a later size-button click wins).
- **Size atoms** are exactly `:car | :suv_van | :pickup`.
- **NHTSA vehicleType → size mapping** (verbatim): `car → :car`, `truck → :pickup`, `mpv → :suv_van`. On a model-name collision across buckets, precedence is `:pickup > :suv_van > :car`.
- **Never block the flow:** if all typed calls fail, fall back to the untyped names-only call with `size: :car`.
- **Run the app** with `PORT=4010 mix phx.server`.
- Do NOT push to any remote. Do NOT touch `config/dev.exs`, `AGENTS.md`, `docs/customer-flows.html`.

---

## File structure

| File | Responsibility | Task |
|------|----------------|------|
| `lib/mobile_car_wash/vehicles/nhtsa_client.ex` (modify) | `vehicle_type_to_size/1`; `models_for_make_year/2` enriched return; typed-bucket fetch + merge + untyped fallback | 1 |
| `test/mobile_car_wash/vehicles/nhtsa_client_test.exs` (modify) | `vehicle_type_to_size/1` tests; enriched-shape delegation test | 1 |
| `lib/mobile_car_wash_web/live/booking_live.ex` (modify) | model `<option>` from `%{name,size}`; auto-set size on model select; VIN prepend shape | 2 |
| `test/mobile_car_wash_web/live/booking_vehicle_step_test.exs` (modify) | enriched `put_models`; size-autoset + editability tests | 2 |

> The test mock `test/support/nhtsa_client_mock.ex` is **shape-agnostic** — `put_models/3` stores and `models_for_make_year/2` returns whatever the test stages. No code change needed there; tests simply stage the enriched shape.

---

## Task 1: NhtsaClient — size-tagged models via NHTSA vehicleType

**Files:**
- Modify: `lib/mobile_car_wash/vehicles/nhtsa_client.ex`
- Test: `test/mobile_car_wash/vehicles/nhtsa_client_test.exs`

**Interfaces:**
- Produces:
  - `NhtsaClient.vehicle_type_to_size(type :: String.t()) :: :car | :suv_van | :pickup` (pure; `"truck"→:pickup`, `"mpv"→:suv_van`, else `:car`; case-insensitive)
  - `NhtsaClient.models_for_make_year(make, year) :: {:ok, [%{name: String.t(), size: :car | :suv_van | :pickup}]} | {:error, term()}` (sorted by `name`, name-deduped) — **changed return shape** (was `[String.t()]`)
- Consumes: `NhtsaCache.get/1`, `NhtsaCache.put/2` (unchanged).

- [ ] **Step 1: Update the failing tests**

In `test/mobile_car_wash/vehicles/nhtsa_client_test.exs`, **replace** the existing `models_for_make_year` delegation test (the `test "models_for_make_year routes to the mock" do ... end` block) with the enriched-shape version, and **add** a `vehicle_type_to_size/1` describe block. The full new content of those two pieces:

```elixir
  describe "vehicle_type_to_size/1" do
    test "maps NHTSA vehicle-type tokens to size atoms" do
      assert NhtsaClient.vehicle_type_to_size("car") == :car
      assert NhtsaClient.vehicle_type_to_size("truck") == :pickup
      assert NhtsaClient.vehicle_type_to_size("mpv") == :suv_van
    end

    test "is case-insensitive and defaults unknown types to :car" do
      assert NhtsaClient.vehicle_type_to_size("MPV") == :suv_van
      assert NhtsaClient.vehicle_type_to_size("Truck") == :pickup
      assert NhtsaClient.vehicle_type_to_size("bus") == :car
    end
  end
```

And the replacement delegation test (inside the existing `describe "delegation to the configured mock"` block, replacing the old `models_for_make_year` test):

```elixir
    test "models_for_make_year routes to the mock and returns size-tagged models" do
      NhtsaClientMock.put_models("Toyota", 2021, [
        %{name: "Camry", size: :car},
        %{name: "RAV4", size: :suv_van}
      ])

      assert {:ok, [%{name: "Camry", size: :car}, %{name: "RAV4", size: :suv_van}]} =
               NhtsaClient.models_for_make_year("Toyota", 2021)
    end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `MIX_ENV=test mix test test/mobile_car_wash/vehicles/nhtsa_client_test.exs`
Expected: FAIL — `vehicle_type_to_size/1` is undefined (the delegation test will pass already since the mock is shape-agnostic, but the new describe block fails to compile/run).

- [ ] **Step 3: Add `vehicle_type_to_size/1` and the typed-bucket module attributes**

In `lib/mobile_car_wash/vehicles/nhtsa_client.ex`, add the module attributes near the top (after the existing `@base` / `@popular_makes` attributes):

```elixir
  # NHTSA vehicleType filter tokens → our pricing size atom.
  @typed_buckets [{"car", :car}, {"truck", :pickup}, {"mpv", :suv_van}]

  # Size precedence when a model appears in more than one bucket (bias larger).
  @size_rank %{pickup: 2, suv_van: 1, car: 0}
```

Then add the public pure function next to `body_class_to_size/1`:

```elixir
  @doc "Map an NHTSA vehicle-type token to our pricing size atom."
  @spec vehicle_type_to_size(String.t()) :: :car | :suv_van | :pickup
  def vehicle_type_to_size(type) when is_binary(type) do
    case String.downcase(type) do
      "truck" -> :pickup
      "mpv" -> :suv_van
      _ -> :car
    end
  end
```

- [ ] **Step 4: Update the `models_for_make_year/2` doc + spec**

Replace the existing `@doc`/`@spec` above `def models_for_make_year` with:

```elixir
  @doc """
  Models for a make+year, each tagged with our pricing size. Returns
  {:ok, [%{name: String.t(), size: :car | :suv_van | :pickup}]} (sorted by
  name, name-deduped) or {:error, reason}. Cached.
  """
  @spec models_for_make_year(String.t(), integer() | String.t()) ::
          {:ok, [%{name: String.t(), size: :car | :suv_van | :pickup}]} | {:error, term()}
```

(The function body — the `case client_module()` dispatch — stays exactly as is.)

- [ ] **Step 5: Rewrite `do_models_for_make_year/2` and add helpers**

Replace the entire existing `defp do_models_for_make_year(make, year) do ... end` with:

```elixir
  defp do_models_for_make_year(make, year) do
    key = {:models, String.downcase(make), to_string(year)}

    case NhtsaCache.get(key) do
      {:ok, models} ->
        {:ok, models}

      :miss ->
        case fetch_typed_models(make, year) do
          {:ok, models} ->
            NhtsaCache.put(key, models)
            {:ok, models}

          # Every typed call failed — fall back to untyped names (size :car).
          # Not cached, so a later call can retry the richer typed path.
          :all_failed ->
            fetch_untyped_models(make, year)
        end
    end
  end

  # Query the car/truck/mpv buckets and merge into a sorted, size-tagged list.
  # Returns :all_failed only when every bucket request errored.
  defp fetch_typed_models(make, year) do
    results =
      Enum.map(@typed_buckets, fn {token, size} ->
        {size, fetch_models_of_type(make, year, token)}
      end)

    if Enum.all?(results, fn {_size, r} -> match?({:error, _}, r) end) do
      :all_failed
    else
      merged =
        results
        |> Enum.flat_map(fn
          {size, {:ok, names}} -> Enum.map(names, &{&1, size})
          {_size, {:error, _}} -> []
        end)
        |> merge_by_name()

      {:ok, merged}
    end
  end

  defp fetch_models_of_type(make, year, type) do
    url =
      "#{@base}/GetModelsForMakeYear/make/#{URI.encode(make, &URI.char_unreserved?/1)}" <>
        "/modelyear/#{year}/vehicleType/#{type}?format=json"

    case Req.get(url) do
      {:ok, %{status: 200, body: %{"Results" => results}}} when is_list(results) ->
        names =
          results
          |> Enum.map(& &1["Model_Name"])
          |> Enum.reject(&(is_nil(&1) or &1 == ""))

        {:ok, names}

      {:ok, %{status: status}} ->
        Logger.error("NHTSA models error #{status} (#{type})")
        {:error, {:nhtsa_error, status}}

      {:error, reason} ->
        Logger.error("NHTSA models request failed (#{type}): #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp fetch_untyped_models(make, year) do
    url =
      "#{@base}/GetModelsForMakeYear/make/#{URI.encode(make, &URI.char_unreserved?/1)}/modelyear/#{year}?format=json"

    case Req.get(url) do
      {:ok, %{status: 200, body: %{"Results" => results}}} when is_list(results) ->
        models =
          results
          |> Enum.map(& &1["Model_Name"])
          |> Enum.reject(&(is_nil(&1) or &1 == ""))
          |> Enum.map(&{&1, :car})
          |> merge_by_name()

        {:ok, models}

      {:ok, %{status: status}} ->
        Logger.error("NHTSA models error #{status}")
        {:error, {:nhtsa_error, status}}

      {:error, reason} ->
        Logger.error("NHTSA models request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Merge {name, size} pairs into a sorted, name-deduped list of %{name, size},
  # keeping the highest-ranked size (pickup > suv_van > car) on a collision.
  defp merge_by_name(pairs) do
    pairs
    |> Enum.reduce(%{}, fn {name, size}, acc ->
      Map.update(acc, name, size, fn existing ->
        if @size_rank[size] > @size_rank[existing], do: size, else: existing
      end)
    end)
    |> Enum.map(fn {name, size} -> %{name: name, size: size} end)
    |> Enum.sort_by(& &1.name)
  end
```

- [ ] **Step 6: Run the client tests**

Run: `MIX_ENV=test mix test test/mobile_car_wash/vehicles/nhtsa_client_test.exs`
Expected: PASS (all describe blocks, including the new `vehicle_type_to_size/1` and the enriched delegation test).

- [ ] **Step 7: Confirm no compile warnings**

Run: `MIX_ENV=test mix compile --warnings-as-errors`
Expected: compiles clean (no unused-variable / unused-function warnings from the rewrite).

- [ ] **Step 8: Commit**

```bash
git add lib/mobile_car_wash/vehicles/nhtsa_client.ex test/mobile_car_wash/vehicles/nhtsa_client_test.exs
git commit -m "feat: size-tag NHTSA models via vehicleType buckets"
```

---

## Task 2: Booking LiveView — auto-fill size from the selected model

**Files:**
- Modify: `lib/mobile_car_wash_web/live/booking_live.ex` (model `<option>` template ~line 521-525; `vehicle_form_change` handler ~line 1033; `decode_vin` handler model-prepend ~line 1063-1067)
- Test: `test/mobile_car_wash_web/live/booking_vehicle_step_test.exs`

**Interfaces:**
- Consumes: `NhtsaClient.models_for_make_year/2` now returns `{:ok, [%{name, size}]}` (Task 1).
- Produces: the `:vehicle` step auto-fills `vehicle_form["size"]` when a model is chosen (still editable). `@vehicle_models` is now a list of `%{name, size}` maps.

> **Implementer note:** read the named regions before editing (the file is ~1500 lines). `@vehicle_models` was a list of strings; it becomes a list of `%{name, size}` maps. The only consumers are the model `<option>` loop and the two handlers below — grep `vehicle_models` to confirm before editing.

- [ ] **Step 1: Update/extend the failing tests**

In `test/mobile_car_wash_web/live/booking_vehicle_step_test.exs`:

(a) Update every `NhtsaClientMock.put_models(...)` call to the enriched shape. Specifically:
- In the "choosing make + year loads models" test, replace the two staging lines with:
```elixir
    NhtsaClientMock.put_models("Toyota", 2021, [
      %{name: "Camry", size: :car},
      %{name: "Corolla", size: :car},
      %{name: "RAV4", size: :suv_van}
    ])

    NhtsaClientMock.put_models("Honda", 2021, [
      %{name: "Accord", size: :car},
      %{name: "Civic", size: :car}
    ])
```
- In the "saving a vehicle from the dropdowns persists it and advances" test, replace its staging line with:
```elixir
    NhtsaClientMock.put_models("Toyota", 2021, [%{name: "Camry", size: :car}])
```

(The existing assertions in those tests — `html =~ "Camry"`, `"RAV4"`, `"Accord"`, `"Civic"`, and the saved-vehicle assertions — remain unchanged; model names still render.)

(b) Add two new tests at the end of the module (before the final `end`):

```elixir
  test "selecting a model auto-fills the size from its NHTSA vehicle type", %{conn: conn} do
    NhtsaClientMock.put_models("Ford", 2023, [
      %{name: "F-150", size: :pickup},
      %{name: "Focus", size: :car},
      %{name: "Escape", size: :suv_van}
    ])

    {:ok, view, _} = live(conn, "/book")
    to_vehicle_step(view)

    # Load models for Ford 2023
    render_change(view, "vehicle_form_change", %{
      "vehicle" => %{"make" => "Ford", "year" => "2023", "model" => "", "color" => "", "size" => "car"}
    })

    # Pick a pickup → size auto-selects pickup (even though the radio sent "car")
    html =
      render_change(view, "vehicle_form_change", %{
        "vehicle" => %{"make" => "Ford", "year" => "2023", "model" => "F-150", "color" => "", "size" => "car"}
      })

    assert html =~ ~r/name="vehicle\[size\]" value="pickup"[^>]*checked/

    # Pick an SUV → size auto-selects suv_van
    html =
      render_change(view, "vehicle_form_change", %{
        "vehicle" => %{"make" => "Ford", "year" => "2023", "model" => "Escape", "color" => "", "size" => "pickup"}
      })

    assert html =~ ~r/name="vehicle\[size\]" value="suv_van"[^>]*checked/
  end

  test "an auto-filled size remains user-editable", %{conn: conn} do
    NhtsaClientMock.put_models("Ford", 2023, [%{name: "F-150", size: :pickup}])

    {:ok, view, _} = live(conn, "/book")
    to_vehicle_step(view)

    render_change(view, "vehicle_form_change", %{
      "vehicle" => %{"make" => "Ford", "year" => "2023", "model" => "", "color" => "", "size" => "car"}
    })

    # Model picks pickup automatically...
    render_change(view, "vehicle_form_change", %{
      "vehicle" => %{"make" => "Ford", "year" => "2023", "model" => "F-150", "color" => "", "size" => "car"}
    })

    # ...then the user overrides to car (model unchanged) — override sticks.
    html =
      render_change(view, "vehicle_form_change", %{
        "vehicle" => %{"make" => "Ford", "year" => "2023", "model" => "F-150", "color" => "", "size" => "car"}
      })

    assert html =~ ~r/name="vehicle\[size\]" value="car"[^>]*checked/
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `MIX_ENV=test mix test test/mobile_car_wash_web/live/booking_vehicle_step_test.exs`
Expected: FAIL — the auto-fill tests fail (size not set from the model) and the model `<option>` loop crashes on `%{name,size}` maps (template still expects strings).

- [ ] **Step 3: Update the model `<option>` template**

In `lib/mobile_car_wash_web/live/booking_live.ex`, replace the model option loop (the `<option :for={md <- @vehicle_models} ...>` element):

```heex
                <option
                  :for={md <- @vehicle_models}
                  value={md.name}
                  selected={@vehicle_form["model"] == md.name}
                >
                  {md.name}
                </option>
```

(The `disabled={@vehicle_models == []}` and the placeholder `<option>` above it are unchanged — the empty-list check still holds for a list of maps.)

- [ ] **Step 4: Auto-fill size in `vehicle_form_change`**

Replace the entire `vehicle_form_change` handler with the version that auto-fills size on a model change:

```elixir
  def handle_event("vehicle_form_change", %{"vehicle" => params}, socket) do
    prev = socket.assigns.vehicle_form
    incoming = Map.take(params, ~w(make year model color size))
    form = Map.merge(prev, incoming)

    make_year_changed? = {form["make"], form["year"]} != {prev["make"], prev["year"]}

    {form, models} =
      if make_year_changed? and form["make"] != "" and form["year"] != "" do
        case NhtsaClient.models_for_make_year(form["make"], form["year"]) do
          {:ok, models} -> {Map.put(form, "model", ""), models}
          {:error, _} -> {Map.put(form, "model", ""), []}
        end
      else
        {form, socket.assigns.vehicle_models}
      end

    # Auto-fill size from the chosen model (editable: a later size click wins,
    # since that event leaves the model unchanged and skips this branch).
    form =
      if not make_year_changed? and form["model"] != "" and form["model"] != prev["model"] do
        case Enum.find(models, &(&1.name == form["model"])) do
          %{size: size} -> Map.put(form, "size", to_string(size))
          nil -> form
        end
      else
        form
      end

    {:noreply, assign(socket, vehicle_form: form, vehicle_models: models, vin_error: nil)}
  end
```

- [ ] **Step 5: Update the `decode_vin` model-prepend to the `%{name,size}` shape**

In the `decode_vin` handler, replace the "Ensure the decoded model is selectable" block:

```elixir
          # Ensure the decoded model is selectable even if it isn't in the list
          models =
            if decoded.model && decoded.model != "" &&
                 not Enum.any?(models, &(&1.name == decoded.model)),
               do: [%{name: decoded.model, size: decoded.size} | models],
               else: models
```

(The rest of `decode_vin` is unchanged — `form["size"]` still comes from `decoded.size`, so the VIN path keeps its existing auto-fill behavior.)

- [ ] **Step 6: Run the vehicle-step tests**

Run: `MIX_ENV=test mix test test/mobile_car_wash_web/live/booking_vehicle_step_test.exs`
Expected: PASS (all tests, including the two new auto-fill/editability tests).

- [ ] **Step 7: Run the live/ regression suite**

Run: `MIX_ENV=test mix test test/mobile_car_wash_web/live/`
Expected: PASS — existing add-ons, price-header, subscription-price tests still green.

- [ ] **Step 8: Commit**

```bash
git add lib/mobile_car_wash_web/live/booking_live.ex test/mobile_car_wash_web/live/booking_vehicle_step_test.exs
git commit -m "feat: auto-fill vehicle size from selected model in booking flow"
```

---

## Final verification (before declaring done)

- [ ] **Full gate:** `mix precommit` is green (re-run `mix test --failed` once if a known flake appears).
- [ ] **Manual smoke (recommended):** `PORT=4010 mix phx.server`, sign in, start a booking, reach the vehicle step. Pick Make=Ford, Year=2023, Model=F-150 → the size should switch to **Pickup** automatically; pick an SUV model → **SUV / Van**; then click a different size button → your choice sticks. Confirm the VIN path still auto-sets size.
- [ ] **Then** invoke `superpowers:finishing-a-development-branch` (stash `config/dev.exs`, `AGENTS.md`, `docs/customer-flows.html` before merging, pop after; do not push unless asked).

---

## Self-review (author)

- **Spec coverage:** §3 vehicleType buckets + merge precedence (Task 1, `fetch_typed_models`/`merge_by_name`) ✓; §4a `vehicle_type_to_size/1` + enriched `models_for_make_year/2` + untyped fallback + cache (Task 1) ✓; `body_class_to_size`/VIN path unchanged (Task 1 leaves them; Task 2 only adjusts the prepend shape) ✓; §4b LiveView model options + auto-fill-on-select + editable + VIN prepend shape (Task 2) ✓; §4c mock shape-agnostic (no change; tests stage enriched) ✓; §5 tests: `vehicle_type_to_size` mapping, enriched delegation, model-select autoset (pickup + suv_van), editability, VIN still autosets, make-change resets (existing test retained) ✓; §6 fallbacks (all-typed-fail → untyped :car; cache-absent handled by existing NhtsaCache guard) ✓.
- **Placeholder scan:** none — every code step contains full code.
- **Type consistency:** `models_for_make_year/2` returns `[%{name, size}]` in Task 1 and is consumed as `md.name` / `&(&1.name == ...)` / `%{size: size}` in Task 2; `vehicle_type_to_size/1` and `@typed_buckets` sizes are the same `:car|:suv_van|:pickup` atoms the `Vehicle.size` constraint accepts and the size radios use; `@size_rank` keys match those atoms.
- **Note on intermediate state:** after Task 1 alone, the dev runtime's real client returns maps while the (not-yet-updated) LiveView template expects strings — tests stay green (test env uses the mock and the still-string vehicle-step test until Task 2). Task 2 completes the migration; the branch is only merged after both. Acceptable under subagent-driven execution (nothing ships mid-plan).
