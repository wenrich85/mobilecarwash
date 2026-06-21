# Geocoder Address Autocomplete + Confirmation Map Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the booking flow's manual-only address section with as-you-type address autocomplete (geocoder-backed), autofilling street/city/state/zip + coordinates, showing the service zone, and confirming the location on a Leaflet map — manual entry kept as a fallback.

**Architecture:** A new mockable server-side `Fleet.GeocoderClient` (US Census default, Photon/OSM fallback) mirrors the existing `Vehicles.NhtsaClient` pattern. The address section of `BookingLive` gains a debounced typeahead that calls the geocoder via `start_async` (mirroring the vehicle model loader), renders suggestions, and on selection autofills the address, resolves the zone from the ZIP, and drops a pin on a new lightweight `AddressMap` Leaflet hook. Geocoded coordinates are persisted to the `Address` record (columns already exist).

**Tech Stack:** Elixir/Phoenix LiveView, Ash, `Req` (server-side HTTP), ETS-backed test mocks, Leaflet (CDN, on-demand), DaisyUI/Tailwind.

## Global Constraints

- **TDD mandatory.** Every task: failing test → minimal implementation → green.
- **No network in tests.** All third-party calls go through a mockable client swapped via `config :mobile_car_wash, :<name>_client`; tests stage canned responses. Mirror `Vehicles.NhtsaClient` / `NhtsaClientMock` exactly.
- **Server-side only, no client keys.** Geocoding is proxied through the server via `Req`; CSP/`connect-src` is unchanged. (Leaflet tiles already allowed in CSP.)
- **Server-authoritative pricing/payment unchanged.** Do not touch `Booking.create_booking/1` or the Stripe path.
- **Zone = ZIP lookup.** Service-area membership is defined by `MobileCarWash.Zones.zone_for_zip/1` (the curated ZIP→quadrant map). `nil` zone = outside the service area. Do **not** use `zone_for_coordinates/2` for service-area determination — it returns a geometric quadrant for *any* coordinates and would wrongly mark out-of-area addresses as in-area.
- **Run focused tests:** `MIX_ENV=test mix test path/to/test.exs`. Full gate: `mix precommit`.
- **Format before commit.** Subagents don't auto-run `mix format`; run `mix format` before each commit (the precommit format step otherwise leaves uncommitted reflows).
- **Branch:** all tasks land on `feature/booking-geocoder-address` (off `main`). Do not push.

---

### Task 1: `Fleet.GeocoderClient` + mock + test wiring

**Files:**
- Create: `lib/mobile_car_wash/fleet/geocoder_client.ex`
- Create: `test/support/geocoder_client_mock.ex`
- Create: `test/mobile_car_wash/fleet/geocoder_client_test.exs`
- Modify: `config/test.exs:42` (add `:geocoder_client` config right after the `:nhtsa_client` line)

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces:
  - `MobileCarWash.Fleet.GeocoderClient.suggest(query :: String.t()) :: {:ok, [suggestion]} | {:error, term()}` where `suggestion :: %{label: String.t(), street: String.t(), city: String.t(), state: String.t(), zip: String.t(), lat: float(), lng: float()}`. Delegates to the configured mock in test env.
  - `MobileCarWash.Fleet.GeocoderClientMock.init/0`, `put_suggestions(query, [suggestion])`, `put_error(query, reason)`, `suggest(query)`.

- [ ] **Step 1: Write the failing test**

Create `test/mobile_car_wash/fleet/geocoder_client_test.exs`:

