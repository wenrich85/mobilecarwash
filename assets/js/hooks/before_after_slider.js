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
