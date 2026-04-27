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

  @doc """
  Renders a pricing tier card with optional MOST POPULAR highlight.
  """
  attr :name, :string, required: true
  attr :price, :string, required: true
  attr :duration, :string, required: true
  attr :features, :list, required: true
  attr :highlighted, :boolean, default: false
  slot :cta, required: true

  def service_tier_card(assigns) do
    ~H"""
    <div class={[
      "relative bg-base-100 rounded-box p-5 flex flex-col",
      if(@highlighted, do: "border-2 border-cyan-500", else: "border border-base-300")
    ]}>
      <div
        :if={@highlighted}
        class="absolute -top-3 right-4 bg-cyan-500 text-white text-[10px] font-bold tracking-wide px-2 py-1 rounded-full"
      >
        MOST POPULAR
      </div>
      <div class="text-xs font-semibold uppercase tracking-wide text-base-content/60 mb-1">
        {@name}
      </div>
      <div class="font-mono text-3xl font-bold text-base-content tracking-tight">
        {@price}
      </div>
      <div class="text-xs text-base-content/60 mt-0.5 mb-4">{@duration}</div>
      <ul class="text-sm text-base-content/80 space-y-1.5 mb-6 flex-1">
        <li :for={feature <- @features} class="flex items-start gap-2">
          <span class="text-cyan-500 font-semibold">✓</span>
          <span>{feature}</span>
        </li>
      </ul>
      <div class="mt-auto min-h-12">
        {render_slot(@cta)}
      </div>
    </div>
    """
  end

  @doc """
  Renders a dark "how we're different" section with cyan glow.

  Two-column on desktop (type left, :preview slot right), stacks on mobile.
  """
  attr :eyebrow, :string, default: "[ HOW WE'RE DIFFERENT ]"
  attr :headline, :string, required: true
  attr :subhead, :string, required: true
  attr :bullets, :list, default: []
  slot :preview

  def tech_section(assigns) do
    ~H"""
    <section class="relative bg-slate-900 py-16 px-4 overflow-hidden">
      <div class="absolute top-1/2 -right-20 w-96 h-96 bg-cyan-500/25 rounded-full blur-3xl -translate-y-1/2"></div>
      <div class="relative max-w-6xl mx-auto grid grid-cols-1 md:grid-cols-2 gap-10 items-center">
        <div>
          <div class="font-mono text-xs text-cyan-400 tracking-widest mb-2">
            {@eyebrow}
          </div>
          <h2 class="text-2xl md:text-3xl font-bold text-white tracking-tight leading-[1.15] mb-3">
            {@headline}
          </h2>
          <p class="text-sm md:text-base text-slate-400 leading-relaxed mb-4">
            {@subhead}
          </p>
          <ul :if={@bullets != []} class="text-sm text-slate-300 space-y-2 list-none p-0">
            <li :for={bullet <- @bullets}>{bullet}</li>
          </ul>
        </div>
        <div :if={@preview != []}>
          {render_slot(@preview)}
        </div>
      </div>
    </section>
    """
  end

  @doc """
  Renders a single customer testimonial card.
  """
  attr :quote, :string, required: true
  attr :name, :string, required: true
  attr :vehicle, :string, default: nil

  def testimonial(assigns) do
    ~H"""
    <div class="bg-base-100 border border-base-300 rounded-box p-5">
      <div class="text-cyan-500 text-3xl font-serif leading-none mb-2">"</div>
      <p class="text-sm text-base-content/80 italic leading-relaxed mb-3">
        {@quote}
      </p>
      <div class="text-xs">
        <div class="font-semibold text-base-content">{@name}</div>
        <div :if={@vehicle} class="text-base-content/60 mt-0.5">{@vehicle}</div>
      </div>
    </div>
    """
  end

  @doc """
  Renders a centered CTA band — used near the bottom of marketing pages
  to drive a final conversion.
  """
  attr :headline, :string, required: true
  attr :subhead, :string, required: true
  slot :cta, required: true

  def cta_band(assigns) do
    ~H"""
    <section class="bg-base-100 py-12 px-4 text-center">
      <h2 class="text-2xl font-bold text-base-content tracking-tight mb-2">
        {@headline}
      </h2>
      <p class="text-sm text-base-content/60 mb-5">{@subhead}</p>
      <div class="flex justify-center min-h-12">
        {render_slot(@cta)}
      </div>
    </section>
    """
  end

  @doc """
  Renders a numbered grid of feature/step items.
  """
  attr :columns, :integer, default: 3, values: [2, 3, 4]
  slot :item, required: true do
    attr :number, :string
    attr :title, :string, required: true
  end

  def feature_grid(assigns) do
    cols_class =
      case assigns.columns do
        2 -> "md:grid-cols-2"
        3 -> "md:grid-cols-3"
        4 -> "md:grid-cols-4"
      end

    assigns = assign(assigns, :cols_class, cols_class)

    ~H"""
    <div class={["grid grid-cols-1 gap-4", @cols_class]}>
      <div :for={item <- @item} class="bg-base-200 rounded-box p-5">
        <div
          :if={item[:number]}
          class="w-7 h-7 bg-cyan-500 text-white rounded-lg flex items-center justify-center font-bold text-sm mb-2.5"
        >{item.number}</div>
        <div class="text-sm font-semibold text-base-content mb-1">
          {item.title}
        </div>
        <div class="text-sm text-base-content/70 leading-relaxed">
          {render_slot(item)}
        </div>
      </div>
    </div>
    """
  end
end