```elixir
defmodule MobileCarWash.Fleet.GeocoderClientTest do
  use ExUnit.Case, async: false

  alias MobileCarWash.Fleet.GeocoderClient
  alias MobileCarWash.Fleet.GeocoderClientMock

  setup do
    GeocoderClientMock.init()
    :ok
  end

  test "suggest/1 delegates to the configured mock and returns staged matches" do
    staged = [
      %{
        label: "123 MAIN ST, SAN ANTONIO, TX, 78261",
        street: "123 MAIN ST",
        city: "SAN ANTONIO",
        state: "TX",
        zip: "78261",
        lat: 29.65,
        lng: -98.42
      }
    ]

    GeocoderClientMock.put_suggestions("123 main", staged)

    assert {:ok, ^staged} = GeocoderClient.suggest("123 main")
  end

  test "suggest/1 returns {:ok, []} for an unstaged query" do
    assert {:ok, []} = GeocoderClient.suggest("nothing staged here")
  end

  test "suggest/1 surfaces staged errors" do
    GeocoderClientMock.put_error("boom", :timeout)
    assert {:error, :timeout} = GeocoderClient.suggest("boom")
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `MIX_ENV=test mix test test/mobile_car_wash/fleet/geocoder_client_test.exs`
Expected: FAIL — `MobileCarWash.Fleet.GeocoderClient.suggest/1 is undefined (module ... is not available)` (and the mock module missing).

- [ ] **Step 3: Create the mock**

Create `test/support/geocoder_client_mock.ex`:

```elixir
defmodule MobileCarWash.Fleet.GeocoderClientMock do
  @moduledoc """
  Test mock for `GeocoderClient`. Tests stage canned suggestions with
  `put_suggestions/2`; the client delegates here in test env so no geocoder
  network call is ever made. Backed by a named ETS table.

  Mirrors `Vehicles.NhtsaClientMock`.
  """
  @table :geocoder_mock

  def init do
    ensure_table()
    :ets.delete_all_objects(@table)
  end

  def put_suggestions(query, suggestions), do: insert({:suggest, query}, suggestions)

  def put_error(query, reason), do: insert({:suggest, query}, {:error, reason})

  def suggest(query) do
    case lookup({:suggest, query}) do
      {:ok, {:error, _} = err} -> err
      {:ok, suggestions} -> {:ok, suggestions}
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

- [ ] **Step 4: Create the client**

Create `lib/mobile_car_wash/fleet/geocoder_client.ex`:

```elixir
defmodule MobileCarWash.Fleet.GeocoderClient do
  @moduledoc """
  Address autocomplete / geocoding via Req. Server-side only; no client keys.

  Default provider: US Census onelineaddress geocoder (free, no key, US-only).
  Falls back to Photon (OSM) when Census errors or returns no matches.

  Mockable in tests via `config :mobile_car_wash, :geocoder_client` so
  suggestions never hit the network. Mirrors `Vehicles.NhtsaClient`.
  """
  require Logger

  @census "https://geocoding.geo.census.gov/geocoder/locations/onelineaddress"
  @photon "https://photon.komoot.io/api"

  @type suggestion :: %{
          label: String.t(),
          street: String.t(),
          city: String.t(),
          state: String.t(),
          zip: String.t(),
          lat: float(),
          lng: float()
        }

  @doc """
  Address suggestions for a free-text query. Returns up to a handful of
  matches, or `{:ok, []}` when nothing matches. Never raises on network error.
  """
  @spec suggest(String.t()) :: {:ok, [suggestion()]} | {:error, term()}
  def suggest(query) do
    case client_module() do
      __MODULE__ -> do_suggest(query)
      mock -> mock.suggest(query)
    end
  end

  defp do_suggest(query) do
    case census_suggest(query) do
      {:ok, []} -> photon_suggest(query)
      {:ok, results} -> {:ok, results}
      {:error, _} -> photon_suggest(query)
    end
  end

  # --- US Census ---
  defp census_suggest(query) do
    params = [address: query, benchmark: "Public_AR_Current", format: "json"]

    case Req.get(@census, params: params) do
      {:ok, %{status: 200, body: %{"result" => %{"addressMatches" => matches}}}}
      when is_list(matches) ->
        {:ok, matches |> Enum.map(&census_match/1) |> Enum.reject(&is_nil/1)}

      {:ok, %{status: status}} ->
        Logger.error("Census geocoder error #{status}")
        {:error, {:census_error, status}}

      {:error, reason} ->
        Logger.error("Census geocoder request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp census_match(%{
         "matchedAddress" => matched,
         "coordinates" => %{"x" => lng, "y" => lat},
         "addressComponents" => comp
       })
       when is_number(lat) and is_number(lng) do
    street =
      matched
      |> to_string()
      |> String.split(",")
      |> List.first()
      |> to_string()
      |> String.trim()

    %{
      label: matched,
      street: street,
      city: comp["city"] || "",
      state: comp["state"] || "",
      zip: comp["zip"] || "",
      lat: lat * 1.0,
      lng: lng * 1.0
    }
  end

  defp census_match(_), do: nil

  # --- Photon (OSM) fallback ---
  defp photon_suggest(query) do
    params = [q: query, limit: 5]

    case Req.get(@photon, params: params) do
      {:ok, %{status: 200, body: %{"features" => features}}} when is_list(features) ->
        {:ok, features |> Enum.map(&photon_feature/1) |> Enum.reject(&is_nil/1)}

      {:ok, %{status: status}} ->
        Logger.error("Photon geocoder error #{status}")
        {:error, {:photon_error, status}}

      {:error, reason} ->
        Logger.error("Photon geocoder request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp photon_feature(%{
         "geometry" => %{"coordinates" => [lng, lat]},
         "properties" => props
       })
       when is_number(lat) and is_number(lng) do
    street =
      [props["housenumber"], props["street"] || props["name"]]
      |> Enum.reject(&(is_nil(&1) or &1 == ""))
      |> Enum.join(" ")

    %{
      label: photon_label(street, props),
      street: street,
      city: props["city"] || "",
      state: props["state"] || "",
      zip: props["postcode"] || "",
      lat: lat * 1.0,
      lng: lng * 1.0
    }
  end

  defp photon_feature(_), do: nil

  defp photon_label(street, props) do
    [street, props["city"], props["state"], props["postcode"]]
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> Enum.join(", ")
  end

  defp client_module do
    Application.get_env(:mobile_car_wash, :geocoder_client, __MODULE__)
  end
end
```

