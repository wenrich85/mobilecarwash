# Booking Redesign — Phase 3: NHTSA Vehicle Step Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the booking wizard's free-text vehicle form with a Make→Year→Model dropdown flow (sourced from the NHTSA vPIC API), a typed-VIN autofill shortcut, color swatches, and an auto-detected-but-editable size — keeping pricing server-authoritative.

**Architecture:** A new mockable server-side client `MobileCarWash.Vehicles.NhtsaClient` (mirrors `Notifications.TwilioClient`) calls the free NHTSA vPIC API via `Req`. Makes are a curated module constant; models (keyed by make **and** year) are fetched on demand and cached in an in-memory ETS TTL cache `MobileCarWash.Vehicles.NhtsaCache` (~30-day TTL, re-warms after restart). VIN decode autofills make/model/year and maps NHTSA `BodyClass` → our `:car | :suv_van | :pickup` size atom. The booking LiveView's `:vehicle` step is reworked to drive these; `Vehicle` gains optional `vin` + `body_class` provenance columns; `size` stays the sole pricing driver.

**Tech Stack:** Elixir, Phoenix LiveView, Ash + AshPostgres, Req (HTTP), ETS, Tailwind/daisyUI.

## Global Constraints

- **TDD is mandatory** — failing test → implement → green, per task.
- **`mix precommit` must be green** before the phase is done (`compile --warnings-as-errors`, `deps.unlock --unused`, `format`, `test`). Benign noise: Ash "missed notifications" warnings and occasional `Postgrex ... disconnected` lines under async are NOT failures.
- **All third-party calls are server-side via `Req`, mockable via app config.** No client-side keys; CSP/`connect-src` stays unchanged. Pattern to mirror: `lib/mobile_car_wash/notifications/twilio_client.ex`.
- **Tests must never hit the network.** Configure the mock in `config/test.exs`.
- **Pricing stays server-authoritative.** The LiveView never sends a trusted price. `size` (`:car` 1.0× / `:suv_van` 1.2× / `:pickup` 1.5×) remains the pricing driver; `vin`/`body_class` are provenance only.
- **Migrations are Ash-generated.** Use `mix ash.codegen <name>`, then `mix ecto.migrate` AND `MIX_ENV=test mix ecto.migrate`. **GOTCHA:** inspect every generated migration and strip any unrelated DDL (a stale `photos` alter-table previously leaked in via snapshot drift).
- **Run the app** with `PORT=4010 mix phx.server` (port 4000 is the user's other project).
- **Scope note (decided):** VIN shortcut is **typed-VIN decode only** this phase (no camera/OCR). Models/makes cache is **ETS in-memory** (no DB table).

---

## File structure

| File | Responsibility | Task |
|------|----------------|------|
| `lib/mobile_car_wash/vehicles/nhtsa_cache.ex` (create) | ETS TTL cache GenServer for makes/models | 1 |
| `lib/mobile_car_wash/application.ex` (modify) | Start `NhtsaCache` in the supervision tree | 1 |
| `test/mobile_car_wash/vehicles/nhtsa_cache_test.exs` (create) | Cache hit/miss/expiry | 1 |
| `lib/mobile_car_wash/vehicles/nhtsa_client.ex` (create) | VIN decode + makes/models + body-class→size, cached, mockable | 2 |
| `test/support/nhtsa_client_mock.ex` (create) | ETS-backed test mock | 2 |
| `config/test.exs` (modify) | Wire the mock client in test | 2 |
| `test/mobile_car_wash/vehicles/nhtsa_client_test.exs` (create) | body-class mapping, makes, delegation | 2 |
| `lib/mobile_car_wash/fleet/vehicle.ex` (modify) | Add optional `vin` + `body_class` attrs | 3 |
| `priv/repo/migrations/*_add_vehicle_vin_body_class.exs` (generated) | DDL for the two columns | 3 |
| `test/mobile_car_wash/fleet/vehicle_test.exs` (create) | Persist vin/body_class | 3 |
| `lib/mobile_car_wash_web/live/booking_live.ex` (modify) | Vehicle step UI: dropdowns, VIN autofill, swatches, save threading | 4 |
| `test/mobile_car_wash_web/live/booking_vehicle_step_test.exs` (create) | Dropdown render, model load, VIN autofill, save, VIN error | 4 |

---

## Task 1: NHTSA ETS TTL cache

**Files:**
- Create: `lib/mobile_car_wash/vehicles/nhtsa_cache.ex`
- Modify: `lib/mobile_car_wash/application.ex` (children list, ~line 10-19)
- Test: `test/mobile_car_wash/vehicles/nhtsa_cache_test.exs`

**Interfaces:**
- Produces:
  - `NhtsaCache.get(key :: term()) :: {:ok, value :: term()} | :miss`
  - `NhtsaCache.put(key :: term(), value :: term(), ttl_ms :: non_neg_integer() \\ 30 days) :: value`
  - `NhtsaCache.start_link(opts) :: GenServer.on_start()` (created the named ETS table `:nhtsa_cache` in `init/1`)

- [ ] **Step 1: Write the failing test**

Create `test/mobile_car_wash/vehicles/nhtsa_cache_test.exs`:

```elixir
defmodule MobileCarWash.Vehicles.NhtsaCacheTest do
  # async: false — shared named ETS table started with the app
  use ExUnit.Case, async: false

  alias MobileCarWash.Vehicles.NhtsaCache

  test "put then get returns the cached value" do
    key = {:models, "toyota", "2021", System.unique_integer([:positive])}
    assert NhtsaCache.put(key, ["Camry", "Corolla"]) == ["Camry", "Corolla"]
    assert NhtsaCache.get(key) == {:ok, ["Camry", "Corolla"]}
  end

  test "get returns :miss for an unknown key" do
    assert NhtsaCache.get({:nope, System.unique_integer([:positive])}) == :miss
  end

  test "get returns :miss once the entry has expired" do
    key = {:models, "ford", "2020", System.unique_integer([:positive])}
    NhtsaCache.put(key, ["F-150"], 0)
    assert NhtsaCache.get(key) == :miss
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `MIX_ENV=test mix test test/mobile_car_wash/vehicles/nhtsa_cache_test.exs`
Expected: FAIL — `module MobileCarWash.Vehicles.NhtsaCache is not available`.

- [ ] **Step 3: Write the cache**

Create `lib/mobile_car_wash/vehicles/nhtsa_cache.ex`:

```elixir
defmodule MobileCarWash.Vehicles.NhtsaCache do
  @moduledoc """
  In-memory ETS TTL cache for NHTSA vPIC responses (makes/models).
  In-memory only — re-warms from the API after a restart. Keeps the
  vehicle dropdowns instant and limits external calls.
  """
  use GenServer

  @table :nhtsa_cache
  @default_ttl_ms :timer.hours(24 * 30)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Fetch a cached value. Returns {:ok, value} on a live hit, :miss otherwise."
  @spec get(term()) :: {:ok, term()} | :miss
  def get(key) do
    case :ets.lookup(@table, key) do
      [{^key, value, expires_at}] ->
        if System.monotonic_time(:millisecond) < expires_at, do: {:ok, value}, else: :miss

      _ ->
        :miss
    end
  end

  @doc "Store a value with a TTL (default ~30 days). Returns the value."
  @spec put(term(), term(), non_neg_integer()) :: term()
  def put(key, value, ttl_ms \\ @default_ttl_ms) do
    expires_at = System.monotonic_time(:millisecond) + ttl_ms
    :ets.insert(@table, {key, value, expires_at})
    value
  end

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, %{}}
  end
