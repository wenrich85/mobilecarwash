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
        class="w-full max-w-5xl mx-auto border-2 border-base-300 rounded-xl bg-gradient-to-br from-base-100 to-base-200 p-6"
      >
        <defs>
          <!-- Gradients for buckets -->
          <linearGradient id="blueGrad" x1="0%" y1="0%" x2="0%" y2="100%">
            <stop offset="0%" style="stop-color:hsl(var(--in));stop-opacity:0.8" />
            <stop offset="100%" style="stop-color:hsl(var(--in));stop-opacity:0.4" />
          </linearGradient>

          <linearGradient id="redGrad" x1="0%" y1="0%" x2="0%" y2="100%">
            <stop offset="0%" style="stop-color:hsl(var(--er));stop-opacity:0.8" />
            <stop offset="100%" style="stop-color:hsl(var(--er));stop-opacity:0.4" />
          </linearGradient>

          <linearGradient id="greenGrad" x1="0%" y1="0%" x2="0%" y2="100%">
            <stop offset="0%" style="stop-color:hsl(var(--su));stop-opacity:0.8" />
            <stop offset="100%" style="stop-color:hsl(var(--su));stop-opacity:0.4" />
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

      <!-- Bucket liquid fill -->
      <path
        d={
          "M #{@cx - 38} #{@cy + 70 - @fill_height} L #{@cx - 36} #{@cy + 70} Q #{@cx} #{@cy + 76} #{@cx + 36} #{@cy + 70} L #{@cx + 38} #{@cy + 70 - @fill_height} Q #{@cx} #{@cy + 66 - @fill_height} #{@cx - 38} #{@cy + 70 - @fill_height}"
        }
        fill={"url(##{@gradient_id})"}
        opacity="0.7"
      />

      <!-- Liquid surface (shimmer effect) -->
      <ellipse
        cx={@cx}
        cy={@cy + 70 - @fill_height}
        rx="36"
        ry="6"
        fill={@color_stroke}
        opacity="0.15"
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
        class="text-sm font-bold fill-base-content"
        font-size="18"
      >
        {@label}
      </text>

      <!-- Fill percentage inside bucket -->
      <text
        x={@cx}
        y={@cy + 35}
        text-anchor="middle"
        class="text-xs font-bold fill-base-content"
        font-size="16"
      >
        {trunc(@fill_pct * 100)}%
      </text>

      <!-- Balance below bucket -->
      <text
        x={@cx}
        y={@cy + 95}
        text-anchor="middle"
        class="text-sm font-semibold fill-base-content"
        font-size="16"
      >
        ${format_cents(@balance_cents)}
      </text>

      <!-- Threshold indicator -->
      <text :if={@threshold_cents} x={@cx} y={@cy + 115} text-anchor="middle" class="text-xs fill-base-content/50" font-size="13">
        Target: ${format_cents(@threshold_cents)}
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
  attr :animation_speed, :string, default: "2s"

  defp flow_arrow(assigns) do
    ~H"""
    <g>
      <!-- Smooth curved path with dashes -->
      <path
        d={
          "M #{@x1} #{@y1} Q #{div(@x1 + @x2, 2)} #{div(@y1 + @y2, 2) - 30} #{@x2} #{@y2}"
        }
        stroke="hsl(var(--p))"
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
        fill="hsl(var(--p))"
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

      <!-- Flow label -->
      <text
        x={div(@x1 + @x2, 2) + 20}
        y={div(@y1 + @y2, 2) - 40}
        class="text-xs font-semibold fill-base-content/70"
        font-size="14"
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
      <!-- Smooth curved path with dashes - orange for reverse flow -->
      <path
        d={
          "M #{@x1} #{@y1} Q #{div(@x1 + @x2, 2)} #{div(@y1 + @y2, 2) + 30} #{@x2} #{@y2}"
        }
        stroke="hsl(var(--wa))"
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
        fill="hsl(var(--wa))"
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

      <!-- Flow label -->
      <text
        x={div(@x1 + @x2, 2) - 20}
        y={div(@y1 + @y2, 2) + 40}
        class="text-xs font-semibold fill-base-content/70"
        font-size="14"
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
      class="fixed inset-0 bg-black/50 flex items-center justify-center z-50 transition-opacity duration-200"
      phx-click="close_modal"
    >
      <div class="card bg-base-100 shadow-2xl max-w-sm w-full mx-4" phx-click="">
        <div class="card-body">
          <h2 class="card-title text-2xl mb-4">💵 Record Income</h2>

          <form phx-submit="deposit" class="space-y-4">
            <div>
              <label class="label">
                <span class="label-text font-semibold">Amount</span>
              </label>
              <div class="join w-full">
                <span class="join-item bg-base-200 px-4 flex items-center font-bold">$</span>
                <input
                  type="number"
                  name="amount"
                  placeholder="0.00"
                  step="0.01"
                  class="input input-bordered join-item flex-1"
                  required
                  autofocus
                />
              </div>
            </div>

            <div>
              <label class="label">
                <span class="label-text font-semibold">Description</span>
              </label>
              <input
                type="text"
                name="description"
                placeholder="e.g., Service payment"
                class="input input-bordered w-full"
              />
            </div>

            <div :if={@form_error} class="alert alert-error">
              <span>{@form_error}</span>
            </div>

            <div class="card-actions justify-end gap-2 pt-4">
              <button type="button" class="btn btn-ghost" phx-click="close_modal">Cancel</button>
              <button type="submit" class="btn btn-success">Record Income</button>
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
      class="fixed inset-0 bg-black/50 flex items-center justify-center z-50 transition-opacity duration-200"
      phx-click="close_modal"
    >
      <div class="card bg-base-100 shadow-2xl max-w-sm w-full mx-4" phx-click="">
        <div class="card-body">
          <h2 class="card-title text-2xl mb-4">📤 Record Expense</h2>

          <form phx-submit="withdraw" class="space-y-4">
            <div>
              <label class="label">
                <span class="label-text font-semibold">Amount</span>
              </label>
              <div class="join w-full">
                <span class="join-item bg-base-200 px-4 flex items-center font-bold">$</span>
                <input
                  type="number"
                  name="amount"
                  placeholder="0.00"
                  step="0.01"
                  class="input input-bordered join-item flex-1"
                  required
                  autofocus
                />
              </div>
            </div>

            <div>
              <label class="label">
                <span class="label-text font-semibold">Description</span>
              </label>
              <input
                type="text"
                name="description"
                placeholder="e.g., Fuel, supplies"
                class="input input-bordered w-full"
              />
            </div>

            <div :if={@form_error} class="alert alert-error">
              <span>{@form_error}</span>
            </div>

            <div class="card-actions justify-end gap-2 pt-4">
              <button type="button" class="btn btn-ghost" phx-click="close_modal">Cancel</button>
              <button type="submit" class="btn btn-error">Record Expense</button>
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
      class="fixed inset-0 bg-black/50 flex items-center justify-center z-50 transition-opacity duration-200"
      phx-click="close_modal"
    >
      <div class="card bg-base-100 shadow-2xl max-w-sm w-full mx-4" phx-click="">
        <div class="card-body">
          <h2 class="card-title text-2xl mb-4">⚙️ Cash Flow Settings</h2>

          <form phx-submit="update_config" class="space-y-4">
            <fieldset name="config">
              <div>
                <label class="label">
                  <span class="label-text font-semibold">Monthly Operating Expense</span>
                </label>
                <div class="join w-full">
                  <span class="join-item bg-base-200 px-4 flex items-center font-bold">$</span>
                  <input
                    type="number"
                    name="config[monthly_opex_cents]"
                    value={@config && format_cents(@config.monthly_opex_cents)}
                    placeholder="0.00"
                    step="0.01"
                    class="input input-bordered join-item flex-1"
                    required
                  />
                </div>
                <p class="text-xs text-base-content/60 mt-2">
                  ℹ️ Expense threshold = Opex × 1.25
                </p>
              </div>

              <div>
                <label class="label">
                  <span class="label-text font-semibold">Owner Salary</span>
                </label>
                <div class="join w-full">
                  <span class="join-item bg-base-200 px-4 flex items-center font-bold">$</span>
                  <input
                    type="number"
                    name="config[salary_cents]"
                    value={@config && format_cents(@config.salary_cents)}
                    placeholder="0.00"
                    step="0.01"
                    class="input input-bordered join-item flex-1"
                    required
                  />
                </div>
              </div>

              <div>
                <label class="label">
                  <span class="label-text font-semibold">Investment Target</span>
                </label>
                <div class="join w-full">
                  <span class="join-item bg-base-200 px-4 flex items-center font-bold">$</span>
                  <input
                    type="number"
                    name="config[investment_target_cents]"
                    value={@config && format_cents(@config.investment_target_cents)}
                    placeholder="0.00"
                    step="0.01"
                    class="input input-bordered join-item flex-1"
                    required
                  />
                </div>
              </div>
            </fieldset>

            <div :if={@form_error} class="alert alert-error">
              <span>{@form_error}</span>
            </div>

            <div class="card-actions justify-end gap-2 pt-4">
              <button type="button" class="btn btn-ghost" phx-click="close_modal">Cancel</button>
              <button type="submit" class="btn btn-primary">Update Settings</button>
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
      class="fixed inset-0 bg-black/50 flex items-center justify-center z-50 transition-opacity duration-200"
      phx-click="close_modal"
    >
      <div class="card bg-base-100 shadow-2xl max-w-sm w-full mx-4" phx-click="">
        <div class="card-body">
          <h2 class="card-title text-2xl mb-4">↩ Rebalance to Expense</h2>

          <form phx-submit="transfer" class="space-y-4">
            <div class="alert alert-info text-sm">
              <span>📊 Pulls 50% from Business Savings + 50% from Tax Account to replenish Expense Account</span>
            </div>

            <div>
              <label class="label">
                <span class="label-text font-semibold">Amount to Transfer</span>
              </label>
              <div class="join w-full">
                <span class="join-item bg-base-200 px-4 flex items-center font-bold">$</span>
                <input
                  type="number"
                  name="amount"
                  placeholder="0.00"
                  step="0.01"
                  class="input input-bordered join-item flex-1"
                  required
                  autofocus
                />
              </div>
            </div>

            <div>
              <label class="label">
                <span class="label-text font-semibold">Description</span>
              </label>
              <input
                type="text"
                name="description"
                placeholder="e.g., Monthly rebalance"
                class="input input-bordered w-full"
              />
            </div>

            <div class="divider my-2"></div>

            <div class="text-xs text-base-content/60 space-y-1">
              <p>✓ Business Savings & Tax both contribute equally</p>
              <p>✓ Mirrors the reverse of your outflow cascade</p>
              <p>✓ Helps maintain operating capital</p>
            </div>

            <div :if={@form_error} class="alert alert-error">
              <span>{@form_error}</span>
            </div>

            <div class="card-actions justify-end gap-2 pt-4">
              <button type="button" class="btn btn-ghost" phx-click="close_modal">Cancel</button>
              <button type="submit" class="btn btn-warning">Rebalance</button>
            </div>
          </form>
        </div>
      </div>
    </div>
    """
  end

  # ===== HELPERS =====

  defp color_to_stroke("blue"), do: "hsl(var(--in))"
  defp color_to_stroke("red"), do: "hsl(var(--er))"
  defp color_to_stroke("green"), do: "hsl(var(--su))"
  defp color_to_stroke(_), do: "hsl(var(--p))"

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