- [ ] **Step 5: Wire the mock into the test config**

In `config/test.exs`, immediately after the existing `:nhtsa_client` line (line 42), add:

```elixir
# Use the ETS-backed mock geocoder in tests so address autocomplete never
# hits the network.
config :mobile_car_wash, :geocoder_client, MobileCarWash.Fleet.GeocoderClientMock
```

- [ ] **Step 6: Run test to verify it passes**

Run: `MIX_ENV=test mix test test/mobile_car_wash/fleet/geocoder_client_test.exs`
Expected: PASS (3 tests, 0 failures).

- [ ] **Step 7: Format and commit**

```bash
mix format
git add lib/mobile_car_wash/fleet/geocoder_client.ex test/support/geocoder_client_mock.ex test/mobile_car_wash/fleet/geocoder_client_test.exs config/test.exs
git commit -m "feat: add mockable Fleet.GeocoderClient (Census + Photon)"
```

---

### Task 2: Shared Leaflet loader + `AddressMap` hook

**Files:**
- Create: `assets/js/hooks/leaflet_loader.js`
- Modify: `assets/js/hooks/dispatch_map.js:1-28` (replace the inline `let L`/`loadLeaflet()` with an import of the shared loader)
- Create: `assets/js/hooks/address_map.js`
- Modify: `assets/js/app.js:45,53` (import + register `AddressMap`)

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: a LiveView JS hook named `"AddressMap"` registered in the socket's `hooks`. It reads `data-lat` / `data-lng` from its element to place an initial marker, and listens for a pushed `"address_map_set"` event (`%{lat, lng}`) to recenter and move the marker. Task 3 renders the `phx-hook="AddressMap"` element and pushes `"address_map_set"`.

> **Note (deviation from spec wording):** Spec §4.3 says "drop a Leaflet pin via the existing DispatchMap hook." DispatchMap auto-requests fleet pins on mount (`request_map_pins`) and expects richly-typed dispatch pins. Rather than overload it, this task adds a small dedicated `AddressMap` hook and extracts the shared CDN loader so both hooks stay DRY and use the same (already CSP-allowed) Leaflet/OSM assets. No behavioral change to DispatchMap.

> **No JS unit tests in this repo.** The behavioral assertion (hook element + data attributes present) lands in Task 3's LiveView test. This task's gate is `mix assets.build` compiling cleanly and the dispatch map continuing to work.

- [ ] **Step 1: Extract the shared loader**

Create `assets/js/hooks/leaflet_loader.js` (copied verbatim from the current `dispatch_map.js` loader, now exported):

```js
// Leaflet loaded on demand via CDN — keeps it out of the main JS bundle.
// Shared by DispatchMap (fleet) and AddressMap (booking).
let L = null

export function loadLeaflet() {
  return new Promise((resolve) => {
    if (L) { resolve(L); return }
    if (window.L) { L = window.L; resolve(L); return }

    // Load CSS
    if (!document.getElementById("leaflet-css")) {
      const link = document.createElement("link")
      link.id = "leaflet-css"
      link.rel = "stylesheet"
      link.href = "https://unpkg.com/leaflet@1.9.4/dist/leaflet.css"
      link.integrity = "sha256-p4NxAoJBhIIN+hmNHrzRCf9tD/miZyoHS5obTRR9BMY="
      link.crossOrigin = ""
      document.head.appendChild(link)
    }

    // Load JS from CDN
    const script = document.createElement("script")
    script.src = "https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"
    script.integrity = "sha256-20nQCchB9co0qIjJZRGuk2/Z9VM+kNiyxNV1lvTlZBo="
    script.crossOrigin = ""
    script.onload = () => { L = window.L; resolve(L) }
    document.head.appendChild(script)
  })
}
```

- [ ] **Step 2: Point DispatchMap at the shared loader**

