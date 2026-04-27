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
  attr :available_dates, :list, default: nil

  def block_window_picker(assigns) do
    available_dates =
      assigns.available_dates ||
        Enum.map(0..6, fn offset -> Date.add(Date.utc_today(), offset) end)

    assigns = assign(assigns, available_dates: available_dates)

    ~H"""
    <div>
      <div class="mb-6">
        <div class="text-sm font-semibold text-base-content mb-2">Pick a date</div>
        <div class="flex gap-2 overflow-x-auto pb-2">
          <button
            :for={d <- @available_dates}
            type="button"
            class={[
              "flex flex-col items-center justify-center w-14 h-14 shrink-0 rounded-lg border transition-colors",
              if(date_match?(@date, d),
                do: "bg-cyan-500 text-white border-cyan-500",
                else: "bg-base-100 border-base-300 text-base-content hover:border-cyan-500"
              )
            ]}
            phx-click="select_date"
            phx-value-date={Date.to_string(d)}
          >
            <div class="text-[10px] font-semibold uppercase tracking-wide opacity-80">
              {Calendar.strftime(d, "%a")}
            </div>
            <div class="text-lg font-bold leading-none">{d.day}</div>
          </button>
        </div>
      </div>

      <div :if={@blocks != []} class="space-y-2">
        <p class="text-sm text-base-content/70 mb-2">
          Pick a window. We'll confirm your exact arrival time by midnight the day before.
        </p>
        <button
          :for={block <- @blocks}
          type="button"
          class={[
            "w-full flex items-center justify-between px-4 py-3 rounded-lg border transition-colors",
            if(@selected_block && @selected_block.id == block.id,
              do: "bg-cyan-500 text-white border-cyan-500",
              else: "bg-base-100 border-base-300 hover:border-cyan-500"
            )
          ]}
          phx-click="select_block"
          phx-value-id={block.id}
        >
          <span class="font-semibold">
            {Calendar.strftime(block.starts_at, "%I:%M %p")} – {Calendar.strftime(block.ends_at, "%I:%M %p")}
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

  defp date_match?(nil, _), do: false
  defp date_match?(%Date{} = a, %Date{} = b), do: Date.compare(a, b) == :eq

  defp date_match?(a, %Date{} = b) when is_binary(a) do
    case Date.from_iso8601(a) do
      {:ok, parsed} -> Date.compare(parsed, b) == :eq
      _ -> false
    end
  end

  defp date_match?(_, _), do: false

  attr :date, :any, required: true
  attr :slots, :list, required: true
  attr :selected_slot, :any, default: nil

  def time_slot_picker(assigns) do
    ~H"""
    <div>
      <div :if={@slots != []} class="grid grid-cols-2 md:grid-cols-4 gap-2">
        <button
          :for={slot <- @slots}
          type="button"
          class={[
            "px-3 py-2 rounded-lg border text-sm font-semibold transition-colors",
            if(@selected_slot && DateTime.compare(@selected_slot, slot.starts_at) == :eq,
              do: "bg-cyan-500 text-white border-cyan-500",
              else: "bg-base-100 border-base-300 hover:border-cyan-500"
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
    <div class="bg-base-100 border border-base-300 rounded-box p-5">
      <h3 class="text-lg font-semibold text-base-content mb-4">Booking Summary</h3>

      <dl class="space-y-3 text-sm">
        <div class="flex justify-between gap-4">
          <dt class="text-base-content/60">Service</dt>
          <dd class="font-semibold text-right">{@service.name}</dd>
        </div>

        <div class="flex justify-between gap-4">
          <dt class="text-base-content/60">Vehicle</dt>
          <dd class="font-semibold text-right">
            {@vehicle.year} {@vehicle.make} {@vehicle.model}
            <span class="ml-1 text-xs font-normal text-base-content/60">
              ({MobileCarWash.Billing.Pricing.size_label(@vehicle.size)})
            </span>
          </dd>
        </div>

        <div class="flex justify-between gap-4">
          <dt class="text-base-content/60">Location</dt>
          <dd class="font-semibold text-right">
            {@address.street}, {@address.city}, {@address.state} {@address.zip}
          </dd>
        </div>

        <div class="flex justify-between gap-4">
          <dt class="text-base-content/60">Date &amp; Time</dt>
          <dd class="font-semibold text-right">
            {Calendar.strftime(@appointment.scheduled_at, "%B %d, %Y at %I:%M %p")}
          </dd>
        </div>

        <div class="flex justify-between gap-4">
          <dt class="text-base-content/60">Duration</dt>
          <dd class="font-semibold text-right">{@service.duration_minutes} minutes</dd>
        </div>
      </dl>

      <div class="border-t border-base-300 mt-4 pt-4 flex justify-between items-baseline">
        <span class="text-sm font-semibold text-base-content">Total</span>
        <div>
          <span :if={@appointment.discount_cents > 0} class="line-through text-base-content/50 mr-2 text-sm">
            ${div(@service.base_price_cents, 100)}
          </span>
          <span class="font-mono text-2xl font-bold text-cyan-700 tabular-nums">
            ${div(@appointment.price_cents, 100)}
          </span>
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
