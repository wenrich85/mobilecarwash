// Downscales photos on-device before LiveView uploads them, so a
// 4–10 MB phone photo becomes a few hundred KB and the transfer
// finishes in well under a second on cellular.
//
// Attach with phx-hook="ImageDownscale" on an element WRAPPING the
// `.live_file_input` — not on the input itself. The file input already
// carries LiveView's internal data-phx-hook="Phoenix.LiveFileUpload",
// which takes precedence over phx-hook, so a hook placed directly on
// the input never mounts.
//
// The wrapper intercepts the input's `change` event in the capture
// phase (before LiveView's delegated listener sees it), resizes each
// image through a canvas, swaps the resized files into the input, and
// re-dispatches `change` so LiveView uploads the small versions.
// Anything that can't be decoded (e.g. HEIC on non-Safari browsers)
// passes through untouched — the server still validates and stores
// the original.
const MAX_DIMENSION = 1600
const JPEG_QUALITY = 0.85
// Files already this small aren't worth re-encoding.
const SKIP_BELOW_BYTES = 400_000

async function downscale(file) {
  if (!file.type.startsWith("image/") || file.size < SKIP_BELOW_BYTES) return file

  try {
    const bitmap = await createImageBitmap(file)
    const scale = Math.min(1, MAX_DIMENSION / Math.max(bitmap.width, bitmap.height))
    const canvas = document.createElement("canvas")
    canvas.width = Math.round(bitmap.width * scale)
    canvas.height = Math.round(bitmap.height * scale)
    canvas.getContext("2d").drawImage(bitmap, 0, 0, canvas.width, canvas.height)
    bitmap.close()

    const blob = await new Promise(resolve => canvas.toBlob(resolve, "image/jpeg", JPEG_QUALITY))
    if (!blob || blob.size >= file.size) return file

    const name = file.name.replace(/\.\w+$/, "") + ".jpg"
    return new File([blob], name, {type: "image/jpeg", lastModified: file.lastModified})
  } catch (_error) {
    return file
  }
}

export const ImageDownscale = {
  mounted() {
    this.el.addEventListener("change", event => {
      const input = event.target
      if (!(input instanceof HTMLInputElement) || input.type !== "file") return

      // Second pass: this change event carries the already-resized
      // files we dispatched below — let LiveView handle it.
      if (input.dataset.downscaled) {
        delete input.dataset.downscaled
        return
      }
      if (!input.files || input.files.length === 0) return

      event.stopImmediatePropagation()

      Promise.all(Array.from(input.files).map(downscale)).then(files => {
        const transfer = new DataTransfer()
        files.forEach(file => transfer.items.add(file))
        input.dataset.downscaled = "true"
        input.files = transfer.files
        input.dispatchEvent(new Event("change", {bubbles: true}))
      })
    }, true)
  }
}
