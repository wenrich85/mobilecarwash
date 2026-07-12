# Before/After Reveal + Share Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the completed wash's status page into a reveal moment — draggable before/after sliders per area — with a one-tap "Share your wash" flow that composes a branded card and opens the native share sheet with the customer's referral link.

**Architecture:** All new behavior lives in `AppointmentStatusLive` plus two self-contained JS hooks (`BeforeAfterSlider` for drag/wipe, `ShareWashCard` for canvas composition + Web Share). No schema changes, no new routes, no new deps, no backend modules touched. Spec: `docs/superpowers/specs/2026-07-11-before-after-reveal-share-design.md`.

**Tech Stack:** Phoenix LiveView (HEEx), Ash queries, vanilla JS hooks (pointer events, IntersectionObserver, canvas, `navigator.share`), daisyUI classes.

## Global Constraints

- No flash messages for any photo/share outcome — all feedback renders inline (modal notice, tile-style copy). Established photo-flow convention.
- Zero compiler warnings; gate is `mix precommit` (format + compile + full suite, ~3.5 min).
- Reveal mode applies ONLY when `@appointment.status == :completed`; every other status keeps today's live grid untouched.
- Key-area priority order everywhere: front → rear → driver_side → passenger_side → interior → wheels (this is the existing `@key_areas` order in `AppointmentStatusLive`).
- All `<img>` tags inside sliders/cards carry `crossorigin="anonymous"` (canvas readback needs CORS-clean cache entries).
- Canvas card: 1080×1350 (4:5), JPEG quality 0.9, wordmark text "Driveway Detail", footer offer "Get $N off your first wash · CODE".
- Share text: `Look what Driveway Detail did for my car ✨ Get $N off your first wash:` (link rides in `url`/appended).
- JS hooks live in `assets/js/hooks/<snake_case>.js`, export a const, registered in `assets/js/app.js` `hooks: {…}`.
- Tests: LiveView tests only (no JS test infra). Test file already exists: `test/mobile_car_wash_web/live/appointment_status_live_test.exs`; extend it — its `register_customer/0`, `sign_in/2`, `create_appointment/2` helpers are reused by every task below.
- Run targeted tests with `mix test test/mobile_car_wash_web/live/appointment_status_live_test.exs` from the worktree root.

---

### Task 1: Exclude soft-deleted photos from the status page

Slot replacement (tech retakes a photo) soft-deletes the old Photo row, but
`AppointmentStatusLive` loads photos with no `deleted_at` filter — replaced
photos can appear on the customer page and would corrupt pair-matching
(`Enum.find` may pick the soft-deleted row). `PhotoUpload` filters
`is_nil(deleted_at)` everywhere; this page must too.

**Files:**
- Modify: `lib/mobile_car_wash_web/live/appointment_status_live.ex` (photo queries in `mount/3` ~line 37 and `reload_photos/1` ~line 334)
- Test: `test/mobile_car_wash_web/live/appointment_status_live_test.exs`

**Interfaces:**
- Consumes: existing test helpers `register_customer/0`, `sign_in/2`, `create_appointment/2`.
- Produces: `create_photo/4` test helper used by Tasks 2 and 4:
  `create_photo(appt, photo_type_atom, car_part_atom, file_path_string) :: Photo.t()`.
  Photo lists in assigns are guaranteed live (no soft-deleted rows).

- [ ] **Step 1: Add the `create_photo/4` helper and a failing test**

Add to `test/mobile_car_wash_web/live/appointment_status_live_test.exs` (below `create_appointment/2`; also add `alias MobileCarWash.Operations.Photo` to the alias block):

```elixir
defp create_photo(appt, photo_type, car_part, file_path) do
  {:ok, photo} =
    Photo
    |> Ash.Changeset.for_create(:upload, %{
      file_path: file_path,
      photo_type: photo_type,
      car_part: car_part,
      content_type: "image/jpeg",
      original_filename: Path.basename(file_path)
    })
    |> Ash.Changeset.force_change_attribute(:appointment_id, appt.id)
    |> Ash.create()

  photo
end
```

New describe block:

```elixir
describe "photo loading" do
  test "soft-deleted photos never render", %{conn: conn} do
    customer = register_customer()
    appt = create_appointment(customer, :in_progress)
    photo = create_photo(appt, :before, :front, "/uploads/front-old.jpg")

    {:ok, _} =
      photo
      |> Ash.Changeset.for_update(:soft_delete, %{})
      |> Ash.update()

    create_photo(appt, :before, :front, "/uploads/front-new.jpg")
    conn = sign_in(conn, customer)

    {:ok, _view, html} = live(conn, ~p"/appointments/#{appt.id}/status")
    refute html =~ "front-old.jpg"
    assert html =~ "front-new.jpg"
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/mobile_car_wash_web/live/appointment_status_live_test.exs`
Expected: 1 failure — `refute html =~ "front-old.jpg"` fails (the soft-deleted photo renders today).

