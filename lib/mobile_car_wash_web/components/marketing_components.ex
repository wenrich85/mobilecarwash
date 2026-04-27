defmodule MobileCarWashWeb.MarketingComponents do
  @moduledoc """
  Customer-facing components used on landing, booking, and other
  marketing pages. Distinct from CoreComponents (which are general-
  purpose). All components use Plan 1's design tokens and Plan 2's
  brand assets.
  """
  use Phoenix.Component

  @doc """
  Renders a centered hero with optional trust badge above the headline.
  """
  attr :headline, :string, required: true
  attr :subhead, :string, required: true
  attr :trust_badge, :string, default: nil
  slot :primary_cta, required: true
  slot :secondary_cta

  def hero(assigns) do
    ~H"""
    <section class="bg-base-100 py-12 md:py-16 px-4">
      <div class="max-w-3xl mx-auto text-center">
        <div
          :if={@trust_badge}
          class="inline-block text-[11px] font-semibold tracking-wider text-cyan-700 bg-cyan-50 px-3 py-1 rounded-full mb-4"
        >
          {@trust_badge}
        </div>
        <h1 class="text-3xl md:text-5xl font-bold text-base-content tracking-tight leading-[1.1] mb-3">
          {@headline}
        </h1>
        <p class="text-base md:text-lg text-base-content/70 max-w-xl mx-auto mb-6">
          {@subhead}
        </p>
        <div class="flex flex-col sm:flex-row items-center justify-center gap-3">
          <div>{render_slot(@primary_cta)}</div>
          <div :if={@secondary_cta != []}>{render_slot(@secondary_cta)}</div>
        </div>
      </div>
    </section>
    """
  end
end
