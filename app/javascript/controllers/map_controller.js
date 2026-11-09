import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import * as L from "leaflet"

const LIVE_LIMIT = 20
const MOVE_DEBOUNCE_MS = 250
const MAX_ZOOM = 19
const CLUSTER_ZOOM_STEP = 2

// Owns the Leaflet map and what is drawn on it.
//
// The map fetches the rooms in the visible area (after it is created and after each pan or zoom)
// as a Turbo Stream that fills #markers with a marker-set element: pins, or in dense areas
// clusters with a count. The marker-set announces itself with marker-set:load, and this
// controller swaps the drawn set for the new one in one step.
//
// Single rooms arrive as marker elements (marker:connect), by role:
// - "panel": the open room. Kept on its own layer that no fetch clears.
// - "live": a room just created anywhere. Drawn if it falls in view (pins mode) or added to its
//   grid cell (clusters mode). Re-applied after a swap if it arrived after that fetch was sent.
// - "set": a fetched pin, or a place-name broadcast. Only re-titles a pin already drawn.
//
// Turbo moves the permanent map element on full visits, which disconnects and reconnects this
// controller. The Leaflet map and all marker state live on the #map element so they survive;
// handlers registered once on the map use only that state, never a controller instance.
export default class extends Controller {
  static targets = ["map"]
  static values = {
    tileUrl: String,
    attribution: String,
    center: Array,
    zoom: Number,
    markersUrl: String,
    iconUrl: String,
    iconRetinaUrl: String,
    shadowUrl: String
  }

  connect() {
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
    const created = !this.mapTarget.leafletMap
    if (created) this.createMap()
    this.map = this.mapTarget.leafletMap
    this.state = this.mapTarget.markerState

    // Scan the whole document: the panel's marker copy lives outside the map container and may
    // have connected before this controller.
    document.querySelectorAll("[data-controller~='marker']").forEach((el) => {
      this.handle({
        id: Number(el.dataset.markerIdValue),
        lat: Number(el.dataset.markerLatValue),
        lng: Number(el.dataset.markerLngValue),
        title: el.dataset.markerTitleValue,
        url: el.dataset.markerUrlValue,
        role: el.dataset.markerRoleValue || "live"
      })
    })
    if (created) this.state.fetchMarkers()
  }

  createMap() {
    const map = L.map(this.mapTarget, { doubleClickZoom: false })
      .setView(this.centerValue, this.zoomValue)
    L.tileLayer(this.tileUrlValue, { attribution: this.attributionValue, maxZoom: MAX_ZOOM }).addTo(map)

    const state = {
      panelLayer: L.layerGroup().addTo(map),
      panelPins: new Map(), // room id -> marker
      setLayer: L.layerGroup().addTo(map),
      setPins: new Map(), // room id -> marker
      clusters: new Map(), // "x,y" -> { lat, lng, count, marker }
      lone: new Map(), // "x,y" -> { id, lat, lng, marker } for single-room cells in clusters mode
      mode: "pins",
      cellSize: 0,
      live: [], // [{ detail, receivedAt }], the last LIVE_LIMIT live rooms
      requestedAt: -Infinity // when the fetch behind the set being drawn was sent
    }

    // Registered once, so these must not capture this controller instance: after Turbo moves
    // the permanent element a new instance (with new targets) takes over. Resolve the form from
    // the permanent DOM at click time instead; those nodes are the same across moves.
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
    map.on("zoomend", () => { container.dataset.mapCurrentZoom = map.getZoom() })
    container.dataset.mapCurrentZoom = map.getZoom()

    const markersUrl = this.markersUrlValue
    let inFlight = null
    state.fetchMarkers = async () => {
      inFlight?.abort()
      const request = inFlight = new AbortController()
      const requestedAt = performance.now()
      const url = `${markersUrl}?${boundsQuery(map)}`
      let body
      try {
        const response = await fetch(url, {
          headers: { Accept: "text/vnd.turbo-stream.html" },
          signal: request.signal
        })
        // A rejected request keeps the current set on the map.
        if (!response.ok) return
        body = await response.text()
      } catch {
        // Superseded (aborted), offline or a dropped connection: keep the current set; the
        // next pan or zoom fetches again.
        return
      }
      if (request.signal.aborted) return
      state.requestedAt = requestedAt
      Turbo.renderStreamMessage(body)
    }
    let moveTimer = null
    map.on("moveend", () => {
      clearTimeout(moveTimer)
      moveTimer = setTimeout(state.fetchMarkers, MOVE_DEBOUNCE_MS)
    })

    this.mapTarget.leafletMap = map
    this.mapTarget.markerState = state
  }

