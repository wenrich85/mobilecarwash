// Leaflet loaded on demand via CDN — keeps it out of the main JS bundle (~148KB saved)
let L = null

function loadLeaflet() {
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

const ZONE_COLORS = {
  nw: "#1E2A38",
  ne: "#3A7CA5",
  sw: "#5EA8CF",
  se: "#2E6384",
}

const STATUS_COLORS = {
  pending: "#ADB5BD",
  confirmed: "#3A7CA5",
  in_progress: "#E6A817",
  completed: "#2A9D6F",
}

// SVG vehicle silhouettes — compact, recognizable at small sizes
const VEHICLE_SVG = {
  car: `<svg viewBox="0 0 32 20" fill="currentColor" xmlns="http://www.w3.org/2000/svg">
    <path d="M5 12h22v4c0 .5-.4 1-1 1H6c-.6 0-1-.5-1-1v-4z" opacity=".7"/>
    <path d="M7 8l3-4h12l3 4H7z"/>
    <path d="M3 12h26v1H3z" opacity=".5"/>
    <circle cx="9" cy="17" r="2.5"/><circle cx="23" cy="17" r="2.5"/>
    <circle cx="9" cy="17" r="1" fill="white" opacity=".5"/>
    <circle cx="23" cy="17" r="1" fill="white" opacity=".5"/>
  </svg>`,

  suv_van: `<svg viewBox="0 0 34 22" fill="currentColor" xmlns="http://www.w3.org/2000/svg">
    <path d="M4 13h26v5c0 .5-.4 1-1 1H5c-.6 0-1-.5-1-1v-5z" opacity=".7"/>
    <path d="M6 6h20c1 0 2 .5 2.5 1.5L30 13H4l2-5.5C6.5 6.5 6 6 6 6z"/>
    <rect x="8" y="7" width="6" height="5" rx=".5" fill="white" opacity=".3"/>
    <rect x="16" y="7" width="6" height="5" rx=".5" fill="white" opacity=".3"/>
    <circle cx="9" cy="19" r="2.5"/><circle cx="25" cy="19" r="2.5"/>
    <circle cx="9" cy="19" r="1" fill="white" opacity=".5"/>
    <circle cx="25" cy="19" r="1" fill="white" opacity=".5"/>
  </svg>`,

  pickup: `<svg viewBox="0 0 36 20" fill="currentColor" xmlns="http://www.w3.org/2000/svg">
    <path d="M3 12h14v5c0 .5-.4 1-1 1H4c-.6 0-1-.5-1-1v-5z" opacity=".7"/>
    <path d="M5 8l3-4h8l2 4H5z"/>
    <rect x="19" y="10" width="14" height="7" rx="1" opacity=".5"/>
    <line x1="19" y1="10" x2="19" y2="17" stroke="currentColor" stroke-width=".5" opacity=".8"/>
    <circle cx="9" cy="17" r="2.5"/><circle cx="27" cy="17" r="2.5"/>
    <circle cx="9" cy="17" r="1" fill="white" opacity=".5"/>
    <circle cx="27" cy="17" r="1" fill="white" opacity=".5"/>
  </svg>`,
}

function vehicleIcon(pin) {
  const color = STATUS_COLORS[pin.status] || "#ADB5BD"
  const zoneColor = ZONE_COLORS[pin.zone] || "#536C8B"
  const svg = VEHICLE_SVG[pin.vehicle_type] || VEHICLE_SVG.car

  return L.divIcon({
    className: "",
    html: `<div style="
      display:flex; align-items:center; justify-content:center;
      width:44px; height:36px;
      background:${color};
      border:2px solid ${zoneColor};
      border-radius:8px;
      color:white;
      box-shadow:0 2px 8px rgba(0,0,0,0.3);
      padding:4px;
    ">${svg}</div>`,
    iconSize: [44, 36],
    iconAnchor: [22, 36],
    popupAnchor: [0, -36],
  })
}

const STADIA_API_KEY = window.stadiaApiKey || null

const TILES = {
  light: {
    url: "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
    attr: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>',
  },
  dark: STADIA_API_KEY
    ? {
        url: `https://tiles.stadiamaps.com/tiles/alidade_smooth_dark/{z}/{x}/{y}{r}.png?api_key=${STADIA_API_KEY}`,
        attr: '&copy; <a href="https://www.stadiamaps.com/">Stadia</a> &copy; <a href="https://openmaptiles.org/">OpenMapTiles</a> &copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>',
      }
    : {
        url: "https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png",
        attr: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> &copy; <a href="https://carto.com/attributions">CARTO</a>',
      },
}

function isDarkMode() {
  return document.documentElement.getAttribute("data-theme") === "dark" ||
    (!document.documentElement.hasAttribute("data-theme") &&
      window.matchMedia("(prefers-color-scheme: dark)").matches)
}

export const DispatchMap = {
  async mounted() {
    // Load Leaflet on demand (not in main bundle)
    L = await loadLeaflet()

    this.map = L.map(this.el, {
      scrollWheelZoom: true,
      zoomControl: true,
    }).setView([29.4241, -98.4936], 11)

    this.setTileLayer()
    this.markers = L.layerGroup().addTo(this.map)

    this.handleEvent("update_map_pins", ({ pins }) => {
      this.renderPins(pins)
    })

    // Watch for theme changes
    this._themeObserver = new MutationObserver(() => this.setTileLayer())
    this._themeObserver.observe(document.documentElement, {
      attributes: true,
      attributeFilter: ["data-theme"],
    })

    this._mediaQuery = window.matchMedia("(prefers-color-scheme: dark)")
    this._mediaHandler = () => this.setTileLayer()
    this._mediaQuery.addEventListener("change", this._mediaHandler)

    // Request initial pins from the server once hook is ready
    this.pushEvent("request_map_pins", {})

    setTimeout(() => this.map.invalidateSize(), 200)
  },

  setTileLayer() {
    const mode = isDarkMode() ? "dark" : "light"
    if (this._currentMode === mode) return
    this._currentMode = mode

    if (this._tileLayer) this.map.removeLayer(this._tileLayer)
    this._tileLayer = L.tileLayer(TILES[mode].url, {
      attribution: TILES[mode].attr,
      maxZoom: 18,
    }).addTo(this.map)
  },

  renderPins(pins) {
    this.markers.clearLayers()

    if (!pins || pins.length === 0) return

    const bounds = []

    pins.forEach((pin) => {
      const color = STATUS_COLORS[pin.status] || "#ADB5BD"
      const zoneColor = ZONE_COLORS[pin.zone] || "#536C8B"
      const vtype = pin.vehicle_type === "suv_van" ? "SUV/Van" : pin.vehicle_type === "pickup" ? "Pickup" : "Car"

      L.marker([pin.lat, pin.lng], { icon: vehicleIcon(pin) })
        .addTo(this.markers)
        .bindPopup(`
          <div style="font-family:system-ui;min-width:150px">
            <strong>${pin.service}</strong>
            <span style="color:#888;font-size:12px"> · ${vtype}</span><br/>
            <span style="color:#666">${pin.customer}</span><br/>
            <span style="color:#666">${pin.time}</span><br/>
            <span style="display:inline-block;padding:1px 8px;border-radius:10px;font-size:11px;color:white;background:${color};margin-top:4px">
              ${pin.status}
            </span>
            ${pin.zone_label ? `<span style="display:inline-block;padding:1px 8px;border-radius:10px;font-size:11px;color:white;background:${zoneColor};margin-left:4px">${pin.zone_label}</span>` : ""}
          </div>
        `)

      bounds.push([pin.lat, pin.lng])
    })

    if (bounds.length > 0) {
      this.map.fitBounds(bounds, { padding: [40, 40], maxZoom: 14 })
    }
  },

  destroyed() {
    if (this._themeObserver) this._themeObserver.disconnect()
    if (this._mediaQuery) this._mediaQuery.removeEventListener("change", this._mediaHandler)
    if (this.map) this.map.remove()
  },
}
