import { Controller } from "@hotwired/stimulus"

// In-place sort for a table. Click a sortable <th> to toggle asc/desc.
//
// Markup contract:
//   <table data-controller="sortable-table">
//     <thead>
//       <tr>
//         <th data-action="click->sortable-table#sort"
//             data-sort-type="text">API name <span class="sort-indicator"></span></th>
//         <th data-action="click->sortable-table#sort"
//             data-sort-type="number">Null %  <span class="sort-indicator"></span></th>
//         ...
//       </tr>
//     </thead>
//     <tbody data-sortable-table-target="body">
//       <tr>
//         <td>...</td>
//         <td data-sort-value="0.105">10.5%</td>  // explicit numeric override
//         ...
//       </tr>
//     </tbody>
//   </table>
//
// data-sort-type: "text" (default) | "number"
// data-sort-value (on td): explicit sort key when display text isn't sortable
//   as-is (percentage strings, em-dash placeholders, etc.).
//
// Nulls (empty string, "—", non-numeric in number mode) sort to the bottom
// regardless of direction — common spreadsheet convention.
export default class extends Controller {
  static targets = ["body"]

  sort(event) {
    const th = event.currentTarget
    const headerRow = th.parentElement
    const colIndex = Array.from(headerRow.children).indexOf(th)
    const type = th.dataset.sortType || "text"
    const currentDir = th.dataset.sortDir || "none"
    const nextDir = currentDir === "asc" ? "desc" : "asc"

    // Reset sort state on every sortable header, then set this one.
    headerRow.querySelectorAll("th[data-sort-type]").forEach(h => {
      h.dataset.sortDir = "none"
      const ind = h.querySelector(".sort-indicator")
      if (ind) ind.textContent = ""
    })
    th.dataset.sortDir = nextDir
    const indicator = th.querySelector(".sort-indicator")
    if (indicator) indicator.textContent = nextDir === "asc" ? " ▲" : " ▼"

    const rows = Array.from(this.bodyTarget.querySelectorAll("tr"))
    rows.sort((a, b) => {
      const aVal = this.#cellValue(a.children[colIndex], type)
      const bVal = this.#cellValue(b.children[colIndex], type)

      // Nulls sort to the bottom regardless of direction.
      if (aVal === null && bVal === null) return 0
      if (aVal === null) return 1
      if (bVal === null) return -1

      let cmp
      if (type === "number") {
        cmp = aVal - bVal
      } else {
        cmp = aVal.localeCompare(bVal)
      }
      return nextDir === "asc" ? cmp : -cmp
    })

    // Re-append in sorted order. appendChild moves existing nodes.
    rows.forEach(row => this.bodyTarget.appendChild(row))
  }

  #cellValue(cell, type) {
    if (!cell) return null
    const raw = (cell.dataset.sortValue ?? cell.textContent ?? "").trim()
    if (raw === "" || raw === "—") return null
    if (type === "number") {
      const n = parseFloat(raw.replace(/[%,\s]/g, ""))
      return isNaN(n) ? null : n
    }
    return raw.toLowerCase()
  }
}
