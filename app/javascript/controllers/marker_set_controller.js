import { Controller } from "@hotwired/stimulus"

// The set of pins or clusters the server sent for the visible area. Reads its server-rendered
// children once and hands them to the map as marker-set:load on window.
export default class extends Controller {
  static values = { mode: String, cellSize: Number }

  connect() {
    const pins = []
    const clusters = []
    for (const el of this.element.children) {
      if (el.hasAttribute("data-cluster")) {
        clusters.push({
          lat: Number(el.dataset.lat),
          lng: Number(el.dataset.lng),
          count: Number(el.dataset.count),
          cellX: Number(el.dataset.cellX),
          cellY: Number(el.dataset.cellY)
        })
      } else if (el.dataset.markerIdValue) {
        pins.push({
          id: Number(el.dataset.markerIdValue),
          lat: Number(el.dataset.markerLatValue),
          lng: Number(el.dataset.markerLngValue),
          title: el.dataset.markerTitleValue,
          url: el.dataset.markerUrlValue,
          cell: el.dataset.cellX === undefined ? null : `${el.dataset.cellX},${el.dataset.cellY}`
        })
      }
    }
    this.dispatch("load", {
      target: window,
      detail: { mode: this.modeValue, cellSize: this.cellSizeValue, pins, clusters }
    })
  }
}