- [ ] **Step 3: Filter soft-deleted photos in both queries**

In `lib/mobile_car_wash_web/live/appointment_status_live.ex`, the same query appears in `mount/3` and `reload_photos/1`. Extract one private helper and use it in both places:

```elixir
defp load_photos(appointment_id) do
  Photo
  |> Ash.Query.filter(appointment_id == ^appointment_id and is_nil(deleted_at))
  |> Ash.read!()
  |> Enum.map(&PhotoUpload.apply_url/1)
end
```

`mount/3` becomes:

```elixir
photos = load_photos(appointment_id)
```

`reload_photos/1` becomes:

```elixir
defp reload_photos(socket) do
  photos = load_photos(socket.assigns.appointment.id)

  assign(socket,
    before_photos: Enum.filter(photos, &(&1.photo_type == :before)),
    after_photos: Enum.filter(photos, &(&1.photo_type == :after))
  )
end
```

- [ ] **Step 4: Run the file's tests to verify all pass**

Run: `mix test test/mobile_car_wash_web/live/appointment_status_live_test.exs`
Expected: all pass (previous cancel tests + new one).

- [ ] **Step 5: Commit**

```bash
git add lib/mobile_car_wash_web/live/appointment_status_live.ex test/mobile_car_wash_web/live/appointment_status_live_test.exs
git commit -m "fix: exclude soft-deleted photos from appointment status page"
```

---

### Task 2: Reveal mode — pair computation and slider markup

When the appointment is `:completed`, replace the static thumbnail grid with
one slider container per complete before/after pair, an unpaired-photos strip,
and no placeholder cells. All other statuses keep the existing grid.

**Files:**
- Modify: `lib/mobile_car_wash_web/live/appointment_status_live.ex` (assigns in `mount/3` + `reload_photos/1`; render section "Before/After Photos" ~lines 229–284)
- Test: `test/mobile_car_wash_web/live/appointment_status_live_test.exs`

**Interfaces:**
- Consumes: `create_photo/4` helper (Task 1), live photo lists.
- Produces:
  - assign `@pairs :: [%{area: atom, label: String.t(), before: Photo.t(), after: Photo.t()}]` in key-area priority order — Task 4's modal iterates this.
  - assign `@unpaired_photos :: [Photo.t()]`.
  - DOM contract for Task 3's hook, per pair: container `id="reveal-#{area}"`,
    `phx-hook="BeforeAfterSlider"`, `phx-update="ignore"`, children
    `img[data-role="before"]` (top layer, clip-path target) and
    `div[data-role="divider"]`.

- [ ] **Step 1: Write failing tests**

Add to the test file:

```elixir
describe "reveal mode (completed wash)" do
  test "renders a slider per complete pair, in priority order", %{conn: conn} do
    customer = register_customer()
    appt = create_appointment(customer, :completed)
    create_photo(appt, :before, :front, "/uploads/front-b.jpg")
    create_photo(appt, :after, :front, "/uploads/front-a.jpg")
    create_photo(appt, :before, :wheels, "/uploads/wheels-b.jpg")
    create_photo(appt, :after, :wheels, "/uploads/wheels-a.jpg")
    conn = sign_in(conn, customer)

    {:ok, _view, html} = live(conn, ~p"/appointments/#{appt.id}/status")

    assert html =~ ~s(id="reveal-front")
    assert html =~ ~s(id="reveal-wheels")
    assert html =~ ~s(phx-hook="BeforeAfterSlider")
    assert html =~ ~s(data-before-url="/uploads/front-b.jpg")
    assert html =~ ~s(data-after-url="/uploads/front-a.jpg")
    # priority order: front slider appears before wheels slider
    {front_pos, _} = :binary.match(html, ~s(id="reveal-front"))
    {wheels_pos, _} = :binary.match(html, ~s(id="reveal-wheels"))
    assert front_pos < wheels_pos
  end

  test "incomplete pairs fall to the More photos strip, empty areas render nothing", %{conn: conn} do
    customer = register_customer()
    appt = create_appointment(customer, :completed)
    # rear has only a before — no slider, lands in strip
    create_photo(appt, :before, :rear, "/uploads/rear-b.jpg")
    conn = sign_in(conn, customer)

    {:ok, _view, html} = live(conn, ~p"/appointments/#{appt.id}/status")

    refute html =~ ~s(id="reveal-rear")
    assert html =~ "More photos"
    assert html =~ "/uploads/rear-b.jpg"
    # no placeholder circles in reveal mode
    refute html =~ "○"
  end

  test "in-progress wash keeps the live grid, no sliders", %{conn: conn} do
    customer = register_customer()
    appt = create_appointment(customer, :in_progress)
    create_photo(appt, :before, :front, "/uploads/front-b.jpg")
    create_photo(appt, :after, :front, "/uploads/front-a.jpg")
    conn = sign_in(conn, customer)

    {:ok, _view, html} = live(conn, ~p"/appointments/#{appt.id}/status")

    refute html =~ "BeforeAfterSlider"
    assert html =~ "Before"
    assert html =~ "After"
    assert html =~ "/uploads/front-b.jpg"
  end
end
```