In `assets/js/hooks/dispatch_map.js`, replace lines 1–28 (the comment, `let L = null`, and the entire `function loadLeaflet() {...}`) with:

```js
// Leaflet loaded on demand via CDN — keeps it out of the main JS bundle (~148KB saved)
import { loadLeaflet } from "./leaflet_loader"

let L = null
```

Leave the rest of the file unchanged — `mounted()` still does `L = await loadLeaflet()`, which populates this module's local `L` used by `vehicleIcon`/`renderPins`.

- [ ] **Step 3: Create the AddressMap hook**

Create `assets/js/hooks/address_map.js`:

```js
import { loadLeaflet } from "./leaflet_loader"

const SA_CENTER = [29.4241, -98.4936]

export const AddressMap = {
  async mounted() {
    const L = await loadLeaflet()
    this._L = L

    const lat = parseFloat(this.el.dataset.lat)
    const lng = parseFloat(this.el.dataset.lng)
    const hasPoint = !Number.isNaN(lat) && !Number.isNaN(lng)
    const center = hasPoint ? [lat, lng] : SA_CENTER

    this.map = L.map(this.el, { scrollWheelZoom: false, zoomControl: true })
      .setView(center, hasPoint ? 15 : 11)

    L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
      attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>',
      maxZoom: 18,
    }).addTo(this.map)

    if (hasPoint) this.marker = L.marker(center).addTo(this.map)

    this.handleEvent("address_map_set", ({ lat, lng }) => {
      const p = [lat, lng]
      this.map.setView(p, 15)
      if (this.marker) this.marker.setLatLng(p)
      else this.marker = this._L.marker(p).addTo(this.map)
    })

    setTimeout(() => this.map.invalidateSize(), 200)
  },

  destroyed() {
    if (this.map) this.map.remove()
  },
}
```

- [ ] **Step 4: Register the hook in app.js**

In `assets/js/app.js`, after the existing DispatchMap import (line 45) add:

```js
import {AddressMap} from "./hooks/address_map"
```

Then add `AddressMap` to the `hooks` object (line 53):

```js
  hooks: {...colocatedHooks, Sortable, DispatchMap, AddressMap, ClipboardCopy, PriceCountUp},
```

- [ ] **Step 5: Verify the assets build**

Run: `mix assets.build`
Expected: completes with no errors (esbuild resolves the new imports).

- [ ] **Step 6: Commit**

```bash
git add assets/js/hooks/leaflet_loader.js assets/js/hooks/dispatch_map.js assets/js/hooks/address_map.js assets/js/app.js
git commit -m "feat: add AddressMap Leaflet hook; share CDN loader with DispatchMap"
```

---

### Task 3: Address section rework — typeahead → autofill → zone → map

**Files:**
- Modify: `lib/mobile_car_wash_web/live/booking_live.ex` — add 3 assigns at mount; replace the address section render (lines ~435–515); add `address_search` / `select_suggestion` event handlers; add `:geocode_suggest` async callbacks; add the `choose_geocoded_address/3` helper; add `GeocoderClient` to the `Fleet` alias.
- Test: `test/mobile_car_wash_web/live/booking_single_page_test.exs` — add geocoder typeahead tests.

**Interfaces:**
- Consumes: `MobileCarWash.Fleet.GeocoderClient.suggest/1` (Task 1); the `"AddressMap"` hook + `"address_map_set"` event (Task 2).
- Produces: a `selected_address` (in-memory `%Address{id: nil}` for guests, or a persisted `%Address{}` for signed-in users) carrying `latitude`/`longitude`/`zone`. Task 4 relies on guest `selected_address` holding `:latitude`/`:longitude`.

- [ ] **Step 1: Write the failing tests**

In `test/mobile_car_wash_web/live/booking_single_page_test.exs`, add the mock alias near the top aliases (after line 8):

```elixir
  alias MobileCarWash.Fleet.GeocoderClientMock
```

Then add these two tests (anywhere among the existing tests):

