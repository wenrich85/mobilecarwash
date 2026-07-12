// Composes the branded before/after share card on a canvas and opens
// the native share sheet (navigator.share with files). Fallbacks:
//   - canvas fails (image load error / CORS taint) -> share text+link only,
//     pushEvent("share_degraded") so the modal shows a soft notice
//   - no file-capable share sheet (desktop) -> download the JPEG and copy
//     the share text+link, pushEvent("share_fallback_done", {mode})
// A user-cancelled share sheet (AbortError) is silently ignored.
// No flash messages — all feedback renders inside the modal.
const CANVAS_W = 1080
const CANVAS_H = 1350
const FOOTER_H = 150
const DIVIDER_H = 4
const FONT_STACK = "system-ui, -apple-system, 'Segoe UI', sans-serif"

function loadImage(url) {
  return new Promise((resolve, reject) => {
    const img = new Image()
    img.crossOrigin = "anonymous"
    img.onload = () => resolve(img)
    img.onerror = () => reject(new Error(`could not load ${url}`))
    img.src = url
  })
}

// drawImage with CSS object-fit:cover semantics.
function drawCover(ctx, img, x, y, w, h) {
  const scale = Math.max(w / img.width, h / img.height)
  const sw = w / scale
  const sh = h / scale
  ctx.drawImage(img, (img.width - sw) / 2, (img.height - sh) / 2, sw, sh, x, y, w, h)
}

function drawChip(ctx, text, x, y) {
  ctx.save()
  ctx.font = `bold 34px ${FONT_STACK}`
  const w = ctx.measureText(text).width + 44
  const h = 58
  ctx.fillStyle = "rgba(255, 255, 255, 0.85)"
  ctx.beginPath()
  ctx.roundRect(x, y, w, h, h / 2)
  ctx.fill()
  ctx.fillStyle = "#1f2937"
  ctx.textBaseline = "middle"
  ctx.fillText(text, x + 22, y + h / 2)
  ctx.restore()
}

async function composeCard(data) {
  const [before, after] = await Promise.all([
    loadImage(data.beforeUrl),
    loadImage(data.afterUrl)
  ])

  const canvas = document.createElement("canvas")
  canvas.width = CANVAS_W
  canvas.height = CANVAS_H
  const ctx = canvas.getContext("2d")
  const half = (CANVAS_H - FOOTER_H - DIVIDER_H) / 2

  drawCover(ctx, before, 0, 0, CANVAS_W, half)
  drawCover(ctx, after, 0, half + DIVIDER_H, CANVAS_W, half)
  ctx.fillStyle = "#ffffff"
  ctx.fillRect(0, half, CANVAS_W, DIVIDER_H)

  drawChip(ctx, "Before", 32, 32)
  drawChip(ctx, "After", 32, half + DIVIDER_H + 32)

  ctx.fillStyle = "#111827"
  ctx.fillRect(0, CANVAS_H - FOOTER_H, CANVAS_W, FOOTER_H)
  ctx.textBaseline = "middle"
  ctx.fillStyle = "#ffffff"
  ctx.font = `bold 44px ${FONT_STACK}`
  ctx.fillText("Driveway Detail", 40, CANVAS_H - FOOTER_H / 2)
  ctx.textAlign = "right"
  ctx.font = `32px ${FONT_STACK}`
  ctx.fillStyle = "#d1d5db"
  ctx.fillText(
    `Get $${data.rewardDollars} off your first wash · ${data.referralCode}`,
    CANVAS_W - 40,
    CANVAS_H - FOOTER_H / 2
  )

  // toBlob throws SecurityError synchronously on a tainted canvas —
  // the caller's try/catch handles both that and the reject path.
  const blob = await new Promise((resolve, reject) =>
    canvas.toBlob(b => (b ? resolve(b) : reject(new Error("toBlob failed"))), "image/jpeg", 0.9)
  )
  return new File([blob], "driveway-detail-wash.jpg", {type: "image/jpeg"})
}

function download(file) {
  const url = URL.createObjectURL(file)
  const a = document.createElement("a")
  a.href = url
  a.download = file.name
  a.click()
  URL.revokeObjectURL(url)
}

export const ShareWashCard = {
  mounted() {
    this.el.addEventListener("click", () => this.share())
  },

  async share() {
    const data = this.el.dataset
    let file = null

    try {
      file = await composeCard(data)
    } catch (_error) {
      this.pushEvent("share_degraded", {})
    }

    try {
      if (file && navigator.canShare && navigator.canShare({files: [file]})) {
        await navigator.share({files: [file], text: data.shareText, url: data.shareLink})
      } else if (!file && navigator.share) {
        await navigator.share({text: data.shareText, url: data.shareLink})
      } else {
        if (file) download(file)
        await navigator.clipboard.writeText(`${data.shareText} ${data.shareLink}`)
        this.pushEvent("share_fallback_done", {mode: file ? "image" : "link"})
      }
    } catch (error) {
      if (error.name === "AbortError") return
      // Share sheet failed some other way — last resort: copy the link.
      try {
        await navigator.clipboard.writeText(`${data.shareText} ${data.shareLink}`)
        this.pushEvent("share_fallback_done", {mode: "link"})
      } catch (_clipboardError) {
        this.pushEvent("share_degraded", {})
      }
    }
  }
}
