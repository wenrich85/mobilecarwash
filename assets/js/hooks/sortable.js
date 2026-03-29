// Drag-and-drop reordering hook for LiveView
// Uses HTML5 Drag and Drop API — no external dependencies
export const Sortable = {
  mounted() {
    this.el.addEventListener("dragstart", (e) => {
      const item = e.target.closest("[data-sort-id]")
      if (!item) return
      e.dataTransfer.effectAllowed = "move"
      e.dataTransfer.setData("text/plain", item.dataset.sortId)
      item.classList.add("opacity-50")
    })

    this.el.addEventListener("dragend", (e) => {
      const item = e.target.closest("[data-sort-id]")
      if (item) item.classList.remove("opacity-50")
    })

    this.el.addEventListener("dragover", (e) => {
      e.preventDefault()
      e.dataTransfer.dropEffect = "move"

      const target = e.target.closest("[data-sort-id]")
      if (target) {
        const rect = target.getBoundingClientRect()
        const midY = rect.top + rect.height / 2
        if (e.clientY < midY) {
          target.classList.add("border-t-2", "border-primary")
          target.classList.remove("border-b-2")
        } else {
          target.classList.add("border-b-2", "border-primary")
          target.classList.remove("border-t-2")
        }
      }
    })

    this.el.addEventListener("dragleave", (e) => {
      const target = e.target.closest("[data-sort-id]")
      if (target) {
        target.classList.remove("border-t-2", "border-b-2", "border-primary")
      }
    })

    this.el.addEventListener("drop", (e) => {
      e.preventDefault()
      const draggedId = e.dataTransfer.getData("text/plain")
      const target = e.target.closest("[data-sort-id]")
      if (!target || target.dataset.sortId === draggedId) return

      target.classList.remove("border-t-2", "border-b-2", "border-primary")

      // Collect new order
      const items = [...this.el.querySelectorAll("[data-sort-id]")]
      const draggedEl = items.find(el => el.dataset.sortId === draggedId)
      if (!draggedEl) return

      const rect = target.getBoundingClientRect()
      const midY = rect.top + rect.height / 2
      if (e.clientY < midY) {
        target.parentNode.insertBefore(draggedEl, target)
      } else {
        target.parentNode.insertBefore(draggedEl, target.nextSibling)
      }

      // Send new order to server
      const newOrder = [...this.el.querySelectorAll("[data-sort-id]")].map(
        el => el.dataset.sortId
      )
      this.pushEvent("reorder_steps", {
        procedure_id: this.el.dataset.procedureId,
        step_ids: newOrder
      })
    })
  }
}
