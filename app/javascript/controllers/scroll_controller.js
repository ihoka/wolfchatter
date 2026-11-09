import { Controller } from "@hotwired/stimulus"

// Keeps a message list scrolled to its newest entry, on connect and whenever
// children are appended.
export default class extends Controller {
  connect() {
    this.scrollToBottom()
    this.nearBottom = true
    this.onScroll = () => { this.nearBottom = this.distanceFromBottom() <= 40 }
    this.element.addEventListener("scroll", this.onScroll, { passive: true })
    this.observer = new MutationObserver(() => {
      if (this.nearBottom) this.scrollToBottom()
    })
    this.observer.observe(this.element, { childList: true })
  }

  disconnect() {
    this.element.removeEventListener("scroll", this.onScroll)
    this.observer?.disconnect()
    this.observer = null
  }

  distanceFromBottom() {
    return this.element.scrollHeight - this.element.scrollTop - this.element.clientHeight
  }

  scrollToBottom() {
    this.element.scrollTop = this.element.scrollHeight
  }
}
