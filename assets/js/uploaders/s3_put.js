// LiveView external uploader: PUTs the file straight to object storage
// (DigitalOcean Spaces / S3) using the presigned URL the server put in
// entry.meta. Progress feeds LiveView's normal entry progress, so tile
// and modal progress bars work unchanged.
export const S3PUT = function (entries, onViewError) {
  entries.forEach(entry => {
    const xhr = new XMLHttpRequest()
    onViewError(() => xhr.abort())

    xhr.onload = () =>
      xhr.status >= 200 && xhr.status < 300 ? entry.progress(100) : entry.error()
    xhr.onerror = () => entry.error()
    xhr.timeout = 30_000
    xhr.ontimeout = () => entry.error()

    xhr.upload.addEventListener("progress", event => {
      if (event.lengthComputable) {
        const percent = Math.round((event.loaded / event.total) * 100)
        if (percent < 100) entry.progress(percent)
      }
    })

    xhr.open("PUT", entry.meta.url, true)
    Object.entries(entry.meta.headers || {}).forEach(([name, value]) =>
      xhr.setRequestHeader(name, value)
    )
    xhr.send(entry.file)
  })
}
