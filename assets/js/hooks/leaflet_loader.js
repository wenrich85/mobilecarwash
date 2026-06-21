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
