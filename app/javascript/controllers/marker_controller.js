import { Controller } from "@hotwired/stimulus"

// Announces a room to the map. Marker elements are plain server-rendered HTML;
// the map controller listens for marker:connect on window and dedupes by id.
export default class extends Controller {
  static values = { id: Number, lat: Number, lng: Number, title: String, url: String }

  connect() {
    this.dispatch("connect", {
      target: window,
      detail: {
        id: this.idValue,
        lat: this.latValue,
        lng: this.lngValue,
        title: this.titleValue,
        url: this.urlValue
      }
    })
  }
}