end
```

- [ ] **Step 4: Add the cache to the supervision tree**

In `lib/mobile_car_wash/application.ex`, add `NhtsaCache` to the `children` list (after `Phoenix.PubSub`, before `MobileCarWashWeb.Presence`):

```elixir
      {Phoenix.PubSub, name: MobileCarWash.PubSub},
      # In-memory cache for NHTSA makes/models (Phase 3 vehicle step)
      MobileCarWash.Vehicles.NhtsaCache,
      # Presence — must start after PubSub, before Endpoint
      MobileCarWashWeb.Presence,
```

- [ ] **Step 5: Run test to verify it passes**

Run: `MIX_ENV=test mix test test/mobile_car_wash/vehicles/nhtsa_cache_test.exs`
Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/mobile_car_wash/vehicles/nhtsa_cache.ex lib/mobile_car_wash/application.ex test/mobile_car_wash/vehicles/nhtsa_cache_test.exs
git commit -m "feat: ETS TTL cache for NHTSA makes/models"
```

---

## Task 2: NHTSA vPIC client (mockable) + mock + test wiring

**Files:**
- Create: `lib/mobile_car_wash/vehicles/nhtsa_client.ex`
- Create: `test/support/nhtsa_client_mock.ex`
- Modify: `config/test.exs` (add mock config near the other `*_client` mocks, ~line 38)
- Test: `test/mobile_car_wash/vehicles/nhtsa_client_test.exs`

**Interfaces:**
- Consumes: `NhtsaCache.get/1`, `NhtsaCache.put/2` (Task 1).
- Produces (both real client and mock implement the same delegated functions):
  - `NhtsaClient.popular_makes() :: [String.t()]` (curated constant; NOT delegated — always the real list)
  - `NhtsaClient.body_class_to_size(String.t() | nil) :: :car | :suv_van | :pickup` (pure; NOT delegated)
  - `NhtsaClient.decode_vin(vin :: String.t()) :: {:ok, %{make: String.t(), model: String.t() | nil, year: integer() | nil, body_class: String.t() | nil, size: :car | :suv_van | :pickup}} | {:error, term()}`
  - `NhtsaClient.models_for_make_year(make :: String.t(), year :: integer() | String.t()) :: {:ok, [String.t()]} | {:error, term()}`
  - Mock helpers (test only): `NhtsaClientMock.init/0`, `NhtsaClientMock.put_vin(vin, result)`, `NhtsaClientMock.put_models(make, year, models)`

- [ ] **Step 1: Write the failing test**

Create `test/mobile_car_wash/vehicles/nhtsa_client_test.exs`:

```elixir
defmodule MobileCarWash.Vehicles.NhtsaClientTest do
  # async: false — toggles the :nhtsa_client app env and uses a shared mock table
  use ExUnit.Case, async: false

  alias MobileCarWash.Vehicles.{NhtsaClient, NhtsaClientMock}

  describe "popular_makes/0" do
    test "returns a non-empty curated list that includes common makes" do
      makes = NhtsaClient.popular_makes()
      assert is_list(makes) and length(makes) >= 20
      assert "Toyota" in makes
      assert "Ford" in makes
    end
  end

  describe "body_class_to_size/1" do
    test "maps pickups and trucks to :pickup" do
      assert NhtsaClient.body_class_to_size("Pickup") == :pickup
      assert NhtsaClient.body_class_to_size("Truck-Tractor") == :pickup
      assert NhtsaClient.body_class_to_size("Crew Cab") == :pickup
    end

    test "maps SUVs, vans, minivans and wagons to :suv_van" do
      assert NhtsaClient.body_class_to_size("Sport Utility Vehicle (SUV)/Multi-Purpose Vehicle (MPV)") == :suv_van
      assert NhtsaClient.body_class_to_size("Minivan") == :suv_van
      assert NhtsaClient.body_class_to_size("Van") == :suv_van
      assert NhtsaClient.body_class_to_size("Wagon") == :suv_van
    end

    test "maps sedans/coupes and unknowns/nil to :car" do
      assert NhtsaClient.body_class_to_size("Sedan/Saloon") == :car
      assert NhtsaClient.body_class_to_size("Coupe") == :car
      assert NhtsaClient.body_class_to_size("Spaceship") == :car
      assert NhtsaClient.body_class_to_size(nil) == :car
    end
  end

  describe "delegation to the configured mock" do
    setup do
      NhtsaClientMock.init()
      :ok
    end

    test "decode_vin routes to the mock and returns its canned result" do
      NhtsaClientMock.put_vin("1HGCM82633A004352", {:ok, %{make: "Honda", model: "Accord", year: 2003, body_class: "Sedan/Saloon", size: :car}})

      assert {:ok, %{make: "Honda", size: :car}} = NhtsaClient.decode_vin("1HGCM82633A004352")
    end

    test "decode_vin returns the mock's not-decoded error for an unknown VIN" do
      assert {:error, :vin_not_decoded} = NhtsaClient.decode_vin("BADVIN")
    end

    test "models_for_make_year routes to the mock" do
      NhtsaClientMock.put_models("Toyota", 2021, ["Camry", "Corolla", "RAV4"])

      assert {:ok, ["Camry", "Corolla", "RAV4"]} = NhtsaClient.models_for_make_year("Toyota", 2021)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `MIX_ENV=test mix test test/mobile_car_wash/vehicles/nhtsa_client_test.exs`
Expected: FAIL — `module MobileCarWash.Vehicles.NhtsaClient is not available`.

- [ ] **Step 3: Write the client**

Create `lib/mobile_car_wash/vehicles/nhtsa_client.ex`:

```elixir
defmodule MobileCarWash.Vehicles.NhtsaClient do
  @moduledoc """
  NHTSA vPIC API client — VIN decode + makes/models — via Req.

  Free, no API key. Mockable in tests via `config :mobile_car_wash, :nhtsa_client`.
  Models (keyed by make AND year) are cached in `NhtsaCache` (~30d TTL).
  """
  require Logger

  alias MobileCarWash.Vehicles.NhtsaCache

  @base "https://vpic.nhtsa.dot.gov/api/vehicles"

  # Curated list of popular makes shown first in the dropdown (alphabetical).
  @popular_makes [
    "Acura", "Audi", "BMW", "Buick", "Cadillac", "Chevrolet", "Chrysler",
    "Dodge", "Ford", "GMC", "Honda", "Hyundai", "Infiniti", "Jeep", "Kia",
    "Land Rover", "Lexus", "Lincoln", "Mazda", "Mercedes-Benz", "Mini",
    "Mitsubishi", "Nissan", "Porsche", "Ram", "Subaru", "Tesla", "Toyota",
    "Volkswagen", "Volvo"
  ]

  @doc "Curated list of popular makes shown first in the dropdown."
  @spec popular_makes() :: [String.t()]
  def popular_makes, do: @popular_makes

  @doc "Decode a VIN. Returns {:ok, map} (make/model/year/body_class/size) or {:error, reason}."
  @spec decode_vin(String.t()) :: {:ok, map()} | {:error, term()}
  def decode_vin(vin) do
    case client_module() do
      __MODULE__ -> do_decode_vin(vin)
      mock -> mock.decode_vin(vin)
    end
  end

  @doc "Models for a make+year. Returns {:ok, [String.t()]} or {:error, reason}. Cached."
  @spec models_for_make_year(String.t(), integer() | String.t()) ::
          {:ok, [String.t()]} | {:error, term()}
  def models_for_make_year(make, year) do
    case client_module() do
      __MODULE__ -> do_models_for_make_year(make, year)
      mock -> mock.models_for_make_year(make, year)
    end
  end

  @doc "Map an NHTSA BodyClass string to our pricing size atom."
  @spec body_class_to_size(String.t() | nil) :: :car | :suv_van | :pickup
  def body_class_to_size(nil), do: :car

  def body_class_to_size(body_class) when is_binary(body_class) do
    bc = String.downcase(body_class)

    cond do
      String.contains?(bc, "pickup") -> :pickup
      String.contains?(bc, ["truck", "cab"]) -> :pickup
      String.contains?(bc, ["sport utility", "suv", "minivan", "van", "wagon", "mpv"]) -> :suv_van
      true -> :car
    end
  end

  # --- Real HTTP implementations ---

  defp do_decode_vin(vin) do
    url = "#{@base}/DecodeVinValues/#{vin}?format=json"

    case Req.get(url) do
      {:ok, %{status: 200, body: %{"Results" => [row | _]}}} ->
        make = row["Make"]

        if is_binary(make) and make != "" do
          body_class = blank_to_nil(row["BodyClass"])

          {:ok,
           %{
             make: titleize(make),
             model: blank_to_nil(row["Model"]),
             year: parse_year(row["ModelYear"]),
             body_class: body_class,
             size: body_class_to_size(body_class)
           }}
        else
          {:error, :vin_not_decoded}
        end

      {:ok, %{status: status}} ->
        Logger.error("NHTSA VIN decode error #{status}")
        {:error, {:nhtsa_error, status}}

      {:error, reason} ->
        Logger.error("NHTSA VIN request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp do_models_for_make_year(make, year) do
    key = {:models, String.downcase(make), to_string(year)}

    case NhtsaCache.get(key) do
      {:ok, models} ->
        {:ok, models}

      :miss ->
        url = "#{@base}/GetModelsForMakeYear/make/#{URI.encode(make)}/modelyear/#{year}?format=json"

        case Req.get(url) do
          {:ok, %{status: 200, body: %{"Results" => results}}} when is_list(results) ->
            models =
              results
              |> Enum.map(& &1["Model_Name"])
              |> Enum.reject(&(is_nil(&1) or &1 == ""))
              |> Enum.uniq()
              |> Enum.sort()

            NhtsaCache.put(key, models)
            {:ok, models}

          {:ok, %{status: status}} ->
            Logger.error("NHTSA models error #{status}")
            {:error, {:nhtsa_error, status}}

          {:error, reason} ->
            Logger.error("NHTSA models request failed: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  # --- Helpers ---

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(s) when is_binary(s), do: s

  defp parse_year(nil), do: nil
  defp parse_year(y) when is_integer(y), do: y

  defp parse_year(y) when is_binary(y) do
    case Integer.parse(y) do
      {int, _} -> int
      :error -> nil
    end
  end

  defp titleize(s) do
    s |> String.split(" ") |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp client_module do
    Application.get_env(:mobile_car_wash, :nhtsa_client, __MODULE__)
  end
end
```

- [ ] **Step 4: Write the mock**

Create `test/support/nhtsa_client_mock.ex`:

```elixir
defmodule MobileCarWash.Vehicles.NhtsaClientMock do
  @moduledoc """
  Test mock for `NhtsaClient`. Tests stage canned responses with
  `put_vin/2` and `put_models/3`; the client delegates here in test env so
  no NHTSA network call is ever made. Backed by a named ETS table.
  """
  @table :nhtsa_mock

  def init do
    ensure_table()
    :ets.delete_all_objects(@table)
  end

  def put_vin(vin, result), do: insert({:vin, vin}, result)
  def put_models(make, year, models), do: insert({:models, make, to_string(year)}, models)

  def decode_vin(vin) do
    case lookup({:vin, vin}) do
      {:ok, result} -> result
      :miss -> {:error, :vin_not_decoded}
    end
  end

  def models_for_make_year(make, year) do
    case lookup({:models, make, to_string(year)}) do
      {:ok, models} -> {:ok, models}
      :miss -> {:ok, []}
    end
  end

  defp insert(key, value) do
    ensure_table()
    :ets.insert(@table, {key, value})
    value
  end

  defp lookup(key) do
    ensure_table()

    case :ets.lookup(@table, key) do
      [{^key, value}] -> {:ok, value}
      _ -> :miss
    end
  end

  defp ensure_table do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :public, :set])
    end
  end
