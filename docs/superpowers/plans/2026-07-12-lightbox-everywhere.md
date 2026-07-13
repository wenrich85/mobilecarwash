# Lightbox Everywhere Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tap any photo on any surface to view it fullscreen, with gallery navigation, a fullscreen before/after scrub for reveal sliders, and full a11y on the overlay.

**Architecture:** Pure client-side JS hook (`Lightbox`) attached to a server-rendered overlay skeleton (`<.lightbox_root />`), opt-in via `data-lightbox` attributes on thumbnails; gallery snapshotted at open time. Scrub logic extracted from `BeforeAfterSlider` into a shared `slider_core.js`. Zero new server events or assigns.

**Tech Stack:** Elixir / Phoenix LiveView / HEEx function components; vanilla JS LiveView hooks; esbuild + tailwind; ExUnit LiveView tests.

**Spec:** `docs/superpowers/specs/2026-07-12-lightbox-everywhere-design.md` (read it first).

## Global Constraints

- Worktree `lightbox-everywhere`, branch `worktree-lightbox-everywhere`, base 1d2d81b. Never touch the main checkout.
- `BeforeAfterSlider`'s observable behavior must not change (DOM contract, wipe animation, reduced-motion path).
- Every wired `<img>` must carry non-empty `alt`. Decorative images (ghost overlay) get no `data-lightbox`.
- Component modules use `use Phoenix.Component` and live in `lib/mobile_car_wash_web/components/` with module name `MobileCarWashWeb.<Name>` (no `.Components.` segment — matches `MobileCarWashWeb.PhotoUploader`).
- Test commands: single file `mix test <path>`, full gate `mix precommit` (compile --warnings-as-errors, deps.unlock --check-unused, format, test).
- `mix format` before every commit (it adds trailing whitespace rules; run it, don't hand-format).
- Commit messages: imperative, no scope prefix (repo style: "Add problem photos to tech job brief").

---

### Task 1: Extract `slider_core.js` (behavior-preserving refactor)

**Files:**
- Create: `assets/js/slider_core.js`
- Modify: `assets/js/hooks/before_after_slider.js`
- Test: `test/mobile_car_wash_web/live/appointment_status_live_test.exs` (existing — must stay green)

**Interfaces:**
- Produces: `attachScrub(el, {before, divider, onUserScrub}) -> {setP(p), detach()}` — pointer-capture scrub on `el`; `setP(p)` sets `before.style.clipPath = inset(0 (100-p)% 0 0)` and `divider.style.left = p%`; `onUserScrub` (optional) fires on every user pointer interaction; `detach()` removes all listeners. Task 2's `Lightbox` imports this exact signature.

- [ ] **Step 1: Create `assets/js/slider_core.js`**

```js
// Shared before/after scrub geometry, used by the BeforeAfterSlider page
// hook and the Lightbox fullscreen slider mode. P = divider position as %
// of width = how much BEFORE shows (P=100 all before, P=0 all after).
//
// attachScrub(el, {before, divider, onUserScrub}) -> {setP, detach}
//   el          container receiving pointer events (captures the pointer)
//   before      the clipped top image element
//   divider     the divider line element
//   onUserScrub optional; called on every user pointer interaction
export function attachScrub(el, {before, divider, onUserScrub}) {
  let dragging = false

  const setP = p => {
    before.style.clipPath = `inset(0 ${100 - p}% 0 0)`
    divider.style.left = `${p}%`
  }

  const scrubTo = event => {
    if (onUserScrub) onUserScrub()
    const rect = el.getBoundingClientRect()
    const p = ((event.clientX - rect.left) / rect.width) * 100
    setP(Math.min(100, Math.max(0, p)))
  }

  const down = event => {
    dragging = true
    el.setPointerCapture(event.pointerId)
    scrubTo(event)
  }
  const move = event => {
    if (dragging) scrubTo(event)
  }
  const up = () => (dragging = false)

  el.addEventListener("pointerdown", down)
  el.addEventListener("pointermove", move)
  el.addEventListener("pointerup", up)
  el.addEventListener("pointercancel", up)

  return {
    setP,
    detach() {
      el.removeEventListener("pointerdown", down)
      el.removeEventListener("pointermove", move)
      el.removeEventListener("pointerup", up)
      el.removeEventListener("pointercancel", up)
    }
  }
}
```

- [ ] **Step 2: Rewrite `assets/js/hooks/before_after_slider.js` on top of it**

Replace the whole file with:

```js
// Draggable before/after comparison slider for the completed-wash reveal.
//
// The container stacks the AFTER image (base) under the BEFORE image
// (top, clipped). Scrub geometry lives in ../slider_core (shared with the
// Lightbox fullscreen slider mode).
//
// On first scroll-into-view (>= 60% visible) the slider plays a one-time
// wipe from P=100 to P=50 (~1.2s ease-out), then rests for the customer
// to drag. Tap anywhere jumps the divider; drag scrubs. Respects
// prefers-reduced-motion by skipping straight to P=50.
import {attachScrub} from "../slider_core"

const WIPE_MS = 1200
const WIPE_FROM = 100
const WIPE_TO = 50

export const BeforeAfterSlider = {
  mounted() {
    this.wiped = false

    this.scrub = attachScrub(this.el, {
      before: this.el.querySelector('[data-role="before"]'),
      divider: this.el.querySelector('[data-role="divider"]'),
      onUserScrub: () => {
        // User interaction takes over: cancel any pending/running wipe.
        this.wiped = true
        if (this.frame) cancelAnimationFrame(this.frame)
      }
    })

    const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches
    if (reducedMotion) {
      this.wiped = true
      this.scrub.setP(WIPE_TO)
    } else {
      this.scrub.setP(WIPE_FROM)
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
  },

  destroyed() {
    if (this.observer) this.observer.disconnect()
    if (this.frame) cancelAnimationFrame(this.frame)
    if (this.scrub) this.scrub.detach()
  },

  wipe() {
    const start = performance.now()
    const tick = now => {
      const t = Math.min(1, (now - start) / WIPE_MS)
      const eased = 1 - Math.pow(1 - t, 3)
      this.scrub.setP(WIPE_FROM + (WIPE_TO - WIPE_FROM) * eased)
      if (t < 1) this.frame = requestAnimationFrame(tick)
    }
    this.frame = requestAnimationFrame(tick)
  }
}
```

Behavior notes preserved exactly: pointer capture on container, tap jumps + drag scrubs, wipe cancel on user interaction, reduced-motion skip, observer/rAF cleanup. One deliberate difference: `detach()` in `destroyed()` (new, harmless — element is being removed anyway).

- [ ] **Step 3: Verify the bundle builds**

Run: `mix assets.build`
Expected: exits 0; esbuild reports no "could not resolve" errors.

- [ ] **Step 4: Run the slider DOM-contract tests**

Run: `mix test test/mobile_car_wash_web/live/appointment_status_live_test.exs`
Expected: all pass (the hook's server-side contract is unchanged).

- [ ] **Step 5: Commit**

```bash
mix format
git add assets/js/slider_core.js assets/js/hooks/before_after_slider.js
git commit -m "Extract shared slider scrub core from BeforeAfterSlider"
```

---

### Task 2: `Lightbox` component + hook + registration

**Files:**
- Create: `lib/mobile_car_wash_web/components/lightbox.ex`
- Create: `assets/js/hooks/lightbox.js`
- Create: `test/mobile_car_wash_web/components/lightbox_test.exs`
- Modify: `assets/js/app.js` (import + hooks map)

**Interfaces:**
- Consumes: `attachScrub` from Task 1 (exact signature above).
- Produces: `MobileCarWashWeb.Lightbox.lightbox_root/1` — HEEx function component, no required assigns, renders `#lightbox-root`. Tasks 3–7 render it via `import MobileCarWashWeb.Lightbox` + `<.lightbox_root />` and rely on these opt-in contracts:
  - `<img data-lightbox="<group>" alt="..." [data-lightbox-caption="..."]>`
  - `<button data-lightbox-slider data-before-url="..." data-after-url="...">`

- [ ] **Step 1: Write the failing component test**

`test/mobile_car_wash_web/components/lightbox_test.exs`:

```elixir
defmodule MobileCarWashWeb.LightboxTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias MobileCarWashWeb.Lightbox

  test "lightbox_root renders the hidden overlay skeleton with hook and a11y contract" do
    html = render_component(&Lightbox.lightbox_root/1, %{})

    assert html =~ ~s(id="lightbox-root")
    assert html =~ ~s(phx-hook="Lightbox")
    assert html =~ ~s(phx-update="ignore")
    assert html =~ ~s(role="dialog")
    assert html =~ ~s(aria-modal="true")
    assert html =~ ~s(aria-label="Photo viewer")

    # controls
    assert html =~ ~s(aria-label="Close photo viewer")
    assert html =~ ~s(aria-label="Previous photo")
    assert html =~ ~s(aria-label="Next photo")
    assert html =~ ~s(aria-live="polite")

    # stage parts the hook hydrates
    for role <- ~w(backdrop stage image slider-stage slider-before slider-after slider-divider load-error counter caption) do
      assert html =~ ~s(data-role="#{role}"), "missing data-role=#{role}"
    end
  end
end
```

- [ ] **Step 2: Run it — expect failure**

Run: `mix test test/mobile_car_wash_web/components/lightbox_test.exs`
Expected: FAIL — `module MobileCarWashWeb.Lightbox is not available`.

- [ ] **Step 3: Create `lib/mobile_car_wash_web/components/lightbox.ex`**

```elixir
defmodule MobileCarWashWeb.Lightbox do
  @moduledoc """
  Fullscreen tap-to-view photo overlay ("lightbox everywhere").

  Render `<.lightbox_root />` ONCE per LiveView that shows photos. The
  overlay is dormant until the `Lightbox` JS hook opens it; all behavior
  is client-side (zero server events). Photos opt in with:

      <img src={...} alt={...} data-lightbox="group-name" />

  Optional `data-lightbox-caption={caption}` shows a caption line.
  Before/after sliders opt in with an expand button:

      <button data-lightbox-slider data-before-url={...} data-after-url={...}>

  Spec: docs/superpowers/specs/2026-07-12-lightbox-everywhere-design.md
  """
  use Phoenix.Component

  @doc "The overlay skeleton. Hidden until the Lightbox hook opens it."
  def lightbox_root(assigns) do
    ~H"""
    <div
      id="lightbox-root"
      phx-hook="Lightbox"
      phx-update="ignore"
      class="fixed inset-0 z-[60] hidden bg-black/90 transition-opacity duration-200"
      role="dialog"
      aria-modal="true"
      aria-label="Photo viewer"
    >
      <div data-role="backdrop" class="absolute inset-0"></div>

      <figure
        data-role="stage"
        class="pointer-events-none absolute inset-0 flex items-center justify-center p-4"
      >
        <img data-role="image" class="pointer-events-auto max-h-full max-w-full object-contain" />
        <div
          data-role="slider-stage"
          class="pointer-events-auto relative hidden aspect-[4/3] w-full max-w-2xl cursor-ew-resize select-none touch-none overflow-hidden rounded-xl"
        >
          <img
            data-role="slider-after"
            alt="After"
            class="pointer-events-none absolute inset-0 h-full w-full object-cover"
          />
          <img
            data-role="slider-before"
            alt="Before"
            class="pointer-events-none absolute inset-0 h-full w-full object-cover"
            style="clip-path: inset(0 50% 0 0)"
          />
          <span class="badge badge-sm pointer-events-none absolute left-2 top-2 border-0 bg-base-100/80">
            Before
          </span>
          <span class="badge badge-sm pointer-events-none absolute right-2 top-2 border-0 bg-base-100/80">
            After
          </span>
          <div
            data-role="slider-divider"
            class="pointer-events-none absolute inset-y-0 w-0.5 bg-base-100 shadow"
            style="left: 50%"
          >
            <div class="absolute left-0 top-1/2 flex h-9 w-9 -translate-x-1/2 -translate-y-1/2 items-center justify-center rounded-full bg-base-100 text-sm text-base-content/60 shadow-md">
              ⇔
            </div>
          </div>
        </div>
        <p data-role="load-error" class="hidden text-sm text-white/90">
          Couldn't load photo — try again later.
        </p>
      </figure>

      <button
        type="button"
        data-role="close"
        aria-label="Close photo viewer"
        class="btn btn-circle btn-sm absolute right-3 top-3 border-0 bg-white/15 text-white"
      >
        ✕
      </button>
      <button
        type="button"
        data-role="prev"
        aria-label="Previous photo"
        class="btn btn-circle absolute left-2 top-1/2 hidden -translate-y-1/2 border-0 bg-white/15 text-white disabled:opacity-30"
      >
        ‹
      </button>
      <button
        type="button"
        data-role="next"
        aria-label="Next photo"
        class="btn btn-circle absolute right-2 top-1/2 hidden -translate-y-1/2 border-0 bg-white/15 text-white disabled:opacity-30"
      >
        ›
      </button>

      <p
        data-role="counter"
        aria-live="polite"
        class="absolute bottom-10 left-1/2 hidden -translate-x-1/2 text-xs text-white/80"
      >
      </p>
      <p
        data-role="caption"
        class="absolute bottom-4 left-1/2 hidden max-w-[90%] -translate-x-1/2 truncate text-sm text-white"
      >
      </p>
    </div>
    """
  end
end
```

- [ ] **Step 4: Run the component test — expect pass**

Run: `mix test test/mobile_car_wash_web/components/lightbox_test.exs`
Expected: PASS.

- [ ] **Step 5: Create `assets/js/hooks/lightbox.js`**

```js
// Fullscreen photo viewer ("lightbox everywhere"). One instance per page,
// attached to the overlay root from MobileCarWashWeb.Lightbox.lightbox_root/1.
//
// Opt-in DOM contracts (see the design spec):
//   <img data-lightbox="group">   tap to view; DOM order = gallery order;
//                                 optional data-lightbox-caption
//   <button data-lightbox-slider data-before-url=... data-after-url=...>
//                                 fullscreen before/after scrub
//
// The gallery is SNAPSHOTTED at open time, so LiveView re-renders (PubSub
// photo updates) can never break an open lightbox. The next open
// re-snapshots.
import {attachScrub} from "../slider_core"

const SWIPE_PX = 40
const SLIDER_REST_P = 50 // the page slider's post-wipe rest position

export const Lightbox = {
  mounted() {
    const q = sel => this.el.querySelector(sel)
    this.els = {
      backdrop: q('[data-role="backdrop"]'),
      image: q('[data-role="image"]'),
      sliderStage: q('[data-role="slider-stage"]'),
      sliderBefore: q('[data-role="slider-before"]'),
      sliderAfter: q('[data-role="slider-after"]'),
      sliderDivider: q('[data-role="slider-divider"]'),
      loadError: q('[data-role="load-error"]'),
      close: q('[data-role="close"]'),
      prev: q('[data-role="prev"]'),
      next: q('[data-role="next"]'),
      counter: q('[data-role="counter"]'),
      caption: q('[data-role="caption"]')
    }
    this.items = []
    this.index = 0
    this.mode = null
    this.opener = null
    this.scrub = null
    this.swipeStart = null

    // One delegated listener opens everything.
    this.onDocClick = event => {
      const sliderBtn = event.target.closest("[data-lightbox-slider]")
      if (sliderBtn) return this.openSlider(sliderBtn)
      const thumb = event.target.closest("[data-lightbox]")
      if (thumb && !this.el.contains(thumb)) this.openImage(thumb)
    }
    document.addEventListener("click", this.onDocClick)

    this.onKeydown = event => {
      if (!this.isOpen()) return
      if (event.key === "Escape") this.close()
      else if (event.key === "ArrowLeft" && this.mode === "image") this.step(-1)
      else if (event.key === "ArrowRight" && this.mode === "image") this.step(1)
      else if (event.key === "Tab") this.trapTab(event)
    }
    document.addEventListener("keydown", this.onKeydown)

    this.els.close.addEventListener("click", () => this.close())
    this.els.backdrop.addEventListener("click", () => this.close())
    this.els.prev.addEventListener("click", () => this.step(-1))
    this.els.next.addEventListener("click", () => this.step(1))

    this.els.image.addEventListener("error", () => {
      if (!this.isOpen() || this.mode !== "image") return
      this.els.image.classList.add("hidden")
      this.els.loadError.classList.remove("hidden")
    })

    // Horizontal swipe navigates (image mode only; slider mode owns drag).
    this.el.addEventListener("pointerdown", event => {
      if (this.mode === "image") this.swipeStart = event.clientX
    })
    this.el.addEventListener("pointerup", event => {
      if (this.swipeStart === null || this.mode !== "image") return
      const dx = event.clientX - this.swipeStart
      this.swipeStart = null
      if (Math.abs(dx) >= SWIPE_PX) this.step(dx < 0 ? 1 : -1)
    })
  },

  destroyed() {
    document.removeEventListener("click", this.onDocClick)
    document.removeEventListener("keydown", this.onKeydown)
    document.documentElement.style.overflow = ""
    if (this.scrub) this.scrub.detach()
  },

  isOpen() {
    return !this.el.classList.contains("hidden")
  },

  openImage(thumb) {
    const group = thumb.getAttribute("data-lightbox")
    const members = [...document.querySelectorAll(`[data-lightbox="${CSS.escape(group)}"]`)]
    this.items = members.map(el => ({
      src: el.getAttribute("src"),
      alt: el.getAttribute("alt") || "",
      caption: el.getAttribute("data-lightbox-caption") || ""
    }))
    this.index = Math.max(0, members.indexOf(thumb))
    this.mode = "image"
    this.open(thumb)
    this.render()
  },

  openSlider(btn) {
    this.mode = "slider"
    this.els.sliderBefore.src = btn.getAttribute("data-before-url")
    this.els.sliderAfter.src = btn.getAttribute("data-after-url")
    this.open(btn)
    this.render()
    if (this.scrub) this.scrub.detach()
    this.scrub = attachScrub(this.els.sliderStage, {
      before: this.els.sliderBefore,
      divider: this.els.sliderDivider
    })
    this.scrub.setP(SLIDER_REST_P)
  },

  open(opener) {
    this.opener = opener
    this.el.classList.remove("hidden")
    const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches
    if (!reducedMotion) {
      this.el.style.opacity = "0"
      requestAnimationFrame(() => (this.el.style.opacity = "1"))
    } else {
      this.el.style.opacity = "1"
    }
    document.documentElement.style.overflow = "hidden"
    this.els.close.focus()
  },

  close() {
    this.el.classList.add("hidden")
    document.documentElement.style.overflow = ""
    if (this.scrub) {
      this.scrub.detach()
      this.scrub = null
    }
    this.mode = null
    if (this.opener && this.opener.isConnected) this.opener.focus()
    this.opener = null
  },

  step(delta) {
    const next = this.index + delta
    if (next < 0 || next >= this.items.length) return
    this.index = next
    this.render()
  },

  render() {
    const imageMode = this.mode === "image"
    this.els.image.classList.toggle("hidden", !imageMode)
    this.els.sliderStage.classList.toggle("hidden", imageMode)
    this.els.loadError.classList.add("hidden")

    const multi = imageMode && this.items.length > 1
    this.els.prev.classList.toggle("hidden", !multi)
    this.els.next.classList.toggle("hidden", !multi)
    this.els.counter.classList.toggle("hidden", !multi)

    if (imageMode) {
      const item = this.items[this.index]
      this.els.image.src = item.src
      this.els.image.alt = item.alt
      this.els.counter.textContent = `${this.index + 1} of ${this.items.length}`
      this.els.prev.disabled = this.index === 0
      this.els.next.disabled = this.index === this.items.length - 1
      this.els.caption.textContent = item.caption
      this.els.caption.classList.toggle("hidden", item.caption === "")
    } else {
      this.els.caption.classList.add("hidden")
    }
  },

  // Keep Tab cycling within the overlay's visible, enabled buttons.
  trapTab(event) {
    const focusables = [this.els.close, this.els.prev, this.els.next].filter(
      b => !b.classList.contains("hidden") && !b.disabled
    )
    if (focusables.length === 0) return
    const i = focusables.indexOf(document.activeElement)
    const last = focusables.length - 1
    const target = event.shiftKey
      ? i <= 0
        ? focusables[last]
        : focusables[i - 1]
      : i === -1 || i === last
        ? focusables[0]
        : focusables[i + 1]
    target.focus()
    event.preventDefault()
  }
}
```

- [ ] **Step 6: Register the hook in `assets/js/app.js`**

Add the import after the `ShareWashCard` import:

```js
import {Lightbox} from "./hooks/lightbox"
```

And add `Lightbox` to the hooks map (line ~58):

```js
  hooks: {...colocatedHooks, Sortable, DispatchMap, AddressMap, ClipboardCopy, PriceCountUp, ImageDownscale, BeforeAfterSlider, ShareWashCard, Lightbox},
```

- [ ] **Step 7: Verify bundle + test**

Run: `mix assets.build && mix test test/mobile_car_wash_web/components/lightbox_test.exs`
Expected: build exits 0, test PASSES.

- [ ] **Step 8: Commit**

```bash
mix format
git add lib/mobile_car_wash_web/components/lightbox.ex assets/js/hooks/lightbox.js assets/js/app.js test/mobile_car_wash_web/components/lightbox_test.exs
git commit -m "Add Lightbox overlay component and client-side hook"
```

---

### Task 3: Wire the customer status page (strips, grids, problem thumbs)

**Files:**
- Modify: `lib/mobile_car_wash_web/live/appointment_status_live.ex` (~L283–341 during-wash grid, ~L391–400 more-photos strip, ~L481–487 problem thumbs, ~L360–371 reveal img alts, module top for import, end of render for root)
- Test: `test/mobile_car_wash_web/live/appointment_status_live_test.exs`

**Interfaces:**
- Consumes: `<.lightbox_root />` + `data-lightbox` contract from Task 2.
- Produces: groups `"wash-photos"`, `"more-photos"`, `"problem-photos"` on this page.

- [ ] **Step 1: Write the failing tests** (append a new `describe` block; reuse the file's existing `register_customer/0`, `sign_in/2`, `create_appointment/2`, `create_photo/4` helpers — read `describe "reveal mode (completed wash)"` at ~L203 for the mount pattern)

```elixir
  describe "lightbox wiring" do
    test "completed page renders lightbox root once and wires unpaired + problem photos", %{
      conn: conn
    } do
      customer = register_customer()
      appt = create_appointment(customer, :completed)
      create_photo(appt, :before, :front, "/uploads/front-b.jpg")
      create_photo(appt, :after, :front, "/uploads/front-a.jpg")
      create_photo(appt, :before, :interior, "/uploads/interior-b.jpg")
      create_photo(appt, :problem_area, :hood, "/uploads/problem.jpg")

      {:ok, _view, html} = conn |> sign_in(customer) |> live(~p"/appointments/#{appt.id}/status")

      assert html =~ ~s(id="lightbox-root")
      assert html =~ ~s(phx-hook="Lightbox")
      # unpaired interior before-photo goes to the More photos strip
      assert html =~ ~s(data-lightbox="more-photos")
      assert html =~ ~s(data-lightbox="problem-photos")
      # every wired img has alt text
      refute html =~ ~r/<img(?![^>]*alt=)[^>]*data-lightbox/
    end

    test "during-wash grid wires wash photos with alt", %{conn: conn} do
      customer = register_customer()
      appt = create_appointment(customer, :confirmed)
      create_photo(appt, :before, :front, "/uploads/front-b.jpg")

      {:ok, _view, html} = conn |> sign_in(customer) |> live(~p"/appointments/#{appt.id}/status")

      assert html =~ ~s(data-lightbox="wash-photos")
      assert html =~ ~s(alt="Before — Front")
      assert html =~ ~s(id="lightbox-root")
    end
  end
```

Adapt the mount call and helper arity to what the existing describe blocks actually use (they are the source of truth — e.g. if `create_appointment` needs different statuses for the live grid, copy the status used by `describe "photo loading"`). The assertions are the contract; keep them verbatim.

- [ ] **Step 2: Run — expect failure**

Run: `mix test test/mobile_car_wash_web/live/appointment_status_live_test.exs`
Expected: new tests FAIL (`lightbox-root` not found); all pre-existing tests PASS.

- [ ] **Step 3: Wire the templates**

At the module top (below `use MobileCarWashWeb, :live_view`):

```elixir
import MobileCarWashWeb.Lightbox, only: [lightbox_root: 1]
```

During-wash grid — before cell img (~L316) becomes:

```heex
<img
  :if={before_p}
  src={before_p.file_path}
  alt={"Before — #{area.label}"}
  data-lightbox="wash-photos"
  class="w-full h-full object-cover cursor-zoom-in"
/>
```

After cell img (~L323) becomes:

```heex
<img
  :if={after_p}
  src={after_p.file_path}
  alt={"After — #{area.label}"}
  data-lightbox="wash-photos"
  class="w-full h-full object-cover cursor-zoom-in"
/>
```

Reveal slider images get alt only (NOT `data-lightbox` — the container owns pointer events; fullscreen comes from Task 4's expand button). After img (~L360):

```heex
<img
  src={pair.after.file_path}
  crossorigin="anonymous"
  alt={"After — #{pair.label}"}
  class="absolute inset-0 w-full h-full object-cover pointer-events-none"
/>
```

Before img (~L365): add `alt={"Before — #{pair.label}"}` the same way (keep `data-role="before"` and the `style` attribute).

More-photos strip img (~L394) becomes:

```heex
<img
  :for={photo <- @unpaired_photos}
  src={photo.file_path}
  alt={photo.caption || "Wash photo"}
  data-lightbox="more-photos"
  data-lightbox-caption={photo.caption}
  class="w-24 h-24 object-cover rounded-lg flex-shrink-0 cursor-zoom-in"
/>
```

Problem thumbs img (~L484) becomes:

```heex
<img
  src={photo.file_path}
  alt={photo.caption || "Problem area photo"}
  data-lightbox="problem-photos"
  data-lightbox-caption={photo.caption}
  class="w-24 h-24 object-cover rounded-lg cursor-zoom-in"
/>
```

Add `<.lightbox_root />` as the LAST child inside the outermost element of `render/1` (after the share modal markup).

- [ ] **Step 4: Run — expect pass**

Run: `mix test test/mobile_car_wash_web/live/appointment_status_live_test.exs`
Expected: ALL pass.

- [ ] **Step 5: Commit**

```bash
mix format
git add lib/mobile_car_wash_web/live/appointment_status_live.ex test/mobile_car_wash_web/live/appointment_status_live_test.exs
git commit -m "Wire status page photos into the lightbox"
```

---

### Task 4: Slider expand button (fullscreen scrub) + retarget dead attributes

**Files:**
- Modify: `lib/mobile_car_wash_web/live/appointment_status_live.ex` (~L350–388: the `:for={pair <- @pairs}` block)
- Test: `test/mobile_car_wash_web/live/appointment_status_live_test.exs` (~L215–225, ~L290–315 — assertions on `data-before-url`/`data-after-url`)

**Interfaces:**
- Consumes: `[data-lightbox-slider]` contract from Task 2.
- Produces: per-pair expand button; slider container NO LONGER carries `data-before-url`/`data-after-url`.

- [ ] **Step 1: Update the tests first.** In `describe "reveal mode (completed wash)"` and the later blocks, the assertions `assert html =~ ~s(data-before-url="/uploads/front-b.jpg")` still pass after the move (same attribute string, new element) — so ADD context assertions making the button the asserted carrier. Immediately after each existing `data-before-url`/`data-after-url` assertion pair, add:

```elixir
      assert html =~ ~s(data-lightbox-slider)
      # the slider container itself must no longer carry the URLs
      refute html =~ ~r/id="reveal-[^"]*"[^>]*data-before-url/
```

Also add one new test in `describe "lightbox wiring"` (from Task 3):

```elixir
    test "each pair gets a fullscreen expand button carrying the pair URLs", %{conn: conn} do
      customer = register_customer()
      appt = create_appointment(customer, :completed)
      create_photo(appt, :before, :front, "/uploads/front-b.jpg")
      create_photo(appt, :after, :front, "/uploads/front-a.jpg")

      {:ok, _view, html} = conn |> sign_in(customer) |> live(~p"/appointments/#{appt.id}/status")

      assert html =~ ~s(data-lightbox-slider)
      assert html =~ ~s(data-before-url="/uploads/front-b.jpg")
      assert html =~ ~s(data-after-url="/uploads/front-a.jpg")
      assert html =~ ~s(aria-label="View Front comparison fullscreen")
    end
```

(Adapt "Front" to the actual `pair.label` value the page renders for `:front` — check the existing reveal tests.)

- [ ] **Step 2: Run — expect failure**

Run: `mix test test/mobile_car_wash_web/live/appointment_status_live_test.exs`
Expected: new/updated assertions FAIL (`data-lightbox-slider` absent; container still carries URLs).

- [ ] **Step 3: Move the attributes and add the button.** The `:for={pair <- @pairs}` wrapper div gains `class="relative"`; the slider container loses `data-before-url`/`data-after-url`; a sibling button lands AFTER the container (outside `phx-update="ignore"`):

```heex
<div :for={pair <- @pairs} class="relative">
  <p class="text-xs text-base-content/70 mb-1">{pair.label}</p>
  <div
    id={"reveal-#{pair.area}"}
    phx-hook="BeforeAfterSlider"
    phx-update="ignore"
    class="relative aspect-[4/3] rounded-xl overflow-hidden bg-base-200 select-none touch-none cursor-ew-resize"
  >
    <%!-- existing children unchanged (after img, before img, badges, divider) --%>
  </div>
  <button
    type="button"
    class="btn btn-circle btn-sm absolute bottom-2 right-2 z-10 border-0 bg-base-100/80"
    aria-label={"View #{pair.label} comparison fullscreen"}
    data-lightbox-slider
    data-before-url={pair.before.file_path}
    data-after-url={pair.after.file_path}
  >
    ⤢
  </button>
</div>
```

Keep every existing child of the reveal container byte-identical.

- [ ] **Step 4: Run — expect pass**

Run: `mix test test/mobile_car_wash_web/live/appointment_status_live_test.exs`
Expected: ALL pass.

- [ ] **Step 5: Commit**

```bash
mix format
git add lib/mobile_car_wash_web/live/appointment_status_live.ex test/mobile_car_wash_web/live/appointment_status_live_test.exs
git commit -m "Add fullscreen expand button to reveal sliders"
```

---

### Task 5: Wire the tech checklist (problem strip + before/after tiles)

**Files:**
- Modify: `lib/mobile_car_wash_web/live/checklist_live.ex` (~L410–417 problem strip; ~L829–835 photo_tile imgs; module top; end of render)
- Test: `test/mobile_car_wash_web/live/checklist_live_test.exs`

**Interfaces:**
- Consumes: Task 2's contracts.
- Produces: groups `"problem-photos"` and `"checklist-photos"` on the checklist page.

- [ ] **Step 1: Write the failing tests** (new `describe "lightbox wiring"`; reuse this file's `create_tech_customer/1`, `create_tech_record/1`, `sign_in/2`, `create_customer/1`, `create_appointment/3`, `create_checklist/2` helpers — copy the mount pattern from `describe "active wash regions"` ~L188, and create photos with `Ash` the same way neighboring tests do; if the file has no photo fixture, add one modeled on `create_photo/4` from `appointment_status_live_test.exs:97`):

```elixir
  describe "lightbox wiring" do
    test "problem strip and captured tiles are lightboxed with alt; root renders once" do
      # mount an active checklist whose appointment has:
      #   one :problem_area photo (caption "Scratch on hood")
      #   one captured :before photo for the first key area
      # ... setup per the file's existing helpers ...

      assert html =~ ~s(id="lightbox-root")
      assert html =~ ~s(data-lightbox="problem-photos")
      assert html =~ ~s(data-lightbox-caption="Scratch on hood")
      assert html =~ ~s(data-lightbox="checklist-photos")
      # ghost overlay img must NOT be wired
      refute html =~ ~r/opacity-20[^>]*data-lightbox/
      refute html =~ ~r/<img(?![^>]*alt=)[^>]*data-lightbox/
    end
  end
```

The setup comment is the only permitted adaptation point; the assertions are the contract.

- [ ] **Step 2: Run — expect failure**

Run: `mix test test/mobile_car_wash_web/live/checklist_live_test.exs`
Expected: new test FAILS on `lightbox-root`; pre-existing tests PASS.

- [ ] **Step 3: Wire the templates**

Module top:

```elixir
import MobileCarWashWeb.Lightbox, only: [lightbox_root: 1]
```

Problem strip img (~L412) becomes:

```heex
<img
  src={photo.file_path}
  alt={photo.caption || "Customer problem photo"}
  data-lightbox="problem-photos"
  data-lightbox-caption={photo.caption}
  class="h-20 w-20 rounded-lg border-2 border-warning object-cover cursor-zoom-in"
/>
```

`photo_tile/1` captured img (~L830) becomes:

```heex
<img
  src={@photo.file_path}
  alt={"#{if @type == :before, do: "Before", else: "After"} — #{@area.label}"}
  data-lightbox="checklist-photos"
  class="h-full w-full object-cover cursor-zoom-in"
/>
```

(If `@type` values differ from `:before`/`:after`, mirror whatever `tile-#{@type}-...` renders — check the ids in existing tile tests.) The ghost img (~L835) gets `alt=""` and NO `data-lightbox` (decorative). The empty-tile ghost (~L864–868) likewise gets `alt=""` only.

Add `<.lightbox_root />` as the last child of `render/1`'s outermost element.

- [ ] **Step 4: Run — expect pass**

Run: `mix test test/mobile_car_wash_web/live/checklist_live_test.exs`
Expected: ALL pass.

- [ ] **Step 5: Commit**

```bash
mix format
git add lib/mobile_car_wash_web/live/checklist_live.ex test/mobile_car_wash_web/live/checklist_live_test.exs
git commit -m "Wire tech checklist photos into the lightbox"
```

---

### Task 6: Wire the uploader preview grid + appointments page

**Files:**
- Modify: `lib/mobile_car_wash_web/components/photo_uploader.ex` (`preview_grid/1`, ~L253–259)
- Modify: `lib/mobile_car_wash_web/live/appointments_live.ex` (module top; end of render)
- Test: `test/mobile_car_wash_web/components/photo_uploader_test.exs`, `test/mobile_car_wash_web/live/appointments_photo_upload_test.exs`

**Interfaces:**
- Consumes: Task 2's contracts.
- Produces: group `"uploaded-photos"` inside `preview_grid/1` (covers the appointments problem-photo modal and every other uploader consumer).

- [ ] **Step 1: Write the failing tests.** In `photo_uploader_test.exs` add:

```elixir
  test "preview_grid wires photos into the lightbox" do
    photos = [
      %{file_path: "/uploads/a.jpg", caption: "Bird droppings", ai_tags: nil},
      %{file_path: "/uploads/b.jpg", caption: nil, ai_tags: nil}
    ]

    html = render_component(&PhotoUploader.preview_grid/1, %{photos: photos})

    assert html =~ ~s(data-lightbox="uploaded-photos")
    assert html =~ ~s(data-lightbox-caption="Bird droppings")
    assert html =~ ~s(cursor-zoom-in)
  end
```

(Match the photo-map shape other `preview_grid` tests in the file use — if they pass structs or extra keys, copy that shape.) In `appointments_photo_upload_test.exs`, add to an existing successful-mount test:

```elixir
      assert html =~ ~s(id="lightbox-root")
```

- [ ] **Step 2: Run — expect failure**

Run: `mix test test/mobile_car_wash_web/components/photo_uploader_test.exs test/mobile_car_wash_web/live/appointments_photo_upload_test.exs`
Expected: new assertions FAIL.

- [ ] **Step 3: Implement.** `preview_grid/1` img (~L255) becomes:

```heex
<img
  src={photo.file_path}
  class="w-full aspect-square object-cover rounded-2xl shadow-sm cursor-zoom-in"
  alt={photo.caption || "Problem area photo"}
  data-lightbox="uploaded-photos"
  data-lightbox-caption={photo.caption}
/>
```

In `appointments_live.ex`: add the `import MobileCarWashWeb.Lightbox, only: [lightbox_root: 1]` and `<.lightbox_root />` (last child of the outermost render element).

- [ ] **Step 4: Run — expect pass**

Run: `mix test test/mobile_car_wash_web/components/photo_uploader_test.exs test/mobile_car_wash_web/live/appointments_photo_upload_test.exs`
Expected: ALL pass. (Note: `photo_uploader_test.exs` has 2 pre-existing compiler warnings — ignore, they're on the handoff backlog.)

- [ ] **Step 5: Commit**

```bash
mix format
git add lib/mobile_car_wash_web/components/photo_uploader.ex lib/mobile_car_wash_web/live/appointments_live.ex test/mobile_car_wash_web/components/photo_uploader_test.exs test/mobile_car_wash_web/live/appointments_photo_upload_test.exs
git commit -m "Wire uploader preview grid into the lightbox"
```

---

### Task 7: Wire the tech job brief

**Files:**
- Modify: `lib/mobile_car_wash_web/live/tech/job_live.ex` (~L270–274 problem grid img; module top; end of render)
- Test: `test/mobile_car_wash_web/live/tech/job_live_test.exs`

**Interfaces:**
- Consumes: Task 2's contracts.
- Produces: group `"problem-photos"` on the job brief page.

- [ ] **Step 1: Write the failing test** (append to the existing problem-photos describe block in `job_live_test.exs`, reusing its setup):

```elixir
    test "problem photos are lightboxed and the overlay root renders" do
      # reuse this describe block's existing setup that creates a job with problem photos

      assert html =~ ~s(id="lightbox-root")
      assert html =~ ~s(data-lightbox="problem-photos")
    end
```

- [ ] **Step 2: Run — expect failure**

Run: `mix test test/mobile_car_wash_web/live/tech/job_live_test.exs`
Expected: new test FAILS; pre-existing PASS.

- [ ] **Step 3: Implement.** The img (~L270, already has `alt={problem_photo_label(photo)}`) gains:

```heex
<img
  src={photo.file_path}
  alt={problem_photo_label(photo)}
  data-lightbox="problem-photos"
  data-lightbox-caption={photo.caption}
  class="aspect-square w-full object-cover cursor-zoom-in"
/>
```

Add the import + `<.lightbox_root />` (last child of `render/1`'s outermost element).

- [ ] **Step 4: Run — expect pass**

Run: `mix test test/mobile_car_wash_web/live/tech/job_live_test.exs`
Expected: ALL pass.

- [ ] **Step 5: Commit**

```bash
mix format
git add lib/mobile_car_wash_web/live/tech/job_live.ex test/mobile_car_wash_web/live/tech/job_live_test.exs
git commit -m "Wire tech job brief problem photos into the lightbox"
```

---

### Task 8: Full gate

**Files:** none new — verification only.

- [ ] **Step 1: Run the full gate**

Run: `mix precommit`
Expected: compile with no new warnings, format clean, 1471 pre-existing + all new tests, 0 failures.

- [ ] **Step 2: Rebuild assets one last time**

Run: `mix assets.build`
Expected: exits 0.

- [ ] **Step 3: Commit anything `mix format` touched**

```bash
git status --short   # if clean, done; else:
git add -u && git commit -m "Format"
```

---

## Manual on-phone verification (post-merge, add to deploy checklist)

Not automatable — verify on a real phone after deploy:
1. Each surface: tap a photo → fullscreen opens instantly; ✕ / backdrop / Escape (desktop) close it; focus returns.
2. Problem strip with 3+ photos: swipe and chevrons navigate; counter updates.
3. Reveal slider: ⤢ button opens fullscreen scrub at the halfway rest; drag scrubs; page slider still scrubs and wipes normally (the Task 1 regression risk).
4. Reduced-motion (iOS: Settings → Accessibility → Motion): overlay opens without fade; page slider still skips its wipe.