```elixir
  test "typing an address shows geocoder suggestions", %{conn: conn} do
    GeocoderClientMock.init()

    GeocoderClientMock.put_suggestions("123 main st san antonio", [
      %{
        label: "123 MAIN ST, SAN ANTONIO, TX, 78261",
        street: "123 MAIN ST",
        city: "SAN ANTONIO",
        state: "TX",
        zip: "78261",
        lat: 29.6512,
        lng: -98.4187
      }
    ])

    {:ok, view, _} = live(conn, "/book")

    render_hook(view, "address_search", %{"q" => "123 main st san antonio"})
    html = render_async(view)

    assert html =~ "123 MAIN ST, SAN ANTONIO, TX, 78261"
  end

  test "selecting a suggestion autofills the address, shows the zone, and mounts the map",
       %{conn: conn} do
    GeocoderClientMock.init()

    GeocoderClientMock.put_suggestions("123 main st san antonio", [
      %{
        label: "123 MAIN ST, SAN ANTONIO, TX, 78261",
        street: "123 MAIN ST",
        city: "SAN ANTONIO",
        state: "TX",
        zip: "78261",
        lat: 29.6512,
        lng: -98.4187
      }
    ])

    {:ok, view, _} = live(conn, "/book")

    render_hook(view, "address_search", %{"q" => "123 main st san antonio"})
    render_async(view)

    html = render_click(view, "select_suggestion", %{"index" => "0"})

    # Autofilled summary
    assert html =~ "123 MAIN ST"
    # ZIP 78261 is in the curated map → :ne → "Northeast", in service area
    assert html =~ "In service area"
    assert html =~ "Northeast"
    # Confirmation map mounted with the geocoded coordinates
    assert html =~ ~s(phx-hook="AddressMap")
    assert html =~ ~s(data-lat="29.6512")
  end

  test "selecting a suggestion outside the service area warns but is allowed", %{conn: conn} do
    GeocoderClientMock.init()

    GeocoderClientMock.put_suggestions("1 elsewhere rd", [
      %{
        label: "1 ELSEWHERE RD, AUSTIN, TX, 73301",
        street: "1 ELSEWHERE RD",
        city: "AUSTIN",
        state: "TX",
        zip: "73301",
        lat: 30.2672,
        lng: -97.7431
      }
    ])

    {:ok, view, _} = live(conn, "/book")

    render_hook(view, "address_search", %{"q" => "1 elsewhere rd"})
    render_async(view)

    html = render_click(view, "select_suggestion", %{"index" => "0"})

    # ZIP 73301 not in curated map → zone nil → outside-area warning
    assert html =~ "Outside our service area"
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `MIX_ENV=test mix test test/mobile_car_wash_web/live/booking_single_page_test.exs`
Expected: the three new tests FAIL — `address_search`/`select_suggestion` handlers undefined (event not handled), and `phx-hook="AddressMap"` absent from the rendered HTML.

- [ ] **Step 3: Add the alias and mount assigns**

In `lib/mobile_car_wash_web/live/booking_live.ex`, add `GeocoderClient` to the existing Fleet alias. Find the alias that brings in `Vehicle`/`Address` (e.g. `alias MobileCarWash.Fleet.{Address, Vehicle}`) and extend it:

```elixir
  alias MobileCarWash.Fleet.{Address, GeocoderClient, Vehicle}
```

(If `GeocoderClient` is already alphabetized differently, just ensure `GeocoderClient` is included in the `Fleet` alias group.)

In `mount/3`, add three assigns alongside the existing address assigns (near `existing_addresses: []` / `show_new_address_form: false`):

```elixir
        address_query: "",
        address_suggestions: [],
        loading_suggestions: false,