- [ ] **Step 2: Run tests to verify the new ones fail**

Run: `mix test test/mobile_car_wash_web/live/appointment_status_live_test.exs`
Expected: the three new tests fail (no `reveal-*` ids, no "More photos"); prior tests pass.

- [ ] **Step 3: Implement pair assigns**

In `appointment_status_live.ex`, add the helpers (near `load_photos/1`):

```elixir
defp complete_pairs(before_photos, after_photos) do
  @key_areas
  |> Enum.map(fn area ->
    %{
      area: area.id,
      label: area.label,
      before: Enum.find(before_photos, &(&1.car_part == area.id)),
      after: Enum.find(after_photos, &(&1.car_part == area.id))
    }
  end)
  |> Enum.filter(&(&1.before && &1.after))
end

defp unpaired_photos(before_photos, after_photos, pairs) do
  paired = MapSet.new(pairs, & &1.area)

  Enum.reject(before_photos ++ after_photos, &MapSet.member?(paired, &1.car_part))
end

defp assign_photo_views(socket, photos) do
  before_photos = Enum.filter(photos, &(&1.photo_type == :before))
  after_photos = Enum.filter(photos, &(&1.photo_type == :after))
  pairs = complete_pairs(before_photos, after_photos)

  assign(socket,
    before_photos: before_photos,
    after_photos: after_photos,
    pairs: pairs,
    unpaired_photos: unpaired_photos(before_photos, after_photos, pairs)
  )
end
```

Use `assign_photo_views/2` from both `mount/3` (replacing the individual `before_photos`/`after_photos` assigns — keep the separate `problem_photos` assign as is) and `reload_photos/1`:

```elixir
defp reload_photos(socket) do
  assign_photo_views(socket, load_photos(socket.assigns.appointment.id))
end
```

Note `mount/3` currently builds the big `assign(socket, ...)` keyword list including `before_photos`/`after_photos` — remove those two keys from that list and pipe the socket through `assign_photo_views(photos)` instead.

- [ ] **Step 4: Implement the render branch**

In `render/1`, change the existing "Before/After Photos (live)" section's outer condition so the grid only renders when NOT completed:

```heex
<!-- Before/After Photos (live, during wash) -->
<div
  :if={
    @appointment.status != :completed and
      (@live_status == :in_progress or @before_photos != [] or @after_photos != [])
  }
  class="mb-6"
>
```

(body of the grid unchanged)

Insert the reveal section immediately after that grid `</div>`:

```heex
<!-- The reveal (completed wash) -->
<div
  :if={@appointment.status == :completed and (@pairs != [] or @unpaired_photos != [])}
  class="mb-6"
>
  <h3 class="font-semibold mb-3">The reveal ✨</h3>
  <div class="space-y-4">
    <div :for={pair <- @pairs}>
      <p class="text-xs text-base-content/70 mb-1">{pair.label}</p>
      <div
        id={"reveal-#{pair.area}"}
        phx-hook="BeforeAfterSlider"
        phx-update="ignore"
        class="relative aspect-[4/3] rounded-xl overflow-hidden bg-base-200 select-none touch-none cursor-ew-resize"
        data-before-url={pair.before.file_path}
        data-after-url={pair.after.file_path}
      >
        <img
          src={pair.after.file_path}
          crossorigin="anonymous"
          class="absolute inset-0 w-full h-full object-cover pointer-events-none"
        />
        <img
          src={pair.before.file_path}
          crossorigin="anonymous"
          data-role="before"
          class="absolute inset-0 w-full h-full object-cover pointer-events-none"
          style="clip-path: inset(0 0% 0 0)"
        />
        <span class="absolute top-2 left-2 badge badge-sm bg-base-100/80 border-0 pointer-events-none">
          Before
        </span>
        <span class="absolute top-2 right-2 badge badge-sm bg-base-100/80 border-0 pointer-events-none">
          After
        </span>
        <div
          data-role="divider"
          class="absolute inset-y-0 w-0.5 bg-base-100 shadow pointer-events-none"
          style="left: 100%"
        >
          <div class="absolute top-1/2 left-0 -translate-y-1/2 -translate-x-1/2 w-9 h-9 rounded-full bg-base-100 shadow-md flex items-center justify-center text-base-content/60 text-sm">
            ⇔
          </div>
        </div>
      </div>
    </div>
  </div>

  <div :if={@unpaired_photos != []} class="mt-4">
    <p class="text-xs text-base-content/70 mb-1">More photos</p>
    <div class="flex gap-2 overflow-x-auto">
      <img
        :for={photo <- @unpaired_photos}
        src={photo.file_path}
        class="w-24 h-24 object-cover rounded-lg flex-shrink-0"
      />
    </div>
  </div>
</div>
```