  register(event) {
    this.handle(event.detail)
  }

  // A fetched set arrived: build the new layer, show it, then drop the old one.
  load({ detail }) {
    const state = this.state
    const layer = L.layerGroup()
    const setPins = new Map()
    const clusters = new Map()
    const lone = new Map()
    for (const room of detail.pins) {
      // The open room is already pinned on the panel layer.
      const marker = state.panelPins.has(room.id) ? null : this.pin(room).addTo(layer)
      if (marker) setPins.set(room.id, marker)
      if (room.cell) lone.set(room.cell, { id: room.id, lat: room.lat, lng: room.lng, marker })
    }
    for (const { lat, lng, count, cellX, cellY } of detail.clusters) {
      const cluster = { lat, lng, count, marker: this.clusterMarker(lat, lng, count).addTo(layer) }
      clusters.set(`${cellX},${cellY}`, cluster)
    }
    layer.addTo(this.map)
    this.map.removeLayer(state.setLayer)
    Object.assign(state, { setLayer: layer, setPins, clusters, lone, mode: detail.mode, cellSize: detail.cellSize })

    // Rooms broadcast after this fetch was sent may be missing from it.
    state.live
      .filter(({ receivedAt }) => receivedAt > state.requestedAt)
      .forEach(({ detail }) => this.applyLive(detail))
  }

  handle(detail) {
    const state = this.state
    if (detail.role === "panel") return this.addPanelPin(detail)

    const known = state.panelPins.get(detail.id) || state.setPins.get(detail.id)
    if (known && known.options.title !== detail.title) this.retitle(known, detail.title)
    if (detail.role !== "live") return

    // A live marker element reconnects when Turbo moves the map container; apply it once.
    if (!state.live.some((entry) => entry.detail.id === detail.id)) {
      state.live.push({ detail, receivedAt: performance.now() })
      if (state.live.length > LIVE_LIMIT) state.live.shift()
      this.applyLive(detail)
    }
    this.pruneLiveMarkers()
  }

  addPanelPin(detail) {
    const state = this.state
    const existing = state.panelPins.get(detail.id)
    if (existing) {
      if (existing.options.title !== detail.title) this.retitle(existing, detail.title)
      return
    }
    // Move the room off the fetched layer so a later fetch cannot remove it.
    const fetched = state.setPins.get(detail.id)
    if (fetched) {
      state.setLayer.removeLayer(fetched)
      state.setPins.delete(detail.id)
      for (const single of state.lone.values()) {
        if (single.id === detail.id) single.marker = null
      }
    }
    state.panelPins.set(detail.id, this.pin(detail).addTo(state.panelLayer))
  }