```

- [ ] **Step 4: Replace the address section render**

Replace the entire address `<.booking_section id="section-address" ...>...</.booking_section>` block (currently lines ~435–515) with:

```elixir
      <.booking_section
        id="section-address"
        index={4}
        title="Service location"
        status={BookingSections.status(:address, build_context(assigns))}
      >
        <p class="text-sm text-base-content/60 mb-4">
          Start typing your address and pick a match, or enter it manually.
        </p>

        <%!-- Saved addresses (signed-in customers) --%>
        <div :if={@existing_addresses != []} class="space-y-3 mb-6">
          <.saved_record_card
            :for={addr <- @existing_addresses}
            title={addr.street}
            subtitle={"#{addr.city}, #{addr.state} #{addr.zip}"}
            selected={@selected_address && @selected_address.id == addr.id}
            phx-click="select_address"
            phx-value-id={addr.id}
          />
        </div>

        <%!-- Address typeahead --%>
        <form phx-change="address_search" autocomplete="off" class="mb-2">
          <.input
            name="q"
            type="text"
            value={@address_query}
            label="Search address"
            placeholder="123 Main St, San Antonio"
            phx-debounce="250"
          />
        </form>

        <div :if={@loading_suggestions} class="text-xs text-base-content/50 mb-2">
          Searching…
        </div>

        <ul
          :if={@address_suggestions != []}
          class="menu bg-base-100 border border-base-300 rounded-box mb-4 p-1 w-full"
        >
          <li :for={{s, i} <- Enum.with_index(@address_suggestions)}>
            <button
              type="button"
              phx-click="select_suggestion"
              phx-value-index={i}
              class="text-left"
            >
              {s.label}
            </button>
          </li>
        </ul>

        <%!-- Manual entry fallback --%>
        <details class="mb-4">
          <summary class="text-sm text-primary cursor-pointer">Enter address manually</summary>
          <form
            phx-submit="save_address"
            class="bg-base-100 border border-base-300 rounded-box p-5 space-y-3 mt-3"
          >
            <.input
              name="address[street]"
              type="text"
              label="Street address"
              placeholder="123 Main St"
              required
            />
            <div class="grid grid-cols-1 sm:grid-cols-3 gap-3">
              <.input name="address[city]" type="text" label="City" placeholder="San Antonio" required />
              <.input name="address[state]" type="text" label="State" value="TX" required />
              <.input name="address[zip]" type="text" label="ZIP" placeholder="78261" required />
            </div>
            <button type="submit" class="btn btn-primary w-full">Save address</button>
          </form>
        </details>

        <%!-- Selected address summary --%>
        <div
          :if={@selected_address}
          class="flex items-center justify-between rounded-box border border-base-300 bg-base-100 p-4 mb-4"
        >
          <div class="text-sm font-semibold">
            {@selected_address.street}, {@selected_address.city} {@selected_address.state} {@selected_address.zip}
          </div>
        </div>

        <%!-- Confirmation map (only once we have coordinates) --%>
        <div
          :if={@selected_address && @selected_address.latitude && @selected_address.longitude}
          id="address-map"
          phx-hook="AddressMap"
          phx-update="ignore"
          data-lat={@selected_address.latitude}
          data-lng={@selected_address.longitude}
          class="h-56 w-full rounded-box border border-base-300 mb-4 z-0"
        >
        </div>

        <%!-- Zone banner --%>
        <div
          :if={@selected_address && @selected_address.zone}
          class="bg-success/10 border border-success/30 rounded-lg p-3 mb-4 text-sm text-success"
        >
          ✓ In service area · <strong>{MobileCarWash.Zones.label(@selected_address.zone)}</strong>
        </div>

        <div
          :if={@selected_address && is_nil(@selected_address.zone)}
          class="bg-warning/10 border border-warning/30 rounded-lg p-3 mb-4 text-sm text-warning"
        >
          ⚠ Outside our service area — we'll confirm or refund.
        </div>
      </.booking_section>
```

- [ ] **Step 5: Add the event handlers**

Add these two handlers near the other address handlers (after `select_address`, ~line 989):

```elixir
  def handle_event("address_search", %{"q" => q}, socket) do
    q = String.trim(q)

    if String.length(q) < 4 do
      {:noreply,
       assign(socket, address_query: q, address_suggestions: [], loading_suggestions: false)}
    else
      {:noreply,
       socket
       |> assign(address_query: q, loading_suggestions: true)
       |> start_async(:geocode_suggest, fn -> GeocoderClient.suggest(q) end)}
    end
  end

  def handle_event("select_suggestion", %{"index" => index}, socket) do
    prev_ctx = build_context(socket.assigns)

    case Enum.at(socket.assigns.address_suggestions, String.to_integer(index)) do
      nil ->
        {:noreply, socket}

      s ->
        socket = choose_geocoded_address(socket, s, prev_ctx)

        {:noreply,
         socket
         |> assign(address_suggestions: [], address_query: "", loading_suggestions: false)
         |> push_event("address_map_set", %{lat: s.lat, lng: s.lng})}
    end
  end
```

- [ ] **Step 6: Add the async callbacks**

Add next to the existing `handle_async(:load_models, ...)` clauses (~line 1191):

```elixir
  def handle_async(:geocode_suggest, {:ok, {:ok, suggestions}}, socket) do
    {:noreply, assign(socket, address_suggestions: suggestions, loading_suggestions: false)}
  end

  def handle_async(:geocode_suggest, {:ok, {:error, _reason}}, socket) do
    {:noreply, assign(socket, address_suggestions: [], loading_suggestions: false)}
  end

  def handle_async(:geocode_suggest, {:exit, _reason}, socket) do
    {:noreply, assign(socket, address_suggestions: [], loading_suggestions: false)}
  end
