defmodule MobileCarWashWeb.Admin.CashFlowComponents do
  @moduledoc """
  Gamified cash flow components: animated SVG bucket diagram with flowing coins,
  form modals, and animation preferences.
  """
  use Phoenix.Component

  attr :accounts, :map, required: true
  attr :thresholds, :map, required: true
  attr :config, :any, required: true
  attr :animating_flows, :list, required: true
  attr :animations_enabled, :boolean, default: true

  def bucket_diagram(assigns) do
    ~H"""
    <div id="bucket-diagram-container" class="w-full">
      <svg
        viewBox="0 0 1000 700"
        class="w-full max-w-5xl mx-auto border-2 border-secondary-300 rounded-2xl bg-gradient-to-br from-secondary-50 via-base-100 to-tertiary-50 p-8 shadow-2xl"
      >
        <defs>
          <!-- Brand color gradients for buckets -->
          <linearGradient id="blueGrad" x1="0%" y1="0%" x2="0%" y2="100%">
            <stop offset="0%" style="stop-color:#3A7CA5;stop-opacity:0.9" />
            <stop offset="100%" style="stop-color:#2E6384;stop-opacity:0.5" />
          </linearGradient>

          <linearGradient id="redGrad" x1="0%" y1="0%" x2="0%" y2="100%">
            <stop offset="0%" style="stop-color:#E74C3C;stop-opacity:0.9" />
            <stop offset="100%" style="stop-color:#C0392B;stop-opacity:0.5" />
          </linearGradient>

          <linearGradient id="greenGrad" x1="0%" y1="0%" x2="0%" y2="100%">
            <stop offset="0%" style="stop-color:#27AE60;stop-opacity:0.9" />
            <stop offset="100%" style="stop-color:#229954;stop-opacity:0.5" />
          </linearGradient>

          <!-- Glow filters -->
          <filter id="bucketGlow">
            <feGaussianBlur stdDeviation="3" result="coloredBlur" />
            <feMerge>
              <feMergeNode in="coloredBlur" />
              <feMergeNode in="SourceGraphic" />
            </feMerge>
          </filter>

          <!-- Coin animation keyframes -->
          <style>
            @keyframes flowCoin {
              0% {
                opacity: 1;
                stroke-dashoffset: 0;
              }
              85% {
                opacity: 1;
              }
              100% {
                opacity: 0;
                stroke-dashoffset: 500;
              }
            }

            @keyframes bounce {
              0%, 100% {
                transform: translateY(0);
              }
              50% {
                transform: translateY(-8px);
              }
            }

            @keyframes arrowPulse {
              0%, 100% {
                stroke-width: 2;
                opacity: 0.6;
              }
              50% {
                stroke-width: 3;
                opacity: 1;
              }
            }

            .flow-path-active {
              animation: flowCoin 2s cubic-bezier(0.25, 0.46, 0.45, 0.94) infinite;
            }

            .coin-active {
              animation: bounce 0.6s ease-in-out infinite;
            }

            .arrow-active {
              animation: arrowPulse 1s ease-in-out infinite;
            }
          </style>
        </defs>

        <!-- Buckets with 3D effect -->
        <.bucket
          label="Expense Account"
          color="blue"
          balance_cents={@accounts.expense.balance_cents}
          threshold_cents={@thresholds.expense}
          cx={500}
          cy={120}
          gradient_id="blueGrad"
        />

        <.bucket
          label="Tax Account"
          color="red"
          balance_cents={@accounts.tax.balance_cents}
          threshold_cents={nil}
          cx={220}
          cy={380}
          gradient_id="redGrad"
        />

        <.bucket
          label="Business Savings"
          color="blue"
          balance_cents={@accounts.business_savings.balance_cents}
          threshold_cents={@thresholds.business_savings}
          cx={500}
          cy={380}
          gradient_id="blueGrad"
        />

        <.bucket
          label="Personal Salary"
          color="green"
          balance_cents={@accounts.personal_salary.balance_cents}
          threshold_cents={nil}
          cx={780}
          cy={380}
          gradient_id="greenGrad"
        />

        <.bucket
          label="Investment Account"
          color="blue"
          balance_cents={@accounts.investment.balance_cents}
          threshold_cents={@config.investment_target_cents}
          cx={500}
          cy={600}
          gradient_id="blueGrad"
        />

        <!-- Flow arrows with animated coins -->
        <.flow_arrow
          x1={500}
          y1={170}
          x2={500}
          y2={330}
          label="Overflow"
          active={:expense_to_savings in @animating_flows && @animations_enabled}
          animation_speed="2s"
        />

        <.flow_arrow
          x1={460}
          y1={160}
          x2={280}
          y2={320}
          label="50%"
          active={:expense_to_tax in @animating_flows && @animations_enabled}
          animation_speed="2s"
        />

        <.flow_arrow
          x1={540}
          y1={160}
          x2={720}
          y2={320}
          label="Salary"
          active={:expense_to_salary in @animating_flows && @animations_enabled}
          animation_speed="2s"
        />

        <.flow_arrow
          x1={500}
          y1={430}
          x2={500}
          y2={550}
          label="Growth"
          active={:savings_to_investment in @animating_flows && @animations_enabled}
          animation_speed="2s"
        />

        <!-- Reverse Flow Arrows (Pulling back to Expense) -->
        <.flow_arrow_reverse
          x1={500}
          y1={330}
          x2={500}
          y2={170}
          label="Replenish"
          active={:savings_to_expense in @animating_flows && @animations_enabled}
        />

        <.flow_arrow_reverse
          x1={280}
          y1={320}
          x2={460}
          y2={160}
          label="From Tax"
          active={:tax_to_expense in @animating_flows && @animations_enabled}
        />

        <.flow_arrow_reverse
          x1={500}
          y1={550}
          x2={500}
          y2={430}
          label="From Growth"
          active={:investment_to_expense in @animating_flows && @animations_enabled}
        />
      </svg>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :color, :string, required: true
  attr :balance_cents, :integer, required: true
  attr :threshold_cents, :any, default: nil
  attr :cx, :integer, required: true
  attr :cy, :integer, required: true
  attr :gradient_id, :string, required: true

  defp bucket(assigns) do
    fill_pct =
      if assigns.threshold_cents && assigns.threshold_cents > 0 do
        min(assigns.balance_cents / assigns.threshold_cents, 1.0)
      else
        min(assigns.balance_cents / max(assigns.threshold_cents || 1, 1), 1.0)
      end

    fill_height = trunc(fill_pct * 60)
    color_stroke = color_to_stroke(assigns.color)

    assigns =
      assigns
      |> assign(fill_height: fill_height, color_stroke: color_stroke, fill_pct: fill_pct)

    ~H"""
    <g filter="url(#bucketGlow)">
      <!-- Bucket rim (ellipse) -->
      <ellipse
        cx={@cx}
        cy={@cy}
        rx="40"
        ry="12"
        fill={@color_stroke}
        opacity="0.1"
      />
      <ellipse
        cx={@cx}
        cy={@cy}
        rx="40"
        ry="12"
        fill="none"
        stroke={@color_stroke}
        stroke-width="2"
      />

      <!-- Bucket body (3D trapezoid effect) -->
      <path
        d={
          "M #{@cx - 40} #{@cy} L #{@cx - 38} #{@cy + 70} Q #{@cx} #{@cy + 78} #{@cx + 38} #{@cy + 70} L #{@cx + 40} #{@cy}"
        }
        fill="none"
        stroke={@color_stroke}
        stroke-width="2.5"
      />

      <!-- Bucket sides (depth) -->
      <line
        x1={@cx - 40}
        y1={@cy}
        x2={@cx - 38}
        y2={@cy + 70}
        stroke={@color_stroke}
        stroke-width="1.5"
        opacity="0.6"
      />
      <line
        x1={@cx + 40}
        y1={@cy}
        x2={@cx + 38}
        y2={@cy + 70}
        stroke={@color_stroke}
        stroke-width="1.5"
        opacity="0.6"
      />

      <!-- Stacked Cash Bills Fill -->
      <.cash_stack
        cx={@cx}
        cy={@cy}
        fill_height={@fill_height}
        color_stroke={@color_stroke}
      />

      <!-- Bucket handle -->
      <path
        d={
          "M #{@cx - 30} #{@cy - 5} Q #{@cx} #{@cy - 35} #{@cx + 30} #{@cy - 5}"
        }
        fill="none"
        stroke={@color_stroke}
        stroke-width="3"
        stroke-linecap="round"
      />

      <!-- Label above bucket -->
      <text
        x={@cx}
        y={@cy - 50}
        text-anchor="middle"
        font-size="18"
        font-weight="bold"
        fill="#1E2A38"
      >
        {@label}
      </text>

      <!-- Fill percentage inside bucket with outline -->
      <text
        x={@cx}
        y={@cy + 35}
        text-anchor="middle"
        font-size="17"
        font-weight="bold"
        fill="white"
        stroke="#1E2A38"
        stroke-width="1.2"
        paint-order="stroke"
      >
        {trunc(@fill_pct * 100)}%
      </text>

      <!-- Balance below bucket with outline and background -->
      <rect
        x={@cx - 48}
        y={@cy + 82}
        width="96"
        height="18"
        fill="#FFFFFF"
        opacity="0.95"
        rx="3"
      />
      <text
        x={@cx}
        y={@cy + 97}
        text-anchor="middle"
        font-size="17"
        font-weight="bold"
        fill="#1E2A38"
      >
        ${format_cents(@balance_cents)}
      </text>

      <!-- Threshold indicator -->
      <text
        :if={@threshold_cents}
        x={@cx}
        y={@cy + 116}
        text-anchor="middle"
        font-size="12"
        font-weight="bold"
        fill="#1E2A38"
        stroke="white"
        stroke-width="0.8"
        paint-order="stroke"
      >
        Target: ${format_cents(@threshold_cents)}
      </text>
    </g>
    """
  end

  attr :cx, :integer, required: true
  attr :cy, :integer, required: true
  attr :fill_height, :integer, required: true
  attr :color_stroke, :string, required: true

  defp cash_stack(assigns) do
    # Generate individual realistic USD bills
    num_bills = max(trunc(assigns.fill_height / 3.5), 0)

    assigns = assign(assigns, num_bills: num_bills)

    ~H"""
    <%= for i <- 0..max(@num_bills - 1, 0) do %>
      <% bill_y = @cy + 70 - (i + 1) * 3.5 %>

      <!-- All bills in classic green (US currency) -->
      <% bill_color = "#1B5E20" %>
      <% bill_text = "$" %>

      <!-- Slight offset and rotation for realistic stacking -->
      <% x_offset = rem(i, 2) * 2.5 - 1.25 %>
      <% rotation = rem(i, 3) * 1.2 - 1.2 %>

      <g transform={"translate(#{@cx + x_offset}, #{bill_y}) rotate(#{rotation})"}>
        <!-- Main bill base -->
        <rect x="-36" y="0" width="72" height="3.2" fill={bill_color} rx="0.4" opacity="0.95"/>

        <!-- Bill darker shade on edges (depth) -->
        <rect x="-36" y="2.8" width="72" height="0.4" fill="#000000" opacity="0.25" rx="0.4"/>
        <rect x="-36" y="0" width="2" height="3.2" fill="#000000" opacity="0.15" rx="0.4"/>

        <!-- Bill top highlight (shine) -->
        <rect x="-36" y="0.1" width="72" height="0.6" fill="#FFFFFF" opacity="0.35" rx="0.4"/>

        <!-- Subtle texture pattern -->
        <circle cx="-28" cy="1.6" r="0.5" fill="#FFFFFF" opacity="0.1"/>
        <circle cx="-18" cy="1.6" r="0.5" fill="#FFFFFF" opacity="0.1"/>
        <circle cx="-8" cy="1.6" r="0.5" fill="#FFFFFF" opacity="0.1"/>
        <circle cx="2" cy="1.6" r="0.5" fill="#FFFFFF" opacity="0.1"/>
        <circle cx="12" cy="1.6" r="0.5" fill="#FFFFFF" opacity="0.1"/>
        <circle cx="22" cy="1.6" r="0.5" fill="#FFFFFF" opacity="0.1"/>

        <!-- Bill denomination value (small text on corner) -->
        <text x="-30" y="2.2" font-size="1.8" font-weight="bold" fill="#FFFFFF" opacity="0.8">
          {bill_text}
        </text>
        <text x="24" y="2.2" font-size="1.8" font-weight="bold" fill="#FFFFFF" opacity="0.8">
          {bill_text}
        </text>
      </g>
    <% end %>
    """
  end

  attr :x1, :integer, required: true
  attr :y1, :integer, required: true
  attr :x2, :integer, required: true
  attr :y2, :integer, required: true
  attr :label, :string, required: true
  attr :active, :boolean, required: true
  attr :animation_speed, :string, default: "2s"

  defp flow_arrow(assigns) do
    ~H"""
    <g>
      <!-- Smooth curved path with dashes -->
      <path
        d={
          "M #{@x1} #{@y1} Q #{div(@x1 + @x2, 2)} #{div(@y1 + @y2, 2) - 30} #{@x2} #{@y2}"
        }
        stroke="#3A7CA5"
        stroke-width="3"
        fill="none"
        stroke-linecap="round"
        stroke-linejoin="round"
        stroke-dasharray="12 6"
        class={["transition-all duration-300", @active && "flow-path-active"]}
      />

      <!-- Arrowhead at end -->
      <polygon
        points={
          "#{@x2},#{@y2} #{@x2 - 8},#{@y2 - 12} #{@x2 + 8},#{@y2 - 12}"
        }
        fill="#3A7CA5"
        class={["transition-opacity", @active && "arrow-active"]}
        opacity={if @active, do: "1", else: "0.4"}
      />

      <!-- Animated coin (💰) along the path -->
      <g :if={@active}>
        <text
          x={@x1}
          y={@y1}
          font-size="24"
          class="coin-active"
          dominant-baseline="middle"
          text-anchor="middle"
        >
          💰
        </text>
      </g>

      <!-- Flow label with background -->
      <% label_x = div(@x1 + @x2, 2) + 20 %>
      <% label_y = div(@y1 + @y2, 2) - 40 %>
      <rect
        x={label_x - 28}
        y={label_y - 9}
        width="56"
        height="14"
        fill="white"
        opacity="0.95"
        rx="3"
      />
      <text
        x={label_x}
        y={label_y}
        text-anchor="middle"
        font-size="14"
        font-weight="bold"
        fill="#1E2A38"
      >
        {@label}
      </text>
    </g>
    """
  end

  attr :x1, :integer, required: true
  attr :y1, :integer, required: true
  attr :x2, :integer, required: true
  attr :y2, :integer, required: true
  attr :label, :string, required: true
  attr :active, :boolean, required: true

  defp flow_arrow_reverse(assigns) do
    ~H"""
    <g>
      <!-- Smooth curved path with dashes - warm gold for reverse flow -->
      <path
        d={
          "M #{@x1} #{@y1} Q #{div(@x1 + @x2, 2)} #{div(@y1 + @y2, 2) + 30} #{@x2} #{@y2}"
        }
        stroke="#E8A03C"
        stroke-width="3"
        fill="none"
        stroke-linecap="round"
        stroke-linejoin="round"
        stroke-dasharray="12 6"
        class={["transition-all duration-300", @active && "flow-path-active"]}
        opacity={if @active, do: "1", else: "0.5"}
      />

      <!-- Arrowhead at end (pointing back) -->
      <polygon
        points={
          "#{@x2},#{@y2} #{@x2 + 8},#{@y2 + 12} #{@x2 - 8},#{@y2 + 12}"
        }
        fill="#E8A03C"
        class={["transition-opacity", @active && "arrow-active"]}
        opacity={if @active, do: "1", else: "0.4"}
      />

      <!-- Animated coin along the path -->
      <g :if={@active}>
        <text
          x={@x1}
          y={@y1}
          font-size="24"
          class="coin-active"
          dominant-baseline="middle"
          text-anchor="middle"
        >
          💵
        </text>
      </g>

      <!-- Flow label with background -->
      <% label_x = div(@x1 + @x2, 2) - 20 %>
      <% label_y = div(@y1 + @y2, 2) + 40 %>
      <rect
        x={label_x - 28}
        y={label_y - 9}
        width="56"
        height="14"
        fill="white"
        opacity="0.95"
        rx="3"
      />
      <text
        x={label_x}
        y={label_y}
        text-anchor="middle"
        font-size="14"
        font-weight="bold"
        fill="#1E2A38"
      >
        {@label}
      </text>
    </g>
    """
  end

  # ===== MODALS =====

  attr :active_modal, :atom
  attr :form_error, :string
  attr :config, :any

  def deposit_modal(assigns) do
    ~H"""
    <div
      :if={@active_modal == :deposit}
      class="fixed inset-0 bg-black/60 backdrop-blur-sm flex items-center justify-center z-50 transition-opacity duration-200"
      phx-click="close_modal"
    >
      <div class="card bg-gradient-to-br from-secondary-50 to-base-100 shadow-2xl max-w-sm w-full mx-4 border border-tertiary-200" phx-click="">
        <div class="card-body">
          <h2 class="card-title text-2xl mb-2 text-primary-700">💵 Record Income</h2>
          <p class="text-sm text-base-content/60 mb-4">Add funds arriving to your expense account</p>

          <form phx-submit="deposit" class="space-y-4">
            <div>
              <label class="label">
                <span class="label-text font-semibold text-primary-700">Amount</span>
              </label>
              <div class="join w-full">
                <span class="join-item bg-tertiary-100 px-4 flex items-center font-bold text-tertiary-700">$</span>
                <input
                  type="number"
                  name="amount"
                  placeholder="0.00"
                  step="0.01"
                  class="input input-bordered join-item flex-1 focus:border-tertiary-400 focus:ring-tertiary-200"
                  required
                  autofocus
                />
              </div>
            </div>

            <div>
              <label class="label">
                <span class="label-text font-semibold text-primary-700">Description</span>
              </label>
              <input
                type="text"
                name="description"
                placeholder="e.g., Service payment"
                class="input input-bordered w-full focus:border-tertiary-400 focus:ring-tertiary-200"
              />
            </div>

            <div :if={@form_error} class="alert alert-error rounded-lg">
              <span>{@form_error}</span>
            </div>

            <div class="card-actions justify-end gap-2 pt-4 border-t border-secondary-200">
              <button type="button" class="btn btn-ghost btn-sm hover:bg-secondary-200" phx-click="close_modal">Cancel</button>
              <button type="submit" class="btn btn-sm text-white" style="background-color: #27AE60; border-color: #27AE60;">Record Income</button>
            </div>
          </form>
        </div>
      </div>
    </div>
    """
  end

  def withdraw_modal(assigns) do
    ~H"""
    <div
      :if={@active_modal == :withdrawal}
      class="fixed inset-0 bg-black/60 backdrop-blur-sm flex items-center justify-center z-50 transition-opacity duration-200"
      phx-click="close_modal"
    >
      <div class="card bg-gradient-to-br from-secondary-50 to-base-100 shadow-2xl max-w-sm w-full mx-4 border border-red-200" phx-click="">
        <div class="card-body">
          <h2 class="card-title text-2xl mb-2 text-primary-700">📤 Record Expense</h2>
          <p class="text-sm text-base-content/60 mb-4">Deduct funds from your expense account</p>

          <form phx-submit="withdraw" class="space-y-4">
            <div>
              <label class="label">
                <span class="label-text font-semibold text-primary-700">Amount</span>
              </label>
              <div class="join w-full">
                <span class="join-item bg-red-100 px-4 flex items-center font-bold text-red-700">$</span>
                <input
                  type="number"
                  name="amount"
                  placeholder="0.00"
                  step="0.01"
                  class="input input-bordered join-item flex-1 focus:border-red-400 focus:ring-red-200"
                  required
                  autofocus
                />
              </div>
            </div>

            <div>
              <label class="label">
                <span class="label-text font-semibold text-primary-700">Description</span>
              </label>
              <input
                type="text"
                name="description"
                placeholder="e.g., Fuel, supplies"
                class="input input-bordered w-full focus:border-red-400 focus:ring-red-200"
              />
            </div>

            <div :if={@form_error} class="alert alert-error rounded-lg">
              <span>{@form_error}</span>
            </div>

            <div class="card-actions justify-end gap-2 pt-4 border-t border-secondary-200">
              <button type="button" class="btn btn-ghost btn-sm hover:bg-secondary-200" phx-click="close_modal">Cancel</button>
              <button type="submit" class="btn btn-sm text-white" style="background-color: #E74C3C; border-color: #E74C3C;">Record Expense</button>
            </div>
          </form>
        </div>
      </div>
    </div>
    """
  end

  def config_modal(assigns) do
    ~H"""
    <div
      :if={@active_modal == :config}
      class="fixed inset-0 bg-black/60 backdrop-blur-sm flex items-center justify-center z-50 transition-opacity duration-200"
      phx-click="close_modal"
    >
      <div class="card bg-gradient-to-br from-secondary-50 to-base-100 shadow-2xl max-w-sm w-full mx-4 border border-primary-300" phx-click="">
        <div class="card-body">
          <h2 class="card-title text-2xl mb-2 text-primary-700">⚙️ Cash Flow Settings</h2>
          <p class="text-sm text-base-content/60 mb-4">Configure thresholds and salary parameters</p>

          <form phx-submit="update_config" class="space-y-4">
            <fieldset name="config">
              <div>
                <label class="label">
                  <span class="label-text font-semibold text-primary-700">Monthly Operating Expense</span>
                </label>
                <div class="join w-full">
                  <span class="join-item bg-primary-100 px-4 flex items-center font-bold text-primary-700">$</span>
                  <input
                    type="number"
                    name="config[monthly_opex_cents]"
                    value={@config && format_cents(@config.monthly_opex_cents)}
                    placeholder="0.00"
                    step="0.01"
                    class="input input-bordered join-item flex-1 focus:border-primary-400 focus:ring-primary-200"
                    required
                  />
                </div>
                <p class="text-xs text-base-content/60 mt-2 bg-primary-50 p-2 rounded">
                  ℹ️ Expense threshold = Opex × 1.25
                </p>
              </div>

              <div>
                <label class="label">
                  <span class="label-text font-semibold text-primary-700">Owner Salary</span>
                </label>
                <div class="join w-full">
                  <span class="join-item bg-primary-100 px-4 flex items-center font-bold text-primary-700">$</span>
                  <input
                    type="number"
                    name="config[salary_cents]"
                    value={@config && format_cents(@config.salary_cents)}
                    placeholder="0.00"
                    step="0.01"
                    class="input input-bordered join-item flex-1 focus:border-primary-400 focus:ring-primary-200"
                    required
                  />
                </div>
              </div>

              <div>
                <label class="label">
                  <span class="label-text font-semibold text-primary-700">Investment Target</span>
                </label>
                <div class="join w-full">
                  <span class="join-item bg-primary-100 px-4 flex items-center font-bold text-primary-700">$</span>
                  <input
                    type="number"
                    name="config[investment_target_cents]"
                    value={@config && format_cents(@config.investment_target_cents)}
                    placeholder="0.00"
                    step="0.01"
                    class="input input-bordered join-item flex-1 focus:border-primary-400 focus:ring-primary-200"
                    required
                  />
                </div>
              </div>
            </fieldset>

            <div :if={@form_error} class="alert alert-error rounded-lg">
              <span>{@form_error}</span>
            </div>

            <div class="card-actions justify-end gap-2 pt-4 border-t border-secondary-200">
              <button type="button" class="btn btn-ghost btn-sm hover:bg-secondary-200" phx-click="close_modal">Cancel</button>
              <button type="submit" class="btn btn-sm text-white" style="background-color: #1E2A38; border-color: #1E2A38;">Update Settings</button>
            </div>
          </form>
        </div>
      </div>
    </div>
    """
  end

  def transfer_modal(assigns) do
    ~H"""
    <div
      :if={@active_modal == :transfer}
      class="fixed inset-0 bg-black/60 backdrop-blur-sm flex items-center justify-center z-50 transition-opacity duration-200"
      phx-click="close_modal"
    >
      <div class="card bg-gradient-to-br from-secondary-50 to-base-100 shadow-2xl max-w-sm w-full mx-4 border border-yellow-300" phx-click="">
        <div class="card-body">
          <h2 class="card-title text-2xl mb-2 text-primary-700">↩ Rebalance to Expense</h2>
          <p class="text-sm text-base-content/60 mb-4">Pull funds back during lean months</p>

          <form phx-submit="transfer" class="space-y-4">
            <div class="alert rounded-lg bg-yellow-50 border border-yellow-200 text-sm">
              <span class="text-yellow-900">📊 Pulls 50% from Business Savings + 50% from Tax Account to replenish Expense Account</span>
            </div>

            <div>
              <label class="label">
                <span class="label-text font-semibold text-primary-700">Amount to Transfer</span>
              </label>
              <div class="join w-full">
                <span class="join-item bg-yellow-100 px-4 flex items-center font-bold text-yellow-700">$</span>
                <input
                  type="number"
                  name="amount"
                  placeholder="0.00"
                  step="0.01"
                  class="input input-bordered join-item flex-1 focus:border-yellow-400 focus:ring-yellow-200"
                  required
                  autofocus
                />
              </div>
            </div>

            <div>
              <label class="label">
                <span class="label-text font-semibold text-primary-700">Description</span>
              </label>
              <input
                type="text"
                name="description"
                placeholder="e.g., Monthly rebalance"
                class="input input-bordered w-full focus:border-yellow-400 focus:ring-yellow-200"
              />
            </div>

            <div class="divider my-2"></div>

            <div class="text-xs space-y-2 bg-primary-50 p-3 rounded-lg">
              <p class="font-semibold text-primary-700 mb-2">How it works:</p>
              <p class="text-primary-700">✓ Business Savings & Tax both contribute equally</p>
              <p class="text-primary-700">✓ Mirrors the reverse of your outflow cascade</p>
              <p class="text-primary-700">✓ Helps maintain operating capital</p>
            </div>

            <div :if={@form_error} class="alert alert-error rounded-lg">
              <span>{@form_error}</span>
            </div>

            <div class="card-actions justify-end gap-2 pt-4 border-t border-secondary-200">
              <button type="button" class="btn btn-ghost btn-sm hover:bg-secondary-200" phx-click="close_modal">Cancel</button>
              <button type="submit" class="btn btn-sm text-white" style="background-color: #E8A03C; border-color: #E8A03C;">Rebalance</button>
            </div>
          </form>
        </div>
      </div>
    </div>
    """
  end

  # ===== HELPERS =====

  defp color_to_stroke("blue"), do: "#3A7CA5"
  defp color_to_stroke("red"), do: "#E74C3C"
  defp color_to_stroke("green"), do: "#27AE60"
  defp color_to_stroke(_), do: "#1E2A38"

  defp format_cents(cents) when is_integer(cents) do
    dollars = div(cents, 100)
    remainder = rem(cents, 100)
    "#{dollars}.#{String.pad_leading("#{remainder}", 2, "0")}"
  end

  defp format_cents(_), do: "0.00"

  def transaction_row(assigns) do
    ~H"""
    <tr class="hover">
      <td class="text-sm">
        <span class="badge badge-sm">{@txn.type}</span>
      </td>
      <td class="text-sm font-mono">${format_cents(@txn.amount_cents)}</td>
      <td class="text-xs text-base-content/60">{@txn.description}</td>
      <td class="text-xs text-base-content/50">
        {Calendar.strftime(@txn.inserted_at, "%m/%d %H:%M")}
      </td>
    </tr>
    """
  end
end