  applyLive({ id, lat, lng, title, url }) {
    const state = this.state
    if (state.panelPins.has(id) || state.setPins.has(id)) return

    let cell = null
    if (state.mode === "clusters" && state.cellSize > 0) {
      cell = `${Math.floor(lng / state.cellSize)},${Math.floor(lat / state.cellSize)}`
      const cluster = state.clusters.get(cell)
      if (cluster) {
        cluster.count += 1
        this.drawCount(cluster.marker, cluster.count)
        return
      }
      const single = state.lone.get(cell)
      if (single) {
        if (single.id === id) return
        if (single.marker) state.setLayer.removeLayer(single.marker)
        state.setPins.delete(single.id)
        state.lone.delete(cell)
        const pair = { lat: (single.lat + lat) / 2, lng: (single.lng + lng) / 2, count: 2 }
        pair.marker = this.clusterMarker(pair.lat, pair.lng, pair.count).addTo(state.setLayer)
        state.clusters.set(cell, pair)
        return
      }
    }

    if (!this.map.getBounds().contains([lat, this.nearLng(lng)])) return
    const marker = this.pin({ lat, lng, title, url }).addTo(state.setLayer)
    state.setPins.set(id, marker)
    if (cell) state.lone.set(cell, { id, lat, lng, marker })
  }

  // #live_markers only needs the recent broadcasts; the pins themselves live on the map.
  pruneLiveMarkers() {
    const live = this.element.querySelector("#live_markers")
    while (live && live.children.length > LIVE_LIMIT) live.firstElementChild.remove()
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

  pin({ lat, lng, title, url }) {
    return L.marker([lat, this.nearLng(lng)], { icon: this.icon, title, alt: title })
      .bindTooltip(this.textNode(title))
      .on("click", () => Turbo.visit(url, { frame: "chatroom_panel", action: "advance" }))
  }

  // Marker clicks do not reach the map's click handler (Leaflet's bubblingMouseEvents is false
  // for markers), so clicking a cluster zooms in and never creates a room.
  clusterMarker(lat, lng, count) {
    const map = this.map
    const marker = L.marker([lat, this.nearLng(lng)], { icon: clusterIcon(count) })
      .on("click", () => map.setView(marker.getLatLng(), Math.min(map.getZoom() + CLUSTER_ZOOM_STEP, MAX_ZOOM)))
    marker.on("add", () => labelCluster(marker, count))
    return marker
  }

  drawCount(marker, count) {
    marker.setIcon(clusterIcon(count))
    labelCluster(marker, count)
  }

  // Rooms are stored in -180..180, but the map can be panned across the antimeridian. Draw each
  // room on the copy of the world nearest the current centre.
  nearLng(lng) {
    const center = this.map.getCenter().lng
    return lng + 360 * Math.round((center - lng) / 360)
  }
}

// The visible box, as the markers endpoint expects it: latitudes clamped, longitudes wrapped to
// -180..180 (west > east means the box crosses the antimeridian), the whole world when the view
// is 360° wide or more, and an integer zoom.
function boundsQuery(map) {
  const bounds = map.getBounds()
  const clampLat = (lat) => Math.max(-90, Math.min(90, lat))
  let west = -180
  let east = 180
  if (bounds.getEast() - bounds.getWest() < 360) {
    west = L.Util.wrapNum(bounds.getWest(), [-180, 180], true)
    east = L.Util.wrapNum(bounds.getEast(), [-180, 180], true)
  }
  const zoom = Math.max(0, Math.min(MAX_ZOOM, Math.round(map.getZoom())))
  return new URLSearchParams({
    south: clampLat(bounds.getSouth()).toFixed(6),
    west: west.toFixed(6),
    north: clampLat(bounds.getNorth()).toFixed(6),
    east: east.toFixed(6),
    zoom: String(zoom)
  })
}

// A round badge with the room count as text (never HTML).
function clusterIcon(count) {
  const size = count < 10 ? 32 : count < 100 ? 40 : 48
  const badge = document.createElement("span")
  badge.className = "flex h-full w-full items-center justify-center rounded-full border-2 border-white " +
    "bg-sky-700 text-sm font-semibold text-white shadow-md"
  badge.textContent = String(count)
  return L.divIcon({ html: badge, className: "map-cluster", iconSize: [size, size] })
}

function labelCluster(marker, count) {
  marker.getElement()?.setAttribute("aria-label", `${count} rooms, zoom in`)
}
