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
    this.justSwiped = false

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
    this.els.backdrop.addEventListener("click", () => {
      if (this.justSwiped) {
        this.justSwiped = false
        return
      }
      this.close()
    })
    this.els.prev.addEventListener("click", () => this.step(-1))
    this.els.next.addEventListener("click", () => this.step(1))

    this.els.image.addEventListener("error", () => {
      if (!this.isOpen() || this.mode !== "image") return
      this.els.image.classList.add("hidden")
      this.els.loadError.classList.remove("hidden")
    })

    const sliderImgError = () => {
      if (!this.isOpen() || this.mode !== "slider") return
      this.els.sliderStage.classList.add("hidden")
      this.els.loadError.classList.remove("hidden")
    }
    this.els.sliderBefore.addEventListener("error", sliderImgError)
    this.els.sliderAfter.addEventListener("error", sliderImgError)

    // Horizontal swipe navigates (image mode only; slider mode owns drag).
    this.el.addEventListener("pointerdown", event => {
      this.justSwiped = false
      if (this.mode === "image") this.swipeStart = event.clientX
    })
    this.el.addEventListener("pointerup", event => {
      if (this.swipeStart === null || this.mode !== "image") return
      const dx = event.clientX - this.swipeStart
      this.swipeStart = null
      if (Math.abs(dx) >= SWIPE_PX) {
        this.justSwiped = true
        this.step(dx < 0 ? 1 : -1)
      }
    })
    this.el.addEventListener("pointercancel", () => (this.swipeStart = null))
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
    if (this.scrub) { this.scrub.detach(); this.scrub = null }
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
