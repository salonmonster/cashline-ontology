import { Controller } from "@hotwired/stimulus"

// Renders a Mermaid ER diagram from the data-erd-source-value attribute.
// Mermaid is loaded on first connect; if it's not pinned in the importmap,
// the controller no-ops and the raw source remains visible.
export default class extends Controller {
  static values = { source: String }

  async connect() {
    try {
      const mermaid = await import("mermaid")
      mermaid.default.initialize({ startOnLoad: false, securityLevel: "strict" })
      const pre = this.element.querySelector("pre.mermaid")
      if (!pre) return
      const { svg } = await mermaid.default.render(`erd-${Math.random().toString(36).slice(2)}`, this.sourceValue || pre.textContent)
      pre.outerHTML = svg
    } catch (e) {
      console.warn("Mermaid not available; leaving raw source visible.", e)
    }
  }
}
