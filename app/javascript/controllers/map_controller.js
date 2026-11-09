import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import * as L from "leaflet"

// Owns the Leaflet map. Pins live for the page's lifetime: they are added once
// per room id and never removed when a marker element disconnects, and re-titled
// when a marker element arrives with a new title.
export default class extends Controller {
  static targets = ["map"]
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
    // Turbo moves the permanent element on full visits, which disconnects and
    // reconnects this controller. The Leaflet map and pins live on the element
    // so pan/zoom survive; only the icon is rebuilt.
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
    if (!this.mapTarget.leafletMap) {
      const map = L.map(this.mapTarget, { doubleClickZoom: false })
        .setView(this.centerValue, this.zoomValue)
      L.tileLayer(this.tileUrlValue, { attribution: this.attributionValue, maxZoom: 19 }).addTo(map)
      // Registered once, so it must not capture this controller instance: after
      // Turbo moves the permanent element a new instance (with new targets) takes
      // over. Resolve the form from the permanent DOM at click time instead; those
      // nodes are the same across moves.
      const container = this.element
      let lastClickAt = -Infinity
      map.on("click", (event) => {
        const form = container.querySelector("#new_chatroom_form")
        if (!form) return
        // A double-click fires two click events; create only one room.
        if (event.originalEvent.timeStamp - lastClickAt < 300) return
        lastClickAt = event.originalEvent.timeStamp
        const { lat, lng } = event.latlng.wrap()
        form.querySelector("[name='chatroom[latitude]']").value = lat.toFixed(6)
        form.querySelector("[name='chatroom[longitude]']").value = lng.toFixed(6)
        form.requestSubmit()
      })
      map.on("zoomend", () => { this.element.dataset.mapCurrentZoom = map.getZoom() })
      this.element.dataset.mapCurrentZoom = map.getZoom()
      this.mapTarget.leafletMap = map
      this.mapTarget.pins = new Map()
    }
    this.map = this.mapTarget.leafletMap
    this.pins = this.mapTarget.pins

    // Scan the whole document, not just #markers: the panel's marker copy lives
    // outside the map container and may have connected before this controller.
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

  register(event) {
    this.add(event.detail)
  }

  // Leaflet treats string tooltip content as HTML; titles come from outside the app.
  textNode(text) {
    const el = document.createElement("span")
    el.textContent = text
    return el
  }

  // A room's title changes when its place name arrives. Update the pin in place.
  retitle(pin, title) {
    pin.options.title = title
    pin.options.alt = title
    const el = pin.getElement()
    if (el) {
      el.setAttribute("title", title)
      el.setAttribute("alt", title)
    }
    pin.setTooltipContent(this.textNode(title))
  }

  add({ id, lat, lng, title, url }) {
    if (!this.map) return

    const existing = this.pins.get(id)
    if (existing) {
      if (existing.options.title !== title) this.retitle(existing, title)
      return
    }

    const pin = L.marker([lat, lng], { icon: this.icon, title, alt: title })
      .bindTooltip(this.textNode(title))
      .on("click", () => Turbo.visit(url, { frame: "chatroom_panel", action: "advance" }))
      .addTo(this.map)
    this.pins.set(id, pin)
  }
}
