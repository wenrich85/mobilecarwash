# Landing Service Display Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render landing-page service cards from active services marked for landing display, while keeping `/book` as the full active service catalog.

**Architecture:** Add a `show_on_landing` boolean to `ServiceType` and use it only in `LandingLive`. Admin Settings writes the flag during service create/update. Booking remains unchanged except for a regression test proving it still ignores the landing-only flag.

**Tech Stack:** Phoenix LiveView, Ash Resource, AshPostgres migrations, Phoenix LiveViewTest, Tailwind/daisyUI classes already used in this app.

## Global Constraints

- Run `mix ecto.gen.migration add_show_on_landing_to_service_types` to create the migration timestamp.
- Use TDD: every production behavior change starts with a failing test.
- `/book` must continue showing every `active == true` service regardless of `show_on_landing`.
- The admin display option controls only the landing page.
- Use existing Phoenix/Ash patterns; do not add dependencies.
- Use `mix precommit` when done and fix any pending issues.

---

### Task 1: ServiceType Landing Display Flag

**Files:**
- Create: `priv/repo/migrations/<generated>_add_show_on_landing_to_service_types.exs`
- Modify: `lib/mobile_car_wash/scheduling/service_type.ex`
- Test: `test/mobile_car_wash/scheduling/service_type_landing_display_test.exs`

**Interfaces:**
- Consumes: existing `MobileCarWash.Scheduling.ServiceType` Ash resource.
- Produces: `ServiceType.show_on_landing :: boolean`, accepted by `:create` and `:update`.

- [ ] **Step 1: Write the failing resource test**

Create `test/mobile_car_wash/scheduling/service_type_landing_display_test.exs`:

```elixir
defmodule MobileCarWash.Scheduling.ServiceTypeLandingDisplayTest do
  use MobileCarWash.DataCase, async: true

  alias MobileCarWash.Scheduling.ServiceType

  test "service types can be created hidden from the landing page" do
    service =
      ServiceType
      |> Ash.Changeset.for_create(:create, %{
        name: "Fleet Wash",
        slug: "fleet_wash_#{System.unique_integer([:positive])}",
        description: "Bookable service that should not be marketed.",
        base_price_cents: 7500,
        duration_minutes: 60,
        show_on_landing: false
      })
      |> Ash.create!()

    assert service.active == true
    assert service.show_on_landing == false
  end

  test "service types can update landing page display independently of active state" do
    service =
      ServiceType
      |> Ash.Changeset.for_create(:create, %{
        name: "Visible Wash",
        slug: "visible_wash_#{System.unique_integer([:positive])}",
        description: "Starts visible.",
        base_price_cents: 6500,
        duration_minutes: 50
      })
      |> Ash.create!()

    updated =
      service
      |> Ash.Changeset.for_update(:update, %{show_on_landing: false})
      |> Ash.update!()

    assert updated.active == true
    assert updated.show_on_landing == false
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
mix test test/mobile_car_wash/scheduling/service_type_landing_display_test.exs
```

Expected: FAIL because `show_on_landing` is not an accepted or defined attribute.

- [ ] **Step 3: Generate and fill the migration**

Run:

```bash
mix ecto.gen.migration add_show_on_landing_to_service_types
```

Edit the generated migration:

```elixir
defmodule MobileCarWash.Repo.Migrations.AddShowOnLandingToServiceTypes do
  use Ecto.Migration

  def change do
    alter table(:service_types) do
      add :show_on_landing, :boolean, null: false, default: true
    end
  end
end
```

- [ ] **Step 4: Update the Ash resource**

In `lib/mobile_car_wash/scheduling/service_type.ex`, add the attribute inside `attributes do`:

```elixir
attribute :show_on_landing, :boolean do
  allow_nil?(false)
  default(true)
  public?(true)
end
```

Add `:show_on_landing` to the `accept([...])` list for both `create :create` and `update :update`.

- [ ] **Step 5: Run test to verify it passes**

Run:

```bash
mix test test/mobile_car_wash/scheduling/service_type_landing_display_test.exs
```

Expected: PASS.

- [ ] **Step 6: Commit task**

```bash
git add priv/repo/migrations lib/mobile_car_wash/scheduling/service_type.ex test/mobile_car_wash/scheduling/service_type_landing_display_test.exs
git commit -m "Add landing display flag to services"
```

---

### Task 2: Landing Page Renders Displayable Active Services

**Files:**
- Modify: `lib/mobile_car_wash_web/live/landing_live.ex`
- Modify: `test/mobile_car_wash_web/live/landing_live_test.exs`

**Interfaces:**
- Consumes: `ServiceType.show_on_landing`.
- Produces: landing pricing cards generated from `@services`, filtered to active and landing-visible services.

- [ ] **Step 1: Replace brittle landing tests with behavior tests**

In `test/mobile_car_wash_web/live/landing_live_test.exs`, update the service seeding helper so it creates unique slugs and accepts visibility:

```elixir
defp create_service(attrs) do
  defaults = %{
    name: "Test Service #{System.unique_integer([:positive])}",
    slug: "test_service_#{System.unique_integer([:positive])}",
    description: "A service for landing page tests.",
    base_price_cents: 5000,
    duration_minutes: 45,
    active: true,
    show_on_landing: true
  }

  MobileCarWash.Scheduling.ServiceType
  |> Ash.Changeset.for_create(:create, Map.merge(defaults, attrs))
  |> Ash.create!()
end
```

Replace the existing pricing test with:

```elixir
test "renders every active service marked for landing display", %{conn: conn} do
  create_service(%{
    name: "Basic Wash",
    slug: "basic_wash_#{System.unique_integer([:positive])}",
    base_price_cents: 5000,
    duration_minutes: 45,
    show_on_landing: true
  })

  create_service(%{
    name: "Deep Clean & Detail",
    slug: "deep_clean_#{System.unique_integer([:positive])}",
    base_price_cents: 20_000,
    duration_minutes: 120,
    show_on_landing: true
  })

  {:ok, _lv, html} = live(conn, ~p"/")

  assert html =~ "Basic Wash"
  assert html =~ "$50"
  assert html =~ "Deep Clean &amp; Detail"
  assert html =~ "$200"
  refute html =~ "Two tiers"
end
```

Add a second test:

```elixir
test "does not render active services hidden from landing display", %{conn: conn} do
  create_service(%{
    name: "Private Fleet Wash",
    slug: "private_fleet_wash_#{System.unique_integer([:positive])}",
    base_price_cents: 7500,
    duration_minutes: 60,
    active: true,
    show_on_landing: false
  })

  {:ok, _lv, html} = live(conn, ~p"/")

  refute html =~ "Private Fleet Wash"
  refute html =~ "$75"
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
mix test test/mobile_car_wash_web/live/landing_live_test.exs
```

Expected: FAIL because hidden services still load or dynamically created non-magic slugs do not render.

- [ ] **Step 3: Filter landing services by the new flag**

In `LandingLive.mount/3` and `handle_info(:services_updated, socket)`, replace the service query with:

```elixir
services =
  ServiceType
  |> Ash.Query.filter(active == true and show_on_landing == true)
  |> Ash.read!()
  |> Enum.sort_by(& &1.base_price_cents)
```

- [ ] **Step 4: Render service cards from the list**

In `LandingLive.render/1`, remove the `basic` and `premium` assignments and replace the pricing card section with:

```elixir
<section id="pricing" class="bg-base-200 py-12 px-4">
  <div class="max-w-5xl mx-auto">
    <div class="text-center mb-8">
      <div class="text-xs font-semibold uppercase tracking-wide text-base-content/60 mb-1">
        SERVICES
      </div>
      <h2 class="text-2xl font-bold text-base-content tracking-tight">
        Choose the detail that fits today.
      </h2>
    </div>
    <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
      <.service_tier_card
        :for={service <- @services}
        name={service.name}
        price={"$#{format_price(service.base_price_cents)}"}
        duration={"~#{service.duration_minutes} min"}
        features={service_features(service)}
      >
        <:cta>
          <.link navigate={~p"/book?service=#{service.slug}"} class="btn btn-primary w-full">
            Book {service.name}
          </.link>
        </:cta>
      </.service_tier_card>
    </div>
  </div>
</section>
```

Add private helpers near `local_business_schema/1`:

```elixir
defp format_price(cents) when is_integer(cents) do
  cents
  |> Decimal.new()
  |> Decimal.div(100)
  |> Decimal.round(2)
  |> Decimal.normalize()
  |> Decimal.to_string(:normal)
end

defp service_features(service) do
  service.description
  |> to_string()
  |> String.split(~r/\.\s*/, trim: true)
  |> Enum.reject(&(&1 == ""))
  |> case do
    [] -> ["Professional mobile detailing at your location"]
    features -> features
  end
end
```

- [ ] **Step 5: Run landing tests to verify they pass**

Run:

```bash
mix test test/mobile_car_wash_web/live/landing_live_test.exs
```

Expected: PASS.

- [ ] **Step 6: Commit task**

```bash
git add lib/mobile_car_wash_web/live/landing_live.ex test/mobile_car_wash_web/live/landing_live_test.exs
git commit -m "Render landing services from catalog"
```

---

### Task 3: Admin Service Display Control

**Files:**
- Modify: `lib/mobile_car_wash_web/live/admin/settings_live.ex`
- Test: `test/mobile_car_wash_web/live/admin/settings_live_test.exs`

**Interfaces:**
- Consumes: `ServiceType.show_on_landing`.
- Produces: Admin create/update forms can set `show_on_landing`.

- [ ] **Step 1: Add focused admin handler tests**

Append tests to `test/mobile_car_wash_web/live/admin/settings_live_test.exs` that exercise the same parsing used by handlers through the resource if admin auth helpers are not available in this file:

```elixir
describe "service landing display option" do
  test "service create params can set show_on_landing to false" do
    attrs = %{
      name: "Admin Hidden Service",
      slug: "admin_hidden_service_#{System.unique_integer([:positive])}",
      description: "Created from admin intent.",
      base_price_cents: 12_300,
      duration_minutes: 70,
      active: true,
      show_on_landing: false
    }

    service =
      MobileCarWash.Scheduling.ServiceType
      |> Ash.Changeset.for_create(:create, attrs)
      |> Ash.create!()

    assert service.show_on_landing == false
    assert service.active == true
  end

  test "service update params can set show_on_landing to true" do
    service =
      MobileCarWash.Scheduling.ServiceType
      |> Ash.Changeset.for_create(:create, %{
        name: "Admin Update Service",
        slug: "admin_update_service_#{System.unique_integer([:positive])}",
        description: "Starts hidden.",
        base_price_cents: 9300,
        duration_minutes: 55,
        active: true,
        show_on_landing: false
      })
      |> Ash.create!()

    updated =
      service
      |> Ash.Changeset.for_update(:update, %{show_on_landing: true})
      |> Ash.update!()

    assert updated.show_on_landing == true
  end
end
```

- [ ] **Step 2: Run test to verify it fails if Task 1 is not complete**

Run:

```bash
mix test test/mobile_car_wash_web/live/admin/settings_live_test.exs
```

Expected after Task 1: PASS for resource behavior. If it already passes, proceed to UI changes because Task 3 also requires admin template support.

- [ ] **Step 3: Parse checkbox params in admin handlers**

In `SettingsLive`, add helper functions near `dollars_to_cents/1`:

```elixir
defp checkbox_checked?(params, key) do
  Map.get(params, key) in ["true", "on", "1", true]
end
```

In `handle_event("add_service", ...)`, add:

```elixir
show_on_landing: checkbox_checked?(params, "show_on_landing")
```

In `handle_event("update_service", ...)`, add:

```elixir
show_on_landing: checkbox_checked?(params, "show_on_landing")
```

- [ ] **Step 4: Add checkbox to Add Service form**

Inside the Add Service form, before the submit button, add:

```elixir
<label class="label cursor-pointer justify-start gap-2 md:col-span-2">
  <input
    type="checkbox"
    name="service[show_on_landing]"
    value="true"
    class="checkbox checkbox-sm checkbox-primary"
    checked
  />
  <span class="label-text text-xs">Show on landing page</span>
</label>
```

- [ ] **Step 5: Add checkbox to Edit Service form**

Inside the Edit Service form, before the save/cancel buttons, add:

```elixir
<label class="label cursor-pointer justify-start gap-2">
  <input
    type="checkbox"
    name="service[show_on_landing]"
    value="true"
    class="checkbox checkbox-sm checkbox-primary"
    checked={svc.show_on_landing}
  />
  <span class="label-text text-xs">Show on landing page</span>
</label>
```

In service view mode, add a small badge beside the slug:

```elixir
<span :if={!svc.show_on_landing} class="badge badge-sm badge-warning">Hidden from landing</span>
```

- [ ] **Step 6: Run admin tests**

Run:

```bash
mix test test/mobile_car_wash_web/live/admin/settings_live_test.exs
```

Expected: PASS.

- [ ] **Step 7: Commit task**

```bash
git add lib/mobile_car_wash_web/live/admin/settings_live.ex test/mobile_car_wash_web/live/admin/settings_live_test.exs
git commit -m "Add admin landing display control"
```

---

### Task 4: Booking Regression and Final Verification

**Files:**
- Modify: `test/mobile_car_wash_web/live/booking_single_page_test.exs`
- Verify: all modified code and tests

**Interfaces:**
- Consumes: `ServiceType.show_on_landing`.
- Produces: regression coverage proving `/book` ignores the landing display flag.

- [ ] **Step 1: Add booking regression test**

Add this test to `test/mobile_car_wash_web/live/booking_single_page_test.exs`:

```elixir
test "booking page renders active services hidden from landing display", %{conn: conn} do
  service =
    ServiceType
    |> Ash.Changeset.for_create(:create, %{
      name: "Book Only Wash",
      slug: "book_only_wash_#{System.unique_integer([:positive])}",
      description: "Active and bookable, not marketed on landing.",
      base_price_cents: 8800,
      duration_minutes: 75,
      active: true,
      show_on_landing: false
    })
    |> Ash.create!()

  {:ok, _view, html} = live(conn, ~p"/book")

  assert html =~ service.name
  assert html =~ "$88"
end
```

- [ ] **Step 2: Run regression test**

Run:

```bash
mix test test/mobile_car_wash_web/live/booking_single_page_test.exs
```

Expected: PASS.

- [ ] **Step 3: Run focused suite**

Run:

```bash
mix test test/mobile_car_wash/scheduling/service_type_landing_display_test.exs test/mobile_car_wash_web/live/landing_live_test.exs test/mobile_car_wash_web/live/admin/settings_live_test.exs test/mobile_car_wash_web/live/booking_single_page_test.exs
```

Expected: PASS.

- [ ] **Step 4: Run project precommit**

Run:

```bash
mix precommit
```

Expected: PASS. Fix any formatting, compile, credo, or test failures it reports.

- [ ] **Step 5: Commit final verification/test changes if separate**

```bash
git add test/mobile_car_wash_web/live/booking_single_page_test.exs
git commit -m "Cover booking visibility independent of landing display"
```
