// Copies the value of `data-copy-text` to the clipboard when the
// element is clicked, then briefly swaps the visible label to "Copied!".
// Used by the booking-success referral card.
export const ClipboardCopy = {
  mounted() {
    this.el.addEventListener("click", () => {
      const text = this.el.dataset.copyText
      if (text && navigator.clipboard) {
        navigator.clipboard.writeText(text).then(() => {
          const original = this.el.textContent
          this.el.textContent = "Copied!"
          setTimeout(() => { this.el.textContent = original }, 1500)
        })
      }
    })
  }
}
