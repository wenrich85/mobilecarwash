// Leaflet loaded on demand via CDN — keeps it out of the main JS bundle.
// Shared by DispatchMap (fleet) and AddressMap (booking).
let L = null

export function loadLeaflet() {
  return new Promise((resolve, reject) => {
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

    // Load JS from CDN. If it fails (CDN down / blocked / integrity mismatch),
    // reject so callers settle instead of hanging forever. Drop the dead tag so
    // a later mount can retry cleanly.
    const script = document.createElement("script")
    script.src = "https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"
    script.integrity = "sha256-20nQCchB9co0qIjJZRGuk2/Z9VM+kNiyxNV1lvTlZBo="
    script.crossOrigin = ""
    script.onload = () => {
      if (window.L) { L = window.L; resolve(L) }
      else reject(new Error("Leaflet loaded but window.L is undefined"))
    }
    script.onerror = () => {
      script.remove()
      reject(new Error("Failed to load Leaflet from CDN"))
    }
    document.head.appendChild(script)
  })
}