Initial state is P=100 (all before: `clip-path: inset(0 0% 0 0)` on the before layer, divider at `left: 100%`); the hook animates/positions from there. `phx-update="ignore"` keeps LiveView from clobbering hook-mutated styles.

- [ ] **Step 5: Run tests to verify all pass**

Run: `mix test test/mobile_car_wash_web/live/appointment_status_live_test.exs`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add lib/mobile_car_wash_web/live/appointment_status_live.ex test/mobile_car_wash_web/live/appointment_status_live_test.exs
git commit -m "feat: before/after reveal sliders on completed wash status page"
```

---

### Task 3: `BeforeAfterSlider` JS hook

Drag/tap scrubbing plus the one-time wipe animation. Client-side only.

**Files:**
- Create: `assets/js/hooks/before_after_slider.js`
- Modify: `assets/js/app.js` (import + register)

**Interfaces:**
- Consumes: Task 2's DOM contract — container with `img[data-role="before"]` and `div[data-role="divider"]`, initial P=100.
- Produces: hook export `BeforeAfterSlider`, registered under that name. No server events.

- [ ] **Step 1: Write the hook**

Create `assets/js/hooks/before_after_slider.js`:

```js
// Draggable before/after comparison slider for the completed-wash reveal.
//
// The container stacks the AFTER image (base) under the BEFORE image
// (top, clipped). P = divider position as % of width = how much BEFORE
// shows (P=100 all before, P=0 all after).
//
// On first scroll-into-view (>= 60% visible) the slider plays a one-time
// wipe from P=100 to P=50 (~1.2s ease-out), then rests for the customer
// to drag. Tap anywhere jumps the divider; drag scrubs. Respects
// prefers-reduced-motion by skipping straight to P=50.
const WIPE_MS = 1200
const WIPE_FROM = 100
const WIPE_TO = 50