end
```

- [ ] **Step 5: Wire the mock in test config**

In `config/test.exs`, add next to the other `*_client` mock lines (after the Twilio mock, ~line 38):

```elixir
# Use the ETS-backed mock NHTSA client in tests so no vehicle lookups
# ever hit the network.
config :mobile_car_wash, :nhtsa_client, MobileCarWash.Vehicles.NhtsaClientMock
```

- [ ] **Step 6: Run test to verify it passes**

Run: `MIX_ENV=test mix test test/mobile_car_wash/vehicles/nhtsa_client_test.exs`
Expected: PASS (all describe blocks green). `decode_vin`/`models_for_make_year` route to the mock; `popular_makes`/`body_class_to_size` run on the real module.

- [ ] **Step 7: Commit**

```bash
git add lib/mobile_car_wash/vehicles/nhtsa_client.ex test/support/nhtsa_client_mock.ex config/test.exs test/mobile_car_wash/vehicles/nhtsa_client_test.exs
git commit -m "feat: mockable NHTSA vPIC client (VIN decode + makes/models)"
```

---

## Task 3: Vehicle resource — optional `vin` + `body_class`

**Files:**
- Modify: `lib/mobile_car_wash/fleet/vehicle.ex` (attributes block)
- Generated: `priv/repo/migrations/*_add_vehicle_vin_body_class.exs`
- Test: `test/mobile_car_wash/fleet/vehicle_test.exs`

**Interfaces:**
- Produces: `Vehicle` now has public optional attributes `vin :: :string` and `body_class :: :string`. The default `create: :*` / `update: :*` actions accept them (they are public). `size` is unchanged and remains the pricing driver.

- [ ] **Step 1: Write the failing test**

Create `test/mobile_car_wash/fleet/vehicle_test.exs`:

```elixir
defmodule MobileCarWash.Fleet.VehicleTest do
  use MobileCarWash.DataCase, async: true

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Fleet.Vehicle

  setup do
    {:ok, customer} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "veh-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Veh Test",
        phone: "+15125550000"
      })
      |> Ash.create()

    %{customer: customer}
  end

  test "persists optional vin and body_class as provenance", %{customer: customer} do
    vehicle =
      Vehicle
      |> Ash.Changeset.for_create(:create, %{
        make: "Honda",
        model: "Accord",
        year: 2003,
        size: :car,
        vin: "1HGCM82633A004352",
        body_class: "Sedan/Saloon"
      })
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create!()

    assert vehicle.vin == "1HGCM82633A004352"
    assert vehicle.body_class == "Sedan/Saloon"
    assert vehicle.size == :car
  end

  test "vin and body_class are optional (nil when omitted)", %{customer: customer} do
    vehicle =
      Vehicle
      |> Ash.Changeset.for_create(:create, %{make: "Toyota", model: "Camry", year: 2021})
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.create!()

    assert is_nil(vehicle.vin)
    assert is_nil(vehicle.body_class)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `MIX_ENV=test mix test test/mobile_car_wash/fleet/vehicle_test.exs`
Expected: FAIL — unknown input `vin` (attribute does not exist yet).

- [ ] **Step 3: Add the attributes**

In `lib/mobile_car_wash/fleet/vehicle.ex`, inside the `attributes do` block, add after the `:color` attribute (before `:size`):

```elixir
    attribute :vin, :string do
      public?(true)
      description("VIN as provided by the customer; provenance only, not a pricing input")
    end

    attribute :body_class, :string do
      public?(true)
      description("NHTSA BodyClass from VIN decode; provenance for the auto-selected size")
    end
```

- [ ] **Step 4: Generate and inspect the migration**

Run: `mix ash.codegen add_vehicle_vin_body_class`

Then **open the generated file** under `priv/repo/migrations/` and confirm it ONLY adds the two `vehicles` columns:

```elixir
    alter table(:vehicles) do
      add :vin, :text
      add :body_class, :text
    end
```

If any unrelated DDL appears (e.g. a `photos` alter-table), delete those lines — they are snapshot drift, not part of this change.

- [ ] **Step 5: Migrate dev and test databases**

```bash
mix ecto.migrate
MIX_ENV=test mix ecto.migrate
```

- [ ] **Step 6: Run test to verify it passes**

Run: `MIX_ENV=test mix test test/mobile_car_wash/fleet/vehicle_test.exs`
Expected: PASS (2 tests).

- [ ] **Step 7: Commit**

```bash
git add lib/mobile_car_wash/fleet/vehicle.ex priv/repo/migrations/ priv/resource_snapshots/ test/mobile_car_wash/fleet/vehicle_test.exs
git commit -m "feat: add optional vin + body_class provenance to Vehicle"
```

---

## Task 4: Booking LiveView — NHTSA vehicle step UI

**Files:**
- Modify: `lib/mobile_car_wash_web/live/booking_live.ex`
  - alias block (top of module) — add `NhtsaClient` alias
  - mount base assigns (~lines 88-94) — add vehicle-form assigns
  - vehicle step template (~lines 410-484) — replace the add-new form region
  - `save_vehicle` handler (~lines 917-952) — accept vin/body_class
  - new handlers `vehicle_form_change` and `decode_vin`
  - private helpers `vehicle_years/0`, `vehicle_colors/0`
- Test: `test/mobile_car_wash_web/live/booking_vehicle_step_test.exs`

**Interfaces:**
- Consumes: `NhtsaClient.popular_makes/0`, `NhtsaClient.decode_vin/1`, `NhtsaClient.models_for_make_year/2` (Task 2); `Vehicle` create with `vin`/`body_class` (Task 3).
- Produces: vehicle step now renders Make/Year/Model `<select>`s, a VIN autofill form (`phx-submit="decode_vin"`), color swatches, and size buttons. New events: `decode_vin` (`%{"vin" => v}`), `vehicle_form_change` (`%{"vehicle" => params}`). `save_vehicle` persists `vin`/`body_class` when present.

> **Implementer note:** read `lib/mobile_car_wash_web/live/booking_live.ex` around the line ranges above before editing — it is ~1450 lines and has been the subject of careful work. The `:vehicle` step already exists in `MobileCarWash.Booking.StateMachine`; **do not touch the state machine.**

- [ ] **Step 1: Write the failing test**

Create `test/mobile_car_wash_web/live/booking_vehicle_step_test.exs`:

```elixir
defmodule MobileCarWashWeb.BookingVehicleStepTest do
  # async: false — sign-in writes a session token; mock NHTSA table is shared
  use MobileCarWashWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Scheduling.ServiceType
  alias MobileCarWash.Fleet.Vehicle
  alias MobileCarWash.Vehicles.NhtsaClientMock

  setup %{conn: conn} do
    NhtsaClientMock.init()

    {:ok, customer} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "veh-step-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Veh Step",
        phone: "+15125550000"
      })
      |> Ash.create()

    ServiceType
    |> Ash.Changeset.for_create(:create, %{
      name: "Basic Wash",
      slug: "basic_wash",
      description: "x",
      base_price_cents: 5_000,
      duration_minutes: 45
    })
    |> Ash.create!()

    conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> post("/auth/customer/password/sign_in", %{
        "customer" => %{"email" => to_string(customer.email), "password" => "Password123!"}
      })
      |> recycle()

    %{conn: conn, customer: customer}
  end

  # Signed-in: select_service → next_step (:add_ons) → next_step (auth skipped → :vehicle)
  defp to_vehicle_step(view) do
    render_click(view, "select_service", %{"slug" => "basic_wash"})
    render_click(view, "next_step", %{})
    render_click(view, "next_step", %{})
  end

  test "vehicle step renders the make dropdown with curated makes", %{conn: conn} do
    {:ok, view, _} = live(conn, "/book")
    html = to_vehicle_step(view)

    assert html =~ "Autofill from VIN"
    assert html =~ ~s(name="vehicle[make]")
    assert html =~ "Toyota"
    assert html =~ "Honda"
  end

  test "choosing make + year loads models from NHTSA into the model dropdown", %{conn: conn} do
    NhtsaClientMock.put_models("Toyota", 2021, ["Camry", "Corolla", "RAV4"])

    {:ok, view, _} = live(conn, "/book")
    to_vehicle_step(view)

    html =
      view
      |> form("form[phx-change='vehicle_form_change']",
        vehicle: %{make: "Toyota", year: "2021", model: "", color: "", size: "car"}
      )
      |> render_change()

    assert html =~ "Camry"
    assert html =~ "RAV4"
  end

  test "VIN autofill populates the form and auto-selects size from body class", %{conn: conn} do
    NhtsaClientMock.put_vin("1HGCM82633A004352", {:ok, %{make: "Honda", model: "Accord", year: 2003, body_class: "Sedan/Saloon", size: :car}})

    {:ok, view, _} = live(conn, "/book")
    to_vehicle_step(view)

    html = render_submit(view, "decode_vin", %{"vin" => "1HGCM82633A004352"})

    # Decoded make/model rendered as selected options
    assert html =~ "Honda"
    assert html =~ "Accord"
    # size=car radio is checked
    assert html =~ ~r/name="vehicle\[size\]" value="car"[^>]*checked/
  end

  test "an undecodable VIN shows an inline error and never blocks manual entry", %{conn: conn} do
    {:ok, view, _} = live(conn, "/book")
    to_vehicle_step(view)

    html = render_submit(view, "decode_vin", %{"vin" => "NOTAVIN"})

    assert html =~ "Couldn&#39;t read that VIN"
    # Manual dropdowns still present
    assert html =~ ~s(name="vehicle[make]")
  end

  test "saving a vehicle from the dropdowns persists it and advances", %{conn: conn, customer: customer} do
    NhtsaClientMock.put_models("Toyota", 2021, ["Camry"])

    {:ok, view, _} = live(conn, "/book")
    to_vehicle_step(view)

    render_submit(view, "save_vehicle", %{
      "vehicle" => %{
        "make" => "Toyota",
        "model" => "Camry",
        "year" => "2021",
        "color" => "Silver",
        "size" => "suv_van",
        "vin" => "",
        "body_class" => ""
      }
    })

    vehicle =
      Vehicle
      |> Ash.Query.filter(customer_id == ^customer.id)
      |> Ash.read!()
      |> hd()

    assert vehicle.make == "Toyota"
    assert vehicle.model == "Camry"
    assert vehicle.size == :suv_van
    assert is_nil(vehicle.vin)
  end
end
```

Add `require Ash.Query` at the top of the test module (under `import Phoenix.LiveViewTest`) so the `Ash.Query.filter` macro is available:

```elixir
  require Ash.Query
```

- [ ] **Step 2: Run test to verify it fails**

Run: `MIX_ENV=test mix test test/mobile_car_wash_web/live/booking_vehicle_step_test.exs`
Expected: FAIL — the make dropdown / VIN form / `vehicle_form_change` event do not exist yet.

- [ ] **Step 3: Add the alias**

At the top of `lib/mobile_car_wash_web/live/booking_live.ex`, alongside the existing aliases, add:

```elixir
  alias MobileCarWash.Vehicles.NhtsaClient
```

- [ ] **Step 4: Add vehicle-form mount assigns**

In the mount base-assigns map (the block around lines 88-94 that sets `existing_vehicles: []`, `show_new_vehicle_form: false`, `vehicle_form: nil`), replace `vehicle_form: nil` with the form state and add the dropdown data:

```elixir
        existing_vehicles: [],
        show_new_vehicle_form: false,
        vehicle_makes: NhtsaClient.popular_makes(),
        vehicle_models: [],
        vehicle_form: %{
          "make" => "",
          "year" => "",
          "model" => "",
          "color" => "",
          "size" => "car",
          "vin" => "",
          "body_class" => ""
        },
        vin_error: nil,
```

(Keep the surrounding keys; just ensure these are present in the assigns. If `vehicle_form: nil` appears in more than one assigns map — e.g. a restored-session branch — apply the same map there. Grep `vehicle_form` first to confirm all sites.)

- [ ] **Step 5: Replace the add-new vehicle form template**

In the `:vehicle` step block (~lines 441-479), replace the existing `<form phx-submit="save_vehicle" ...>...</form>` with a VIN form plus a dropdown form. Leave the saved-vehicles list and "+ Add new vehicle" toggle (lines ~418-437) and the trailing `<div :if={@selected_vehicle}>` Continue button (lines ~481-483) untouched.

```heex
        <%!-- VIN autofill shortcut --%>
        <form
          :if={@existing_vehicles == [] or @show_new_vehicle_form}
          phx-submit="decode_vin"
          class="bg-base-200 border border-base-300 rounded-box p-4 space-y-2 mb-4"
        >
          <label class="text-sm font-semibold text-base-content block">⚡ Autofill from VIN</label>
          <div class="flex gap-2">
            <input
              type="text"
              name="vin"
              value={@vehicle_form["vin"]}
              placeholder="1HGCM82633A004352"
              maxlength="17"
              class="input input-bordered flex-1 uppercase"
              autocomplete="off"
            />
            <button type="submit" class="btn btn-secondary">Autofill</button>
          </div>
          <p :if={@vin_error} class="text-xs text-error">{@vin_error}</p>
        </form>

        <%!-- Manual dropdown form --%>
        <form
          :if={@existing_vehicles == [] or @show_new_vehicle_form}
          phx-change="vehicle_form_change"
          phx-submit="save_vehicle"
          class="bg-base-100 border border-base-300 rounded-box p-5 space-y-4 mb-6"
        >
          <div :if={@existing_vehicles == []} class="text-sm font-semibold text-base-content">
            Add your vehicle
          </div>

          <div class="grid grid-cols-1 sm:grid-cols-3 gap-3">
            <label class="form-control w-full">
              <span class="label-text font-semibold mb-1">Make</span>
              <select name="vehicle[make]" class="select select-bordered w-full" required>
                <option value="" disabled selected={@vehicle_form["make"] == ""}>Select make</option>
                <option :for={mk <- @vehicle_makes} value={mk} selected={@vehicle_form["make"] == mk}>
                  {mk}
                </option>
              </select>
            </label>

            <label class="form-control w-full">
              <span class="label-text font-semibold mb-1">Year</span>
              <select name="vehicle[year]" class="select select-bordered w-full" required>
                <option value="" disabled selected={@vehicle_form["year"] == ""}>Select year</option>
                <option
                  :for={yr <- vehicle_years()}
                  value={yr}
                  selected={to_string(@vehicle_form["year"]) == to_string(yr)}
                >
                  {yr}
                </option>
              </select>
            </label>

            <label class="form-control w-full">
              <span class="label-text font-semibold mb-1">Model</span>
              <select
                name="vehicle[model]"
                class="select select-bordered w-full"
                required
                disabled={@vehicle_models == []}
              >
                <option value="" disabled selected={@vehicle_form["model"] == ""}>
                  {if @vehicle_models == [], do: "Pick make & year first", else: "Select model"}
                </option>
                <option
                  :for={md <- @vehicle_models}
                  value={md}
                  selected={@vehicle_form["model"] == md}
                >
                  {md}
                </option>
              </select>
            </label>
          </div>

          <div>
            <label class="text-sm font-semibold text-base-content mb-2 block">Color</label>
            <div class="flex flex-wrap gap-3">
              <label :for={{name, hex} <- vehicle_colors()} class="cursor-pointer" title={name}>
                <input
                  type="radio"
                  name="vehicle[color]"
                  value={name}
                  class="sr-only peer"
                  checked={@vehicle_form["color"] == name}
                />
                <span
                  class="block size-8 rounded-full border-2 border-base-300 peer-checked:border-cyan-500 peer-checked:ring-2 peer-checked:ring-cyan-500 transition"
                  style={"background-color: #{hex}"}
                >
                </span>
              </label>
            </div>
          </div>

          <div>
            <label class="text-sm font-semibold text-base-content mb-2 block">Vehicle type</label>
            <div class="grid grid-cols-1 sm:grid-cols-3 gap-2">
              <label class="cursor-pointer border border-base-300 rounded-lg p-3 hover:border-cyan-500 has-[:checked]:border-cyan-500 has-[:checked]:bg-cyan-500/15 transition-colors">
                <input
                  type="radio"
                  name="vehicle[size]"
                  value="car"
                  class="sr-only"
                  checked={@vehicle_form["size"] == "car"}
                />
                <div class="text-sm font-semibold">Car</div>
                <div class="text-xs text-base-content/60">Sedan, coupe, compact</div>
              </label>
              <label class="cursor-pointer border border-base-300 rounded-lg p-3 hover:border-cyan-500 has-[:checked]:border-cyan-500 has-[:checked]:bg-cyan-500/15 transition-colors">
                <input
                  type="radio"
                  name="vehicle[size]"
                  value="suv_van"
                  class="sr-only"
                  checked={@vehicle_form["size"] == "suv_van"}
                />
                <div class="text-sm font-semibold">SUV / Van</div>
                <div class="text-xs text-warning">+20% price</div>
              </label>
              <label class="cursor-pointer border border-base-300 rounded-lg p-3 hover:border-cyan-500 has-[:checked]:border-cyan-500 has-[:checked]:bg-cyan-500/15 transition-colors">
                <input
                  type="radio"
                  name="vehicle[size]"
                  value="pickup"
                  class="sr-only"
                  checked={@vehicle_form["size"] == "pickup"}
                />
                <div class="text-sm font-semibold">Pickup</div>
                <div class="text-xs text-warning">+50% price</div>
              </label>
            </div>
          </div>

          <input type="hidden" name="vehicle[vin]" value={@vehicle_form["vin"]} />
          <input type="hidden" name="vehicle[body_class]" value={@vehicle_form["body_class"]} />

          <button type="submit" class="btn btn-primary w-full">Save vehicle</button>
        </form>
```

- [ ] **Step 6: Add the `vehicle_form_change` and `decode_vin` handlers**

In `lib/mobile_car_wash_web/live/booking_live.ex`, add these handlers next to the existing `save_vehicle` / `select_vehicle` handlers (~line 905-965):

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

    {:noreply, assign(socket, vehicle_form: form, vehicle_models: models)}
  end

  def handle_event("decode_vin", %{"vin" => vin}, socket) do
    vin = vin |> String.trim() |> String.upcase()

    case NhtsaClient.decode_vin(vin) do
      {:ok, decoded} ->
        models =
          case NhtsaClient.models_for_make_year(decoded.make, decoded.year) do
            {:ok, m} -> m
            _ -> []
          end

        # Ensure the decoded model is selectable even if it isn't in the list
        models =
          if decoded.model && decoded.model != "" && decoded.model not in models,
            do: [decoded.model | models],
            else: models

        form = %{
          "make" => decoded.make,
          "year" => to_string(decoded.year),
          "model" => decoded.model || "",
          "color" => socket.assigns.vehicle_form["color"],
          "size" => to_string(decoded.size),
          "vin" => vin,
          "body_class" => decoded.body_class || ""
        }

        {:noreply, assign(socket, vehicle_form: form, vehicle_models: models, vin_error: nil)}

      {:error, _reason} ->
        {:noreply,
         assign(socket,
           vin_error: "Couldn't read that VIN — enter your vehicle below."
         )}
    end
  end
```

- [ ] **Step 7: Extend `save_vehicle` to persist vin/body_class**

In the existing `save_vehicle` handler (~line 917), change `allowed_vehicle_keys` and add normalization for the two new fields. Replace:

```elixir
    allowed_vehicle_keys = ~w(make model year color size)

    attrs =
      vehicle_params
      |> Map.take(allowed_vehicle_keys)
      |> Map.new(fn {k, v} -> {String.to_existing_atom(k), v} end)
      |> Map.update(:year, nil, fn v ->
        if is_binary(v) and v != "", do: String.to_integer(v), else: nil
      end)
```

with:

```elixir
    allowed_vehicle_keys = ~w(make model year color size vin body_class)

    attrs =
      vehicle_params
      |> Map.take(allowed_vehicle_keys)
      |> Map.new(fn {k, v} -> {String.to_existing_atom(k), v} end)
      |> Map.update(:year, nil, fn v ->
        if is_binary(v) and v != "", do: String.to_integer(v), else: nil
      end)
      |> Map.update(:vin, nil, fn v -> if v in ["", nil], do: nil, else: v end)
      |> Map.update(:body_class, nil, fn v -> if v in ["", nil], do: nil, else: v end)
```

Leave the rest of the handler (the `Ash.Changeset.for_create`, `force_change_attribute(:customer_id, ...)`, success/error branches) unchanged.

- [ ] **Step 8: Add the `vehicle_years/0` and `vehicle_colors/0` helpers**

Add these private helpers near the other private helpers at the bottom of the module:

```elixir
  defp vehicle_years do
    current = Date.utc_today().year + 1
    Enum.to_list(current..1990//-1)
  end

  defp vehicle_colors do
    [
      {"Black", "#1a1a1a"},
      {"White", "#f5f5f5"},
      {"Silver", "#c0c0c0"},
      {"Gray", "#808080"},
      {"Red", "#c0392b"},
      {"Blue", "#2563eb"},
      {"Green", "#16a34a"},
      {"Tan", "#d2b48c"}
    ]
  end
```

- [ ] **Step 9: Run the vehicle-step test to verify it passes**

Run: `MIX_ENV=test mix test test/mobile_car_wash_web/live/booking_vehicle_step_test.exs`
Expected: PASS (5 tests).

- [ ] **Step 10: Run the booking regression tests**

Run: `MIX_ENV=test mix test test/mobile_car_wash_web/live/`
Expected: PASS — confirm the existing add-ons, price-header, and subscription-price tests still pass with the reworked vehicle step.

- [ ] **Step 11: Commit**

```bash
git add lib/mobile_car_wash_web/live/booking_live.ex test/mobile_car_wash_web/live/booking_vehicle_step_test.exs
git commit -m "feat: NHTSA dropdown + VIN-autofill vehicle step in booking flow"
```

---

## Final verification (run before declaring the phase done)

- [ ] **Full gate:** `mix precommit` is green (re-run `mix test --failed` once if a known flake appears).
- [ ] **Manual smoke (optional but recommended):** `PORT=4010 mix phx.server`, sign in as `customer@demo.com` / `Password123!`, start a booking, reach the vehicle step, confirm: makes dropdown populated, selecting make+year loads models, a real VIN autofills + auto-selects size, an invalid VIN shows the inline error without blocking, saving advances and the hero reflects the size multiplier.
- [ ] **Then** invoke `superpowers:finishing-a-development-branch` to merge. Per the repo convention, **stash `config/dev.exs`, `AGENTS.md`, `docs/customer-flows.html` before merging and pop after**, and do **not** push unless the user asks.

---

## Self-review notes (author)

- **Spec coverage (§4.4, §6a):** Make→Year→Model dropdowns (Task 4) ✓; VIN typed shortcut + autofill + body-class→size (Tasks 2+4) ✓; curated popular makes (Task 2) ✓; models keyed by make+year (Task 2) ✓; makes/models caching ~30d TTL (Task 1) ✓; mockable server-side `Req` client (Task 2) ✓; color swatches → existing free-text `color` (Task 4) ✓; size auto-selected-but-editable (Task 4) ✓; `Vehicle` optional `vin`+`body_class`, `size` stays pricing driver (Task 3) ✓; saved-vehicle chips retained (untouched existing UI) ✓; error fallbacks "never block manual entry" (Task 4 VIN error test) ✓.
- **Deliberately deferred (not in this phase):** camera/OCR VIN scan (decided: typed-VIN only); `GetAllMakes` "more" fallback (curated list only); dollar-precise live size impact on the hero pre-save (size still drives the hero on save via existing `assign_price_breakdown`; buttons show the +20%/+50% labels). These match the agreed scope; surface to the user if broader coverage is wanted.
- **Type consistency:** `decode_vin/1` return map keys (`make/model/year/body_class/size`) are produced identically in the client (Task 2) and consumed in `decode_vin` handler (Task 4); mock implements the same `decode_vin/1` + `models_for_make_year/2` contract; `body_class_to_size/1` returns the same `:car|:suv_van|:pickup` atoms the `Vehicle.size` constraint accepts.