```

- [ ] **Step 7: Add the `choose_geocoded_address/3` helper**

Add to the private helpers section (near `persist_pending_address`, ~line 1281). Guests get an in-memory struct (persisted at Pay); signed-in users persist immediately with the geocoded coordinates:

```elixir
  # Guest: hold the geocoded address in-memory (persisted at Pay).
  defp choose_geocoded_address(%{assigns: %{current_customer: nil}} = socket, s, prev_ctx) do
    address =
      struct(Address, %{
        street: s.street,
        city: s.city,
        state: s.state,
        zip: s.zip,
        latitude: s.lat,
        longitude: s.lng,
        zone: MobileCarWash.Zones.zone_for_zip(s.zip)
      })

    socket
    |> assign(selected_address: address, show_new_address_form: false)
    |> persist_booking_state()
    |> maybe_scroll(prev_ctx)
  end

  # Signed-in: persist the geocoded address immediately (zone is set by the
  # Address resource's SetZoneFromZip change; coords are accepted as-is).
  defp choose_geocoded_address(socket, s, prev_ctx) do
    customer = socket.assigns.current_customer

    case Address
         |> Ash.Changeset.for_create(:create, %{
           street: s.street,
           city: s.city,
           state: s.state,
           zip: s.zip,
           latitude: s.lat,
           longitude: s.lng
         })
         |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
         |> Ash.create() do
      {:ok, address} ->
        socket
        |> assign(
          selected_address: address,
          existing_addresses: socket.assigns.existing_addresses ++ [address]
        )
        |> persist_booking_state()
        |> maybe_scroll(prev_ctx)

      {:error, _} ->
        put_flash(socket, :error, "Could not save that address. Please try manual entry.")
    end
  end
```

- [ ] **Step 8: Run tests to verify they pass**

Run: `MIX_ENV=test mix test test/mobile_car_wash_web/live/booking_single_page_test.exs`
Expected: PASS — all existing tests plus the three new ones (0 failures).

- [ ] **Step 9: Format and commit**

```bash
mix format
git add lib/mobile_car_wash_web/live/booking_live.ex test/mobile_car_wash_web/live/booking_single_page_test.exs
git commit -m "feat: geocoder address typeahead with autofill, zone banner, and confirmation map"
```

---

### Task 4: Persist geocoded coordinates for guest addresses

**Files:**
- Modify: `lib/mobile_car_wash_web/live/booking_live.ex` — `persist_pending_address/1` (~line 1267) to carry `:latitude`/`:longitude`.
- Test: `test/mobile_car_wash_web/live/booking_single_page_test.exs` — guest geocoded-address e2e asserting persisted coordinates.

**Interfaces:**
- Consumes: the guest in-memory `selected_address` with `:latitude`/`:longitude` from Task 3.
- Produces: a persisted `Address` whose `latitude`/`longitude` equal the geocoded values (not the ZIP centroid).

> **Why this is needed:** `persist_pending_address/1` currently does `Map.take(a, [:street, :city, :state, :zip])`, dropping the geocoded coordinates. The `Address` `:create` action's `AutoGeocodeFromZip` change only fills coords from the ZIP centroid *when the caller didn't supply them*, so without this change a guest's precise geocoded pin would be replaced by the coarse ZIP centroid on save.

- [ ] **Step 1: Write the failing test**

Add to `test/mobile_car_wash_web/live/booking_single_page_test.exs` (the `Ash.Query` and `Address`/`Customer` aliases are already imported; `GeocoderClientMock` was aliased in Task 3):

```elixir
  test "guest geocoded address persists the precise coordinates (not the ZIP centroid)",
       %{conn: conn} do
    GeocoderClientMock.init()

    # 78250 centroid in Zones is {29.5050, -98.6350}; stage distinct coords
    # so we can prove the precise geocoded point is what gets persisted.
    GeocoderClientMock.put_suggestions("789 pine st san antonio", [
      %{
        label: "789 PINE ST, SAN ANTONIO, TX, 78250",
        street: "789 PINE ST",
        city: "SAN ANTONIO",
        state: "TX",
        zip: "78250",
        lat: 29.5099,
        lng: -98.6399
      }
    ])

    service = ServiceType |> Ash.Query.filter(slug == "basic_wash") |> Ash.read!() |> hd()
    block = create_open_block(service)

    {:ok, view, _html} = live(conn, "/book")

    render_click(view, "select_service", %{"slug" => "basic_wash"})

    render_submit(view, "save_vehicle", %{
      "vehicle" => %{
        "make" => "Toyota",
        "model" => "Camry",
        "year" => "2022",
        "color" => "Silver",
        "size" => "car",
        "vin" => "",
        "body_class" => ""
      }
    })

    # Address via geocoder selection (not manual entry)
    render_hook(view, "address_search", %{"q" => "789 pine st san antonio"})
    render_async(view)
    render_click(view, "select_suggestion", %{"index" => "0"})

    block_date = block.starts_at |> DateTime.to_date() |> Date.to_string()
    render_click(view, "select_date", %{"date" => block_date})
    render_click(view, "select_block", %{"id" => block.id})

    guest_email = "guest-#{System.unique_integer([:positive])}@example.com"

    render_change(view, "guest_form_change", %{
      "guest" => %{"name" => "Geo Guest", "email" => guest_email, "phone" => "5125550133"}
    })

    assert {:error, {:redirect, %{to: _url}}} = render_click(view, "confirm_booking", %{})

    addresses =
      Address
      |> Ash.Query.filter(street == "789 PINE ST")
      |> Ash.read!(authorize?: false)

    assert length(addresses) == 1
    saved = hd(addresses)
    assert saved.zip == "78250"
    assert_in_delta saved.latitude, 29.5099, 0.0001
    assert_in_delta saved.longitude, -98.6399, 0.0001
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `MIX_ENV=test mix test test/mobile_car_wash_web/live/booking_single_page_test.exs -k "precise coordinates"`
Expected: FAIL — `saved.latitude` equals the ZIP centroid `29.505` (from `AutoGeocodeFromZip`), not `29.5099`.