export const BeforeAfterSlider = {
  mounted() {
    this.before = this.el.querySelector('[data-role="before"]')
    this.divider = this.el.querySelector('[data-role="divider"]')
    this.wiped = false
    this.dragging = false

    const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches
    if (reducedMotion) {
      this.wiped = true
      this.setP(WIPE_TO)
    } else {
      this.setP(WIPE_FROM)
      this.observer = new IntersectionObserver(
        entries => {
          entries.forEach(entry => {
            if (entry.intersectionRatio >= 0.6 && !this.wiped) {
              this.wiped = true
              this.wipe()
            }
          })
        },
        {threshold: 0.6}
      )
      this.observer.observe(this.el)
    }

    this.el.addEventListener("pointerdown", event => {
      this.dragging = true
      this.el.setPointerCapture(event.pointerId)
      this.scrubTo(event)
    })
    this.el.addEventListener("pointermove", event => {
      if (this.dragging) this.scrubTo(event)
    })
    this.el.addEventListener("pointerup", () => (this.dragging = false))
    this.el.addEventListener("pointercancel", () => (this.dragging = false))
  },

  destroyed() {
    if (this.observer) this.observer.disconnect()
    if (this.frame) cancelAnimationFrame(this.frame)
  },

  scrubTo(event) {
    // User interaction takes over: cancel any pending/running wipe.
    this.wiped = true
    if (this.frame) cancelAnimationFrame(this.frame)

    const rect = this.el.getBoundingClientRect()
    const p = ((event.clientX - rect.left) / rect.width) * 100
    this.setP(Math.min(100, Math.max(0, p)))
  },

  setP(p) {
    this.before.style.clipPath = `inset(0 ${100 - p}% 0 0)`
    this.divider.style.left = `${p}%`
  },

  wipe() {
    const start = performance.now()
    const tick = now => {
      const t = Math.min(1, (now - start) / WIPE_MS)
      const eased = 1 - Math.pow(1 - t, 3)
      this.setP(WIPE_FROM + (WIPE_TO - WIPE_FROM) * eased)
      if (t < 1) this.frame = requestAnimationFrame(tick)
    }
    this.frame = requestAnimationFrame(tick)
  }
}
```

- [ ] **Step 2: Register the hook**

In `assets/js/app.js`, add the import next to the existing hook imports and the name to the `hooks:` object:

```js
import {BeforeAfterSlider} from "./hooks/before_after_slider"
```

```js
hooks: {...colocatedHooks, Sortable, DispatchMap, AddressMap, ClipboardCopy, PriceCountUp, ImageDownscale, BeforeAfterSlider},
```

- [ ] **Step 3: Verify assets build and suite still green**

Run: `mix assets.build && mix test test/mobile_car_wash_web/live/appointment_status_live_test.exs`
Expected: esbuild succeeds with no errors; tests pass.

- [ ] **Step 4: Commit**

```bash
git add assets/js/hooks/before_after_slider.js assets/js/app.js
git commit -m "feat: BeforeAfterSlider hook — drag scrub + one-time reveal wipe"
```

---

### Task 4: Share CTA, picker modal, and LiveView events

The "Share your wash" card below the sliders, the pair-picker modal, and the
server side of the share hook's events.

**Files:**
- Modify: `lib/mobile_car_wash_web/live/appointment_status_live.ex`
- Test: `test/mobile_car_wash_web/live/appointment_status_live_test.exs`

**Interfaces:**
- Consumes: `@pairs` (Task 2), `MobileCarWash.Marketing.Referrals.share_link_for/1` and `default_reward_dollars/0`, `MobileCarWashWeb.CoreComponents.modal/1` (`<.modal id=... show on_cancel={JS}>` with `:title`/`:footer` slots).
- Produces (DOM contract for Task 5's hook): Share button `id="share-wash-card"`, `phx-hook="ShareWashCard"`, with dataset keys `beforeUrl`, `afterUrl`, `areaLabel`, `referralCode`, `rewardDollars`, `shareLink`, `shareText`. Server events the hook may push: `"share_degraded"` (no params) and `"share_fallback_done"` with `%{"mode" => "image" | "image_only" | "link"}`.

- [ ] **Step 1: Write failing tests**

```elixir
describe "share your wash" do
  defp completed_with_pair(conn) do
    customer = register_customer()
    appt = create_appointment(customer, :completed)
    create_photo(appt, :before, :front, "/uploads/front-b.jpg")
    create_photo(appt, :after, :front, "/uploads/front-a.jpg")
    create_photo(appt, :before, :wheels, "/uploads/wheels-b.jpg")
    create_photo(appt, :after, :wheels, "/uploads/wheels-a.jpg")
    {sign_in(conn, customer), appt}
  end

  test "CTA renders only when a complete pair exists", %{conn: conn} do
    {conn2, appt} = completed_with_pair(conn)
    {:ok, _view, html} = live(conn2, ~p"/appointments/#{appt.id}/status")
    assert html =~ "Share your wash"

    customer = register_customer()
    bare = create_appointment(customer, :completed)
    create_photo(bare, :before, :front, "/uploads/only-before.jpg")
    conn3 = sign_in(conn, customer)
    {:ok, _view, html} = live(conn3, ~p"/appointments/#{bare.id}/status")
    refute html =~ "Share your wash"
  end

  test "modal opens with the first pair preselected and referral data wired", %{conn: conn} do
    {conn, appt} = completed_with_pair(conn)
    {:ok, view, _html} = live(conn, ~p"/appointments/#{appt.id}/status")

    html = view |> element("button", "Share your wash") |> render_click()

    assert html =~ ~s(id="share-wash-card")
    assert html =~ ~s(phx-hook="ShareWashCard")
    assert html =~ ~s(data-before-url="/uploads/front-b.jpg")
    assert html =~ ~s(data-after-url="/uploads/front-a.jpg")
    assert html =~ "utm_source=referral"
    # referral code present and embedded in the share link
    assert [_, code] = Regex.run(~r/data-referral-code="([^"]+)"/, html)
    assert html =~ "ref=#{code}"
  end

  test "smart default is the first complete pair in priority order when front is incomplete",
       %{conn: conn} do
    customer = register_customer()
    appt = create_appointment(customer, :completed)
    # front has only a before (incomplete); wheels is the only complete pair
    create_photo(appt, :before, :front, "/uploads/front-b.jpg")
    create_photo(appt, :before, :wheels, "/uploads/wheels-b.jpg")
    create_photo(appt, :after, :wheels, "/uploads/wheels-a.jpg")
    conn = sign_in(conn, customer)

    {:ok, view, _html} = live(conn, ~p"/appointments/#{appt.id}/status")
    html = view |> element("button", "Share your wash") |> render_click()

    assert html =~ ~s(data-before-url="/uploads/wheels-b.jpg")
    assert html =~ ~s(data-after-url="/uploads/wheels-a.jpg")
  end

  test "selecting another pair updates the share button dataset", %{conn: conn} do
    {conn, appt} = completed_with_pair(conn)
    {:ok, view, _html} = live(conn, ~p"/appointments/#{appt.id}/status")
    view |> element("button", "Share your wash") |> render_click()

    html =
      view
      |> element(~s(button[phx-value-area="wheels"]))
      |> render_click()

    assert html =~ ~s(data-before-url="/uploads/wheels-b.jpg")
    assert html =~ ~s(data-after-url="/uploads/wheels-a.jpg")
  end

  test "share_degraded and share_fallback_done render inline notices", %{conn: conn} do
    {conn, appt} = completed_with_pair(conn)
    {:ok, view, _html} = live(conn, ~p"/appointments/#{appt.id}/status")
    view |> element("button", "Share your wash") |> render_click()

    html = render_hook(view, "share_degraded", %{})
    assert html =~ "Couldn&#39;t attach the photo"

    html = render_hook(view, "share_fallback_done", %{"mode" => "image"})
    assert html =~ "Image saved — link copied"

    html = render_hook(view, "share_fallback_done", %{"mode" => "link"})
    assert html =~ "Link copied"
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/mobile_car_wash_web/live/appointment_status_live_test.exs`
Expected: the four new tests fail ("Share your wash" not rendered); the rest pass.

- [ ] **Step 3: Implement assigns and events**

In `appointment_status_live.ex`:

Add the alias at the top: `alias MobileCarWash.Marketing.Referrals`

In `mount/3` (success branch), compute share data once:

```elixir
share_link = Referrals.share_link_for(customer)

