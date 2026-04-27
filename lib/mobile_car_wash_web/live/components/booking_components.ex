defmodule MobileCarWashWeb.BookingComponents do
  @moduledoc """
  Function components for the multi-step booking flow.
  """
  use Phoenix.Component
  use MobileCarWashWeb, :verified_routes

  @steps [:select_service, :auth, :vehicle, :address, :photos, :schedule, :review, :confirmed]

  attr :current_step, :atom, required: true

  def step_indicator(assigns) do
    labels = step_labels()
    steps = @steps
    current_index = Enum.find_index(steps, &(&1 == assigns.current_step)) || 0
    step_number = current_index + 1
    total_steps = length(steps)
    progress_percent = round(step_number / total_steps * 100)
    current_label = Keyword.get(labels, assigns.current_step, "")

    next_label =
      case Enum.at(steps, current_index + 1) do
        nil -> nil
        next -> Keyword.get(labels, next)
      end

    assigns =
      assign(assigns,
        step_number: step_number,
        total_steps: total_steps,
        progress_percent: progress_percent,
        current_label: current_label,
        next_label: next_label
      )

    ~H"""
    <div class="mb-8">
      <div class="flex items-baseline justify-between mb-2">
        <div class="text-sm font-semibold text-base-content">
          Step {@step_number} of {@total_steps} — {@current_label}
        </div>
        <div class="text-xs text-base-content/60">{@progress_percent}% complete</div>
      </div>
      <div class="h-1.5 bg-base-200 rounded-full overflow-hidden">
        <div
          class="h-full bg-cyan-500 rounded-full transition-all"
          style={"width: #{@progress_percent}%"}
        />
      </div>
      <div :if={@next_label} class="text-xs text-base-content/60 mt-1.5">
        Next: {@next_label}
      </div>
    </div>
    """
  end

  defp step_labels do
    [
      {:select_service, "Service"},
      {:auth, "Account"},
      {:vehicle, "Vehicle"},
      {:address, "Address"},
      {:photos, "Photos"},
      {:schedule, "Schedule"},
      {:review, "Review"},
      {:confirmed, "Done"}
    ]
  end

  attr :service, :map, required: true
  attr :selected, :boolean, default: false

  def service_card(assigns) do
    ~H"""
    <div
      class={[
        "relative bg-base-100 rounded-box p-5 cursor-pointer transition-shadow hover:shadow-md",
        if(@selected, do: "border-2 border-cyan-500", else: "border border-base-300")
      ]}
      phx-click="select_service"
      phx-value-slug={@service.slug}
    >
      <div
        :if={@selected}
        class="absolute top-3 right-3 w-6 h-6 bg-cyan-500 text-white rounded-full flex items-center justify-center text-sm font-bold"
      >
        ✓
      </div>
      <div class="text-xs font-semibold uppercase tracking-wide text-base-content/60 mb-1">
        {@service.name}
      </div>
      <div class="font-mono text-3xl font-bold text-base-content tabular-nums">
        ${div(@service.base_price_cents, 100)}
      </div>
      <div class="text-xs text-base-content/60 mt-0.5 mb-3">
        {@service.duration_minutes} min
      </div>
      <p class="text-sm text-base-content/80">{@service.description}</p>
    </div>
    """
  end

  attr :date, :any, required: true
  attr :blocks, :list, required: true
  attr :selected_block, :any, default: nil

  def block_window_picker(assigns) do
    ~H"""
    <div>
      <div class="form-control mb-6">
        <label class="label"><span class="label-text font-semibold">Select a date</span></label>
        <input
          type="date"
          class="input input-bordered w-full max-w-xs"
          value={@date}
          min={Date.utc_today() |> Date.add(1) |> Date.to_string()}
          phx-change="select_date"
          name="date"
        />
      </div>

      <div :if={@blocks != []} class="space-y-3">
        <p class="text-sm text-base-content/70 mb-2">
          Pick a window. We'll confirm your exact arrival time by midnight the day before.
        </p>
        <button
          :for={block <- @blocks}
          type="button"
          class={[
            "btn btn-block h-auto py-3 justify-between",
            if(@selected_block && @selected_block.id == block.id,
              do: "btn-primary",
              else: "btn-outline"
            )
          ]}
          phx-click="select_block"
          phx-value-id={block.id}
        >
          <span class="font-semibold">
            {Calendar.strftime(block.starts_at, "%I:%M %p")} – {Calendar.strftime(
              block.ends_at,
              "%I:%M %p"
            )}
          </span>
          <span class="text-xs opacity-75">
            {block.capacity - block.appointment_count} of {block.capacity} spots left
          </span>
        </button>
      </div>

      <div :if={@date && @blocks == []} class="alert alert-warning mt-4">
        <span>No available windows for this date. Please try another day.</span>
      </div>
    </div>
    """
  end

  attr :date, :any, required: true
  attr :slots, :list, required: true
  attr :selected_slot, :any, default: nil

  def time_slot_picker(assigns) do
    ~H"""
    <div>
      <div class="form-control mb-6">
        <label class="label"><span class="label-text font-semibold">Select a date</span></label>
        <input
          type="date"
          class="input input-bordered w-full max-w-xs"
          value={@date}
          min={Date.utc_today() |> Date.add(1) |> Date.to_string()}
          phx-change="select_date"
          name="date"
        />
      </div>

      <div :if={@slots != []} class="grid grid-cols-2 md:grid-cols-4 gap-3">
        <button
          :for={slot <- @slots}
          type="button"
          class={[
            "btn",
            if(@selected_slot && DateTime.compare(@selected_slot, slot.starts_at) == :eq,
              do: "btn-primary",
              else: "btn-outline"
            )
          ]}
          phx-click="select_slot"
          phx-value-slot={DateTime.to_iso8601(slot.starts_at)}
        >
          {Calendar.strftime(slot.starts_at, "%I:%M %p")}
        </button>
      </div>

      <div :if={@date && @slots == []} class="alert alert-warning mt-4">
        <span>No available slots for this date. Please try another day.</span>
      </div>
    </div>
    """
  end

  attr :appointment, :map, required: true
  attr :service, :map, required: true
  attr :vehicle, :map, required: true
  attr :address, :map, required: true

  def booking_summary(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-xl">
      <div class="card-body">
        <h3 class="card-title text-xl mb-4">Booking Summary</h3>

        <div class="space-y-4">
          <div>
            <span class="font-semibold">Service:</span>
            <span>{@service.name}</span>
          </div>

          <div>
            <span class="font-semibold">Vehicle:</span>
            <span>{@vehicle.year} {@vehicle.make} {@vehicle.model}</span>
            <span class="badge badge-sm badge-outline ml-2">
              {MobileCarWash.Billing.Pricing.size_label(@vehicle.size)}
            </span>
            <span :if={@vehicle.size != :car} class="text-xs text-warning ml-1">
              ({MobileCarWash.Billing.Pricing.multiplier(@vehicle.size)}x)
            </span>
          </div>

          <div>
            <span class="font-semibold">Location:</span>
            <span>{@address.street}, {@address.city}, {@address.state} {@address.zip}</span>
          </div>

          <div>
            <span class="font-semibold">Date & Time:</span>
            <span>{Calendar.strftime(@appointment.scheduled_at, "%B %d, %Y at %I:%M %p")}</span>
          </div>

          <div>
            <span class="font-semibold">Duration:</span>
            <span>{@service.duration_minutes} minutes</span>
          </div>

          <div class="divider"></div>

          <div class="flex justify-between text-lg">
            <span class="font-bold">Total:</span>
            <div>
              <span
                :if={@appointment.discount_cents > 0}
                class="line-through text-base-content/70 mr-2"
              >
                ${div(@service.base_price_cents, 100)}
              </span>
              <span class="font-bold text-primary">
                ${div(@appointment.price_cents, 100)}
              </span>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :appointment, :map, required: true
  attr :service, :map, required: true

  def confirmation_card(assigns) do
    ~H"""
    <div class="text-center py-8">
      <div class="text-6xl mb-4">✓</div>
      <h2 class="text-3xl font-bold mb-4">Booking Confirmed!</h2>
      <p class="text-lg text-base-content/70 mb-8">
        Your {@service.name} is scheduled for {Calendar.strftime(
          @appointment.scheduled_at,
          "%B %d, %Y at %I:%M %p"
        )}.
      </p>

      <div class="card bg-base-100 shadow-xl max-w-md mx-auto">
        <div class="card-body">
          <p class="text-sm text-base-content/70">Booking ID</p>
          <p class="font-mono text-sm">{@appointment.id}</p>

          <div class="mt-4">
            <span class="badge badge-warning badge-lg">Pending Confirmation</span>
          </div>
        </div>
      </div>

      <div class="mt-8">
        <.link navigate={~p"/"} class="btn btn-primary">
          Back to Home
        </.link>
      </div>
    </div>
    """
  end
end
