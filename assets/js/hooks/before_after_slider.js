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