referral_code =
  share_link
  |> URI.parse()
  |> Map.get(:query, "")
  |> Kernel.||("")
  |> URI.decode_query()
  |> Map.get("ref")
```

(`share_link_for/1` backfills a missing referral code on legacy customers, so
parse the code back out of the link rather than trusting
`customer.referral_code`, which may still be `nil` on the in-memory struct.)

Add to the mount assign list:

```elixir
share_link: share_link,
referral_code: referral_code,
share_modal_open: false,
share_area: nil,
share_degraded: false,
share_confirmation: nil
```

Add the event handlers (next to `handle_event("cancel_appointment", ...)`):

```elixir
@impl true
def handle_event("open_share_modal", _params, socket) do
  default_area =
    case socket.assigns.pairs do
      [first | _] -> first.area
      [] -> nil
    end

  {:noreply,
   assign(socket,
     share_modal_open: true,
     share_area: socket.assigns.share_area || default_area,
     share_degraded: false,
     share_confirmation: nil
   )}
end

def handle_event("close_share_modal", _params, socket) do
  {:noreply, assign(socket, share_modal_open: false)}
end

def handle_event("select_share_area", %{"area" => area}, socket) do
  case Enum.find(socket.assigns.pairs, &(to_string(&1.area) == area)) do
    nil -> {:noreply, socket}
    pair -> {:noreply, assign(socket, share_area: pair.area)}
  end
end

def handle_event("share_degraded", _params, socket) do
  {:noreply, assign(socket, share_degraded: true)}
end

def handle_event("share_fallback_done", params, socket) do
  message =
    case params["mode"] do
      "image" -> "Image saved — link copied"
      _ -> "Link copied"
    end

  {:noreply, assign(socket, share_confirmation: message)}
end
```

Add the pair-lookup helper:

```elixir
defp selected_pair(pairs, area) do
  Enum.find(pairs, &(&1.area == area)) || List.first(pairs)
end
```

- [ ] **Step 4: Implement the CTA and modal markup**

Insert directly after the reveal section from Task 2 (inside the `:if={@appointment}` div):

```heex
<!-- Share your wash -->
<div
  :if={@appointment.status == :completed and @pairs != [] and @share_link}
  class="card bg-gradient-to-br from-primary/10 to-secondary/10 shadow mb-6"
>
  <div class="card-body p-4">
    <h3 class="font-semibold">✨ Share your wash</h3>
    <p class="text-sm text-base-content/80">
      Show off the transformation — friends save on their first wash and you earn
      <span class="font-semibold">${Referrals.default_reward_dollars()} in credit</span>
      when they book.
    </p>
    <button type="button" class="btn btn-primary w-full mt-2" phx-click="open_share_modal">
      Share your wash
    </button>
  </div>
</div>

<.modal
  :if={@share_modal_open}
  id="share-wash-modal"
  show
  on_cancel={Phoenix.LiveView.JS.push("close_share_modal")}
