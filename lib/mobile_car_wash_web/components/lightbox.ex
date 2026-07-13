defmodule MobileCarWashWeb.Lightbox do
  @moduledoc """
  Fullscreen tap-to-view photo overlay ("lightbox everywhere").

  Render `<.lightbox_root />` ONCE per LiveView that shows photos. The
  overlay is dormant until the `Lightbox` JS hook opens it; all behavior
  is client-side (zero server events). Photos opt in with:

      <img src={...} alt={...} data-lightbox="group-name" />

  Optional `data-lightbox-caption={caption}` shows a caption line.
  Before/after sliders opt in with an expand button:

      <button data-lightbox-slider data-before-url={...} data-after-url={...}>

  Spec: docs/superpowers/specs/2026-07-12-lightbox-everywhere-design.md
  """
  use Phoenix.Component

  @doc "The overlay skeleton. Hidden until the Lightbox hook opens it."
  def lightbox_root(assigns) do
    ~H"""
    <div
      id="lightbox-root"
      phx-hook="Lightbox"
      phx-update="ignore"
      class="fixed inset-0 z-[60] hidden bg-black/90 transition-opacity duration-200"
      role="dialog"
      aria-modal="true"
      aria-label="Photo viewer"
    >
      <div data-role="backdrop" class="absolute inset-0"></div>

      <figure
        data-role="stage"
        class="pointer-events-none absolute inset-0 flex items-center justify-center p-4"
      >
        <img
          data-role="image"
          class="pointer-events-auto max-h-full max-w-full touch-none object-contain"
        />
        <div
          data-role="slider-stage"
          class="pointer-events-auto relative hidden aspect-[4/3] w-full max-w-2xl cursor-ew-resize select-none touch-none overflow-hidden rounded-xl"
        >
          <img
            data-role="slider-after"
            alt="After"
            class="pointer-events-none absolute inset-0 h-full w-full object-cover"
          />
          <img
            data-role="slider-before"
            alt="Before"
            class="pointer-events-none absolute inset-0 h-full w-full object-cover"
            style="clip-path: inset(0 50% 0 0)"
          />
          <span class="badge badge-sm pointer-events-none absolute left-2 top-2 border-0 bg-base-100/80">
            Before
          </span>
          <span class="badge badge-sm pointer-events-none absolute right-2 top-2 border-0 bg-base-100/80">
            After
          </span>
          <div
            data-role="slider-divider"
            class="pointer-events-none absolute inset-y-0 w-0.5 bg-base-100 shadow"
            style="left: 50%"
          >
            <div class="absolute left-0 top-1/2 flex h-9 w-9 -translate-x-1/2 -translate-y-1/2 items-center justify-center rounded-full bg-base-100 text-sm text-base-content/60 shadow-md">
              ⇔
            </div>
          </div>
        </div>
        <p data-role="load-error" class="hidden text-sm text-white/90">
          Couldn't load photo — try again later.
        </p>
      </figure>

      <button
        type="button"
        data-role="close"
        aria-label="Close photo viewer"
        class="btn btn-circle btn-sm absolute right-3 top-3 border-0 bg-white/15 text-white"
      >
        ✕
      </button>
      <button
        type="button"
        data-role="prev"
        aria-label="Previous photo"
        class="btn btn-circle absolute left-2 top-1/2 hidden -translate-y-1/2 border-0 bg-white/15 text-white disabled:opacity-30"
      >
        ‹
      </button>
      <button
        type="button"
        data-role="next"
        aria-label="Next photo"
        class="btn btn-circle absolute right-2 top-1/2 hidden -translate-y-1/2 border-0 bg-white/15 text-white disabled:opacity-30"
      >
        ›
      </button>

      <p
        data-role="counter"
        aria-live="polite"
        class="absolute bottom-10 left-1/2 hidden -translate-x-1/2 text-xs text-white/80"
      >
      </p>
      <p
        data-role="caption"
        class="absolute bottom-4 left-1/2 hidden max-w-[90%] -translate-x-1/2 truncate text-sm text-white"
      >
      </p>
    </div>
    """
  end
end
