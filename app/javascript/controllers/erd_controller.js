import { Controller } from "@hotwired/stimulus"

// Mermaid's initialize() replaces global config on the singleton. Run it once
// per page lifetime; subsequent Stimulus connects (Turbo cache replay) reuse
// the same configured Mermaid.
let mermaidInitialized = false

// Renders a Mermaid ER diagram from the data-erd-source-value attribute.
// Mermaid is loaded on first connect; if it's not pinned in the importmap,
// the controller no-ops and the raw source remains visible.
export default class extends Controller {
  static values = { source: String }

  async connect() {
    this.alive = true
    try {
      const mermaid = await import("mermaid")
      if (!this.alive || !this.element.isConnected) return

      if (!mermaidInitialized) {
        mermaid.default.initialize({ startOnLoad: false, securityLevel: "strict" })
        mermaidInitialized = true
      }

      const pre = this.element.querySelector("pre.mermaid")
      if (!pre) return

      const { svg } = await mermaid.default.render(
        `erd-${Math.random().toString(36).slice(2)}`,
        this.sourceValue || pre.textContent
      )
      // Re-check after the await — Turbo may have swapped the node out from
      // under us while Mermaid was rendering. Without this, the outerHTML
      // assignment can land on a detached node or race with a second connect().
      if (!this.alive || !pre.isConnected) return
      pre.outerHTML = svg
    } catch (e) {
      console.warn("Mermaid not available; leaving raw source visible.", e)
    }
  }

  disconnect() {
    this.alive = false
  }
}