>
  <:title>Share your wash</:title>
  <p class="text-sm text-base-content/80 mb-3">Pick your favorite before &amp; after:</p>
  <div class="flex gap-3 overflow-x-auto pb-2">
    <button
      :for={pair <- @pairs}
      type="button"
      phx-click="select_share_area"
      phx-value-area={pair.area}
      class={[
        "flex-shrink-0 rounded-lg border-2 p-1",
        if(@share_area == pair.area, do: "border-primary", else: "border-transparent")
      ]}
    >
      <div class="flex gap-0.5 w-32">
        <img
          src={pair.before.file_path}
          crossorigin="anonymous"
          class="w-1/2 aspect-[3/4] object-cover rounded-l"
        />
        <img
          src={pair.after.file_path}
          crossorigin="anonymous"
          class="w-1/2 aspect-[3/4] object-cover rounded-r"
        />
      </div>
      <p class="text-xs text-center mt-1">{pair.label}</p>
    </button>
  </div>
  <p :if={@share_degraded} class="text-xs text-warning mt-2">
    Couldn't attach the photo — your link was shared instead.
  </p>
  <p :if={@share_confirmation} class="text-xs text-success mt-2">{@share_confirmation}</p>
  <:footer>
    <% pair = selected_pair(@pairs, @share_area) %>
    <button
      id="share-wash-card"
      type="button"
      phx-hook="ShareWashCard"
      data-before-url={pair.before.file_path}
      data-after-url={pair.after.file_path}
      data-area-label={pair.label}
      data-referral-code={@referral_code}
      data-reward-dollars={Referrals.default_reward_dollars()}
      data-share-link={@share_link}
      data-share-text={"Look what Driveway Detail did for my car ✨ Get $#{Referrals.default_reward_dollars()} off your first wash:"}
      class="btn btn-primary"
    >
      Share
    </button>
  </:footer>
</.modal>
```

- [ ] **Step 5: Run tests to verify all pass**

Run: `mix test test/mobile_car_wash_web/live/appointment_status_live_test.exs`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add lib/mobile_car_wash_web/live/appointment_status_live.ex test/mobile_car_wash_web/live/appointment_status_live_test.exs
git commit -m "feat: share-your-wash CTA and pair picker modal"
```

---

### Task 5: `ShareWashCard` JS hook

Canvas composition of the branded card and the native-share / fallback logic.

**Files:**
- Create: `assets/js/hooks/share_wash_card.js`
- Modify: `assets/js/app.js` (import + register)

**Interfaces:**
- Consumes: Task 4's DOM contract — button dataset `beforeUrl`, `afterUrl`, `areaLabel`, `referralCode`, `rewardDollars`, `shareLink`, `shareText`; pushes `"share_degraded"` and `"share_fallback_done"` (`{mode: "image" | "link"}`).
- Produces: hook export `ShareWashCard`, registered under that name.

- [ ] **Step 1: Write the hook**

Create `assets/js/hooks/share_wash_card.js`:

```js
// Composes the branded before/after share card on a canvas and opens
// the native share sheet (navigator.share with files). Fallbacks:
//   - canvas fails (image load error / CORS taint) -> share text+link only,
//     pushEvent("share_degraded") so the modal shows a soft notice
//   - no file-capable share sheet (desktop) -> download the JPEG and copy
//     the share text+link, pushEvent("share_fallback_done", {mode})
// A user-cancelled share sheet (AbortError) is silently ignored.
// No flash messages — all feedback renders inside the modal.
const CANVAS_W = 1080
const CANVAS_H = 1350
const FOOTER_H = 150
const DIVIDER_H = 4
const FONT_STACK = "system-ui, -apple-system, 'Segoe UI', sans-serif"

function loadImage(url) {
  return new Promise((resolve, reject) => {
    const img = new Image()
    img.crossOrigin = "anonymous"
    img.onload = () => resolve(img)
    img.onerror = () => reject(new Error(`could not load ${url}`))
    img.src = url
  })
}

// drawImage with CSS object-fit:cover semantics.
function drawCover(ctx, img, x, y, w, h) {
  const scale = Math.max(w / img.width, h / img.height)
  const sw = w / scale
  const sh = h / scale
  ctx.drawImage(img, (img.width - sw) / 2, (img.height - sh) / 2, sw, sh, x, y, w, h)
}

function drawChip(ctx, text, x, y) {
  ctx.save()
  ctx.font = `bold 34px ${FONT_STACK}`
  const w = ctx.measureText(text).width + 44
  const h = 58
  ctx.fillStyle = "rgba(255, 255, 255, 0.85)"
  ctx.beginPath()
  ctx.roundRect(x, y, w, h, h / 2)
  ctx.fill()
  ctx.fillStyle = "#1f2937"
  ctx.textBaseline = "middle"
  ctx.fillText(text, x + 22, y + h / 2)
  ctx.restore()
}

async function composeCard(data) {
  const [before, after] = await Promise.all([
    loadImage(data.beforeUrl),
    loadImage(data.afterUrl)
  ])

  const canvas = document.createElement("canvas")
  canvas.width = CANVAS_W
  canvas.height = CANVAS_H
  const ctx = canvas.getContext("2d")
  const half = (CANVAS_H - FOOTER_H - DIVIDER_H) / 2

  drawCover(ctx, before, 0, 0, CANVAS_W, half)
  drawCover(ctx, after, 0, half + DIVIDER_H, CANVAS_W, half)
  ctx.fillStyle = "#ffffff"
  ctx.fillRect(0, half, CANVAS_W, DIVIDER_H)

  drawChip(ctx, "Before", 32, 32)
  drawChip(ctx, "After", 32, half + DIVIDER_H + 32)

  ctx.fillStyle = "#111827"
  ctx.fillRect(0, CANVAS_H - FOOTER_H, CANVAS_W, FOOTER_H)
  ctx.textBaseline = "middle"
  ctx.fillStyle = "#ffffff"
  ctx.font = `bold 44px ${FONT_STACK}`
  ctx.fillText("Driveway Detail", 40, CANVAS_H - FOOTER_H / 2)
  ctx.textAlign = "right"
  ctx.font = `32px ${FONT_STACK}`
  ctx.fillStyle = "#d1d5db"
  ctx.fillText(
    `Get $${data.rewardDollars} off your first wash · ${data.referralCode}`,
    CANVAS_W - 40,
    CANVAS_H - FOOTER_H / 2
  )

  // toBlob throws SecurityError synchronously on a tainted canvas —
  // the caller's try/catch handles both that and the reject path.
  const blob = await new Promise((resolve, reject) =>
    canvas.toBlob(b => (b ? resolve(b) : reject(new Error("toBlob failed"))), "image/jpeg", 0.9)
  )
  return new File([blob], "driveway-detail-wash.jpg", {type: "image/jpeg"})
}

function download(file) {
  const url = URL.createObjectURL(file)
  const a = document.createElement("a")
  a.href = url
  a.download = file.name
  a.click()
  URL.revokeObjectURL(url)
}

export const ShareWashCard = {
  mounted() {
    this.el.addEventListener("click", () => this.share())
  },

  async share() {
    const data = this.el.dataset
    let file = null

    try {
      file = await composeCard(data)
    } catch (_error) {
      this.pushEvent("share_degraded", {})
    }

    try {
      if (file && navigator.canShare && navigator.canShare({files: [file]})) {
        await navigator.share({files: [file], text: data.shareText, url: data.shareLink})
      } else if (!file && navigator.share) {
        await navigator.share({text: data.shareText, url: data.shareLink})
      } else {
        if (file) download(file)
        await navigator.clipboard.writeText(`${data.shareText} ${data.shareLink}`)
        this.pushEvent("share_fallback_done", {mode: file ? "image" : "link"})
      }
    } catch (error) {
      if (error.name === "AbortError") return
      // Share sheet failed some other way — last resort: copy the link.
      try {
        await navigator.clipboard.writeText(`${data.shareText} ${data.shareLink}`)
        this.pushEvent("share_fallback_done", {mode: "link"})
      } catch (_clipboardError) {
        this.pushEvent("share_degraded", {})
      }
    }
  }
}
```

