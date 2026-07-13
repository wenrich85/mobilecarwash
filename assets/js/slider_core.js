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
