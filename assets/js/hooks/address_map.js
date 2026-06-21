import { loadLeaflet } from "./leaflet_loader"

const SA_CENTER = [29.4241, -98.4936]

export const AddressMap = {
  async mounted() {
    let L
    try {
      L = await loadLeaflet()
    } catch (e) {
      // Map is a non-essential preview — the booking form still works without it.
      console.error("AddressMap: Leaflet failed to load", e)
      return
    }
    this._L = L

    const lat = parseFloat(this.el.dataset.lat)
    const lng = parseFloat(this.el.dataset.lng)
    const hasPoint = !Number.isNaN(lat) && !Number.isNaN(lng)
    const center = hasPoint ? [lat, lng] : SA_CENTER

    this.map = L.map(this.el, { scrollWheelZoom: false, zoomControl: true })
      .setView(center, hasPoint ? 15 : 11)

    L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
      attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>',
      maxZoom: 18,
    }).addTo(this.map)

    if (hasPoint) this.marker = L.marker(center).addTo(this.map)

    this.handleEvent("address_map_set", ({ lat, lng }) => {
      const p = [lat, lng]
      this.map.setView(p, 15)
      if (this.marker) this.marker.setLatLng(p)
      else this.marker = this._L.marker(p).addTo(this.map)
    })

    // Recompute size once the container actually has dimensions — it mounts
    // inside a progressively-revealed section, so a fixed delay is a guess.
    this._resizeObserver = new ResizeObserver(() => this.map.invalidateSize())
    this._resizeObserver.observe(this.el)
  },

  destroyed() {
    if (this._resizeObserver) this._resizeObserver.disconnect()
    if (this.map) this.map.remove()
  },
}
