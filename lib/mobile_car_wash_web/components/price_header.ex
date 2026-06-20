defmodule MobileCarWashWeb.PriceHeader do
  @moduledoc """
  Stateless hero price header for the booking wizard. Renders the live
  total prominently with a tap-to-expand itemized receipt. Fed by
  `MobileCarWash.Billing.Pricing.breakdown/1`.
  """
  use MobileCarWashWeb, :html

  alias MobileCarWash.Billing.Pricing

  attr :breakdown, :map, default: nil
  attr :expanded, :boolean, default: false
  attr :toggle_event, :string, default: "toggle_receipt"

  def price_header(assigns) do
    ~H"""
    <div class="sticky top-16 z-30 -mx-4 px-4 pt-3 pb-2 bg-base-100/95 backdrop-blur">
      <div
        :if={is_nil(@breakdown)}
        class="rounded-2xl bg-base-200 px-4 py-3 text-center text-sm text-base-content/60"
      >
        Select a service to see your price
      </div>

      <div :if={@breakdown}>
        <button
          type="button"
          phx-click={@toggle_event}
          class="w-full rounded-2xl bg-gradient-to-br from-success to-success/80 text-success-content px-4 py-3 text-center"
        >
          <div
            id="price-hero-total"
            phx-hook="PriceCountUp"
            data-cents={@breakdown.total_cents}
            class="text-3xl font-extrabold leading-none"
          >
            {Pricing.format_cents(@breakdown.total_cents)}
          </div>
          <div :if={@breakdown.size_delta_cents > 0} class="text-xs opacity-90 mt-1">
            ▲ +{Pricing.format_cents(@breakdown.size_delta_cents)} {@breakdown.size_label}
          </div>
          <div class="text-[11px] opacity-80 mt-1">
            <.icon name="hero-receipt-percent" class="size-3" />
            {if @expanded, do: "Hide breakdown", else: "Tap for breakdown"}
          </div>
        </button>

        <div
          :if={@expanded}
          class="mt-2 rounded-xl border border-base-300 bg-base-100 px-4 py-3 text-sm"
        >
          <.line label="Base" amount={@breakdown.base_cents} />
          <.line
            :if={@breakdown.size_label && @breakdown.size_delta_cents != 0}
            label={@breakdown.size_label}
            amount={@breakdown.size_delta_cents}
          />
          <.line :for={l <- @breakdown.addon_lines} label={l.label} amount={l.amount_cents} />
          <.line
            :if={@breakdown.discount_cents > 0}
            label="Discount"
            amount={-@breakdown.discount_cents}
          />
          <div class="flex justify-between font-extrabold text-success border-t border-base-300 mt-2 pt-2">
            <span>Total</span>
            <span>{Pricing.format_cents(@breakdown.total_cents)}</span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :amount, :integer, required: true

  defp line(assigns) do
    ~H"""
    <div class="flex justify-between py-0.5 text-base-content/80">
      <span>{@label}</span>
      <span>{format_signed(@amount)}</span>
    </div>
    """
  end

  defp format_signed(amount) when amount < 0, do: "−" <> Pricing.format_cents(-amount)
  defp format_signed(amount), do: Pricing.format_cents(amount)
end
