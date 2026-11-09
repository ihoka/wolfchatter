import { Controller } from "@hotwired/stimulus"

// Keeps a message list scrolled to its newest entry, on connect and whenever
// children are appended.
export default class extends Controller {
  connect() {
    this.scrollToBottom()
    this.observer = new MutationObserver(() => this.scrollToBottom())
    this.observer.observe(this.element, { childList: true })
  }

  disconnect() {
    this.observer?.disconnect()
    this.observer = null
  }

  scrollToBottom() {
    this.element.scrollTop = this.element.scrollHeight
  }
}