- [ ] **Step 3: Carry coordinates through the persist path**

In `lib/mobile_car_wash_web/live/booking_live.ex`, update `persist_pending_address/1`'s `Map.take` to include the coordinate columns:

```elixir
    attrs = Map.take(a, [:street, :city, :state, :zip, :latitude, :longitude])
```

(The `Address` `:create` action already accepts `:latitude`/`:longitude`, and `AutoGeocodeFromZip` leaves caller-supplied coords untouched.)

- [ ] **Step 4: Run test to verify it passes**

Run: `MIX_ENV=test mix test test/mobile_car_wash_web/live/booking_single_page_test.exs -k "precise coordinates"`
Expected: PASS.

- [ ] **Step 5: Run the full booking LiveView test file**

Run: `MIX_ENV=test mix test test/mobile_car_wash_web/live/booking_single_page_test.exs`
Expected: PASS (all tests, 0 failures).

- [ ] **Step 6: Format and commit**

```bash
mix format
git add lib/mobile_car_wash_web/live/booking_live.ex test/mobile_car_wash_web/live/booking_single_page_test.exs
git commit -m "feat: persist geocoded coordinates for guest addresses"
```

---

## Final verification (after all tasks)

- [ ] Run the full gate: `mix precommit` (~5 min). Expected: 0 failures. (`photo_upload_test.exs` can flake under full-suite load — re-run it in isolation if it fails: `MIX_ENV=test mix test test/mobile_car_wash/operations/photo_upload_test.exs`.)
- [ ] Commit any `mix format` reflows as a separate `style:` commit if present.
- [ ] Manual smoke (optional): `PORT=4010 mix phx.server` → http://localhost:4010/book → select service + vehicle → type an address → pick a suggestion → confirm the map pin, autofill, and zone banner. Hard-refresh (Cmd+Shift+R) after the asset rebuild.
- [ ] Then `superpowers:finishing-a-development-branch`: stash the three convention files (`config/dev.exs`, `AGENTS.md`, `docs/customer-flows.html`), merge `feature/booking-geocoder-address` into `main` with `--no-ff`, restore the stash, delete the branch. Do not push.

---

## Self-review notes

- **Spec coverage:** §4.3 `GeocoderClient` (Census default + Photon fallback, mockable) → Task 1. Mock so tests never hit network → Task 1. Debounced typeahead → Task 3 (`phx-debounce="250"`). Autofill street/city/state/zip → Task 3. Store latitude/longitude → Task 3 (in-memory/immediate) + Task 4 (persist). Resolve zone via `Zones` → Task 3 (`zone_for_zip`). Leaflet pin via Leaflet/OSM (CSP unchanged) → Task 2 + Task 3. Manual entry + saved chips fallback → Task 3 (`<details>` + saved-record cards). Zone banner ✓/⚠ copy → Task 3. Async/non-blocking lookups → Task 3 (`start_async`/`handle_async`). §5 geocoder-down/no-match fallback to manual → Task 3 (manual `<details>` always available; empty suggestions just show nothing).
- **Deliberate deviation:** dedicated `AddressMap` hook instead of reusing `DispatchMap` (rationale in Task 2). Zone from ZIP only, not coordinates (rationale in Global Constraints).
- **Type consistency:** `suggestion` map keys (`label/street/city/state/zip/lat/lng`) are identical across the client, the mock, the async handler, `select_suggestion`, and all tests. The hook reads `data-lat`/`data-lng` and the `address_map_set` payload uses `%{lat, lng}` consistently.
