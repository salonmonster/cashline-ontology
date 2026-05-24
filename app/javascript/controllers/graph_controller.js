import { Controller } from "@hotwired/stimulus"

// Renders a Cytoscape force-directed graph from a JSON endpoint.
// Lazily imports cytoscape + cytoscape-fcose; no-ops if the modules
// aren't pinned in the importmap.
export default class extends Controller {
  static values = { endpoint: String, objectPath: String }
  static targets = ["canvas", "namespaceFilter", "minRecords"]

  async connect() {
    try {
      const cytoscape = (await import("cytoscape")).default
      try {
        const fcose = (await import("cytoscape-fcose")).default
        cytoscape.use(fcose)
        this.layoutName = "fcose"
      } catch (_e) {
        this.layoutName = "cose"
      }

      const resp = await fetch(this.endpointValue, { headers: { Accept: "application/json" } })
      const data = await resp.json()
      this.data = data
      this.cy = cytoscape({
        container: this.canvasTarget,
        elements: this.buildElements(data),
        layout: { name: this.layoutName, animate: false },
        style: [
          { selector: "node", style: { "background-color": "#1e293b", "label": "data(label)", "color": "#0f172a", "font-size": 10, "text-valign": "bottom" } },
          { selector: "edge", style: { "width": 1, "line-color": "#94a3b8", "curve-style": "bezier" } }
        ]
      })
      this.cy.on("tap", "node", (evt) => {
        const apiName = evt.target.data("label")
        window.location = this.objectPathValue.replace("__API_NAME__", encodeURIComponent(apiName))
      })

      const namespaces = Array.from(new Set(data.nodes.map(n => n.namespace))).sort()
      if (this.hasNamespaceFilterTarget) {
        for (const ns of namespaces) {
          const opt = document.createElement("option")
          opt.value = ns; opt.textContent = ns
          this.namespaceFilterTarget.appendChild(opt)
        }
      }
    } catch (e) {
      console.warn("Cytoscape not available", e)
    }
  }

  buildElements(data) {
    return [
      ...data.nodes.map(n => ({ data: { id: String(n.id), label: n.label, namespace: n.namespace, cluster: n.cluster, recordCount: n.record_count || 0 } })),
      ...data.edges.map(e => ({ data: { id: `e${e.source}-${e.target}`, source: String(e.source), target: String(e.target) } }))
    ]
  }

  applyFilters() {
    if (!this.cy) return
    const ns = this.hasNamespaceFilterTarget ? this.namespaceFilterTarget.value : ""
    const min = this.hasMinRecordsTarget ? Number(this.minRecordsTarget.value || 0) : 0
    this.cy.nodes().forEach(n => {
      const matches = (!ns || n.data("namespace") === ns) && n.data("recordCount") >= min
      n.style("display", matches ? "element" : "none")
    })
    this.cy.edges().forEach(e => {
      const src = this.cy.getElementById(e.data("source"))
      const tgt = this.cy.getElementById(e.data("target"))
      const show = src.style("display") !== "none" && tgt.style("display") !== "none"
      e.style("display", show ? "element" : "none")
    })
  }

  fit() {
    if (this.cy) this.cy.fit()
  }
}