- [ ] **Step 2: Register the hook**

In `assets/js/app.js`:

```js
import {ShareWashCard} from "./hooks/share_wash_card"
```

```js
hooks: {...colocatedHooks, Sortable, DispatchMap, AddressMap, ClipboardCopy, PriceCountUp, ImageDownscale, BeforeAfterSlider, ShareWashCard},
```

- [ ] **Step 3: Verify assets build and suite still green**

Run: `mix assets.build && mix test test/mobile_car_wash_web/live/appointment_status_live_test.exs`
Expected: esbuild succeeds; tests pass.

- [ ] **Step 4: Commit**

```bash
git add assets/js/hooks/share_wash_card.js assets/js/app.js
git commit -m "feat: ShareWashCard hook — canvas card composition + native share"
```

---

### Task 6: Deploy checklist update + full gate

**Files:**
- Modify: `docs/superpowers/specs/2026-07-11-direct-to-spaces-uploads-design.md` (Deploy checklist, ~line 252)

**Interfaces:**
- Consumes: everything above.
- Produces: a merged-ready branch.

- [ ] **Step 1: Add GET to the Spaces CORS checklist item**

In `docs/superpowers/specs/2026-07-11-direct-to-spaces-uploads-design.md`, item 1 of "## Deploy checklist" currently reads `methods = PUT`. Update it to:

```markdown
1. Set CORS on the Space (DO control panel or `s3cmd`/`aws s3api` against
   the Spaces endpoint): allowed origin = the app's production origin,
   methods = `PUT` and `GET`, allowed headers = `content-type`, max age 3600.
   (`GET` is required by the before/after share card: slider images load with
   `crossorigin="anonymous"` and are drawn to a canvas — without CORS on GET
   the canvas taints and every share degrades to text-only.)
```

Also append to item 3 (the phone verification item), after its current text:

```markdown
   Then on a completed wash's status page: drag a before/after slider, watch
   the wipe animation play once, and share a card — the composed image (not
   just text) must reach the share sheet on iOS Safari and Android Chrome.
```

- [ ] **Step 2: Run the full precommit gate**

Run: `mix precommit`
Expected: format clean, compile with zero warnings, full suite green (1433 baseline + new tests, 0 failures).

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/specs/2026-07-11-direct-to-spaces-uploads-design.md
git commit -m "docs: add GET + share-card verification to Spaces deploy checklist"
```
