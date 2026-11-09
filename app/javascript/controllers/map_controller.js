import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import * as L from "leaflet"

// Owns the Leaflet map. Pins live for the page's lifetime: they are added once
// per room id and never removed when a marker element disconnects.
export default class extends Controller {
  static targets = ["map", "form", "latitude", "longitude"]
  static values = {
    tileUrl: String,
    attribution: String,
    center: Array,
    zoom: Number,
    iconUrl: String,
    iconRetinaUrl: String,
    shadowUrl: String
  }

  connect() {
    this.pins = new Map()
    this.icon = L.icon({
      iconUrl: this.iconUrlValue,
      iconRetinaUrl: this.iconRetinaUrlValue,
      shadowUrl: this.shadowUrlValue,
      iconSize: [25, 41],
      iconAnchor: [12, 41],
      popupAnchor: [1, -34],
      tooltipAnchor: [16, -28],
      shadowSize: [41, 41]
    })
    this.map = L.map(this.mapTarget, { doubleClickZoom: false })
      .setView(this.centerValue, this.zoomValue)
    L.tileLayer(this.tileUrlValue, { attribution: this.attributionValue, maxZoom: 19 }).addTo(this.map)

    // Marker controllers may have connected before this one.
    document.querySelectorAll("[data-controller~='marker']").forEach((el) => {
      this.add({
        id: Number(el.dataset.markerIdValue),
        lat: Number(el.dataset.markerLatValue),
        lng: Number(el.dataset.markerLngValue),
        title: el.dataset.markerTitleValue,
        url: el.dataset.markerUrlValue
      })
    })
  }

  disconnect() {
    this.map?.remove()
    this.map = null
  }

  register(event) {
    this.add(event.detail)
  }

  add({ id, lat, lng, title, url }) {
    if (!this.map || this.pins.has(id)) return

    const pin = L.marker([lat, lng], { icon: this.icon, title, alt: title })
      .bindTooltip(title)
      .on("click", () => Turbo.visit(url, { frame: "chatroom_panel", action: "advance" }))
      .addTo(this.map)
    this.pins.set(id, pin)
  }
}
