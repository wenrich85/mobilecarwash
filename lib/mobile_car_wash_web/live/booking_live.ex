defmodule MobileCarWashWeb.BookingLive do
  use MobileCarWashWeb, :live_view

  import MobileCarWashWeb.BookingComponents
  import MobileCarWashWeb.Live.Helpers.EventTracker

  alias MobileCarWash.Scheduling.{ServiceType, Availability, Booking}
  alias MobileCarWash.Fleet.{Vehicle, Address}

  require Ash.Query

  @impl true
  def mount(_params, _session, socket) do
    services =
      ServiceType
      |> Ash.Query.filter(active == true)
      |> Ash.read!()
      |> Enum.sort_by(& &1.base_price_cents)

    socket =
      socket
      |> assign_session_id()
      |> assign(
        page_title: "Book a Wash",
        services: services,
        current_step: :select_service,
        selected_service: nil,
        selected_vehicle: nil,
        selected_address: nil,
        selected_slot: nil,
        selected_date: Date.utc_today() |> Date.add(1) |> Date.to_string(),
        available_slots: [],
        existing_vehicles: [],
        existing_addresses: [],
        appointment: nil,
        # Forms
        vehicle_form: nil,
        address_form: nil,
        # New data forms
        show_new_vehicle_form: false,
        show_new_address_form: false,
        # Timing
        step_started_at: System.monotonic_time(:millisecond),
        flow_started_at: System.monotonic_time(:millisecond)
      )

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket =
      case params do
        %{"service" => slug} ->
          service = Enum.find(socket.assigns.services, &(&1.slug == slug))

          if service do
            socket
            |> assign(selected_service: service)
            |> maybe_advance_past_service()
          else
            socket
          end

        _ ->
          socket
      end

    if connected?(socket) and socket.assigns.current_step == :select_service do
      track_event(socket, "booking.started", %{
        "service" => params["service"],
        "is_authenticated" => socket.assigns.current_customer != nil
      })
    end

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto py-8 px-4">
      <.step_indicator current_step={@current_step} />

      <div :if={@current_step == :select_service}>
        <h2 class="text-2xl font-bold mb-6">Choose Your Service</h2>
        <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
          <.service_card
            :for={service <- @services}
            service={service}
            selected={@selected_service && @selected_service.id == service.id}
          />
        </div>
        <div :if={@selected_service} class="mt-8 text-right">
          <button class="btn btn-primary" phx-click="next_step">Continue</button>
        </div>
      </div>

      <div :if={@current_step == :auth}>
        <h2 class="text-2xl font-bold mb-6">Sign In or Create Account</h2>
        <div :if={@current_customer}>
          <div class="alert alert-success mb-6">
            <span>Welcome back, {@current_customer.name}!</span>
          </div>
          <button class="btn btn-primary" phx-click="next_step">Continue</button>
        </div>
        <div :if={!@current_customer}>
          <p class="text-base-content/70 mb-4">
            Please sign in or create an account to continue booking.
          </p>
          <div class="flex gap-4">
            <.link navigate={~p"/sign-in"} class="btn btn-primary">
              Sign In
            </.link>
            <.link navigate={~p"/sign-in"} class="btn btn-outline">
              Create Account
            </.link>
          </div>
        </div>
      </div>

      <div :if={@current_step == :vehicle}>
        <h2 class="text-2xl font-bold mb-6">Select Your Vehicle</h2>

        <div :if={@existing_vehicles != []} class="space-y-4 mb-6">
          <div
            :for={vehicle <- @existing_vehicles}
            class={[
              "card bg-base-100 shadow cursor-pointer hover:shadow-lg transition-shadow",
              @selected_vehicle && @selected_vehicle.id == vehicle.id && "ring-2 ring-primary"
            ]}
            phx-click="select_vehicle"
            phx-value-id={vehicle.id}
          >
            <div class="card-body py-3">
              <span class="font-semibold">{vehicle.year} {vehicle.make} {vehicle.model}</span>
              <span class="text-sm text-base-content/50">{vehicle.color} · {vehicle.size}</span>
            </div>
          </div>
        </div>

        <button
          :if={!@show_new_vehicle_form}
          class="btn btn-outline btn-sm mb-6"
          phx-click="show_new_vehicle"
        >
          + Add New Vehicle
        </button>

        <form :if={@show_new_vehicle_form} phx-submit="save_vehicle" class="space-y-4 mb-6">
          <div class="grid grid-cols-2 gap-4">
            <div class="form-control">
              <label class="label"><span class="label-text">Make</span></label>
              <input type="text" name="vehicle[make]" class="input input-bordered" required placeholder="Toyota" />
            </div>
            <div class="form-control">
              <label class="label"><span class="label-text">Model</span></label>
              <input type="text" name="vehicle[model]" class="input input-bordered" required placeholder="Camry" />
            </div>
          </div>
          <div class="grid grid-cols-3 gap-4">
            <div class="form-control">
              <label class="label"><span class="label-text">Year</span></label>
              <input type="number" name="vehicle[year]" class="input input-bordered" min="1990" max="2027" placeholder="2024" />
            </div>
            <div class="form-control">
              <label class="label"><span class="label-text">Color</span></label>
              <input type="text" name="vehicle[color]" class="input input-bordered" placeholder="Silver" />
            </div>
            <div class="form-control">
              <label class="label"><span class="label-text">Size</span></label>
              <select name="vehicle[size]" class="select select-bordered">
                <option value="sedan">Sedan</option>
                <option value="suv">SUV</option>
                <option value="truck">Truck</option>
                <option value="van">Van</option>
              </select>
            </div>
          </div>
          <button type="submit" class="btn btn-primary">Save Vehicle</button>
        </form>

        <div :if={@selected_vehicle} class="mt-4 text-right">
          <button class="btn btn-primary" phx-click="next_step">Continue</button>
        </div>
      </div>

      <div :if={@current_step == :address}>
        <h2 class="text-2xl font-bold mb-6">Service Location</h2>

        <div :if={@existing_addresses != []} class="space-y-4 mb-6">
          <div
            :for={addr <- @existing_addresses}
            class={[
              "card bg-base-100 shadow cursor-pointer hover:shadow-lg transition-shadow",
              @selected_address && @selected_address.id == addr.id && "ring-2 ring-primary"
            ]}
            phx-click="select_address"
            phx-value-id={addr.id}
          >
            <div class="card-body py-3">
              <span class="font-semibold">{addr.street}</span>
              <span class="text-sm text-base-content/50">{addr.city}, {addr.state} {addr.zip}</span>
            </div>
          </div>
        </div>

        <button
          :if={!@show_new_address_form}
          class="btn btn-outline btn-sm mb-6"
          phx-click="show_new_address"
        >
          + Add New Address
        </button>

        <form :if={@show_new_address_form} phx-submit="save_address" class="space-y-4 mb-6">
          <div class="form-control">
            <label class="label"><span class="label-text">Street Address</span></label>
            <input type="text" name="address[street]" class="input input-bordered" required placeholder="123 Main St" />
          </div>
          <div class="grid grid-cols-3 gap-4">
            <div class="form-control">
              <label class="label"><span class="label-text">City</span></label>
              <input type="text" name="address[city]" class="input input-bordered" required placeholder="Austin" />
            </div>
            <div class="form-control">
              <label class="label"><span class="label-text">State</span></label>
              <input type="text" name="address[state]" class="input input-bordered" required value="TX" />
            </div>
            <div class="form-control">
              <label class="label"><span class="label-text">ZIP</span></label>
              <input type="text" name="address[zip]" class="input input-bordered" required placeholder="78701" />
            </div>
          </div>
          <button type="submit" class="btn btn-primary">Save Address</button>
        </form>

        <div :if={@selected_address} class="mt-4 text-right">
          <button class="btn btn-primary" phx-click="next_step">Continue</button>
        </div>
      </div>

      <div :if={@current_step == :schedule}>
        <h2 class="text-2xl font-bold mb-6">Pick a Date & Time</h2>
        <.time_slot_picker
          date={@selected_date}
          slots={@available_slots}
          selected_slot={@selected_slot}
        />
        <div :if={@selected_slot} class="mt-8 text-right">
          <button class="btn btn-primary" phx-click="next_step">Continue</button>
        </div>
      </div>

      <div :if={@current_step == :review}>
        <h2 class="text-2xl font-bold mb-6">Review Your Booking</h2>
        <.booking_summary
          appointment={%{
            scheduled_at: @selected_slot,
            price_cents: @selected_service.base_price_cents,
            discount_cents: 0
          }}
          service={@selected_service}
          vehicle={@selected_vehicle}
          address={@selected_address}
        />
        <div class="mt-8 flex gap-4 justify-end">
          <button class="btn btn-outline" phx-click="prev_step">Back</button>
          <button class="btn btn-primary btn-lg" phx-click="confirm_booking">
            Confirm Booking
          </button>
        </div>
      </div>

      <div :if={@current_step == :confirmed && @appointment}>
        <.confirmation_card appointment={@appointment} service={@selected_service} />
      </div>

      <!-- Back button (except on first and last steps) -->
      <div :if={@current_step not in [:select_service, :confirmed]} class="mt-4">
        <button class="btn btn-ghost btn-sm" phx-click="prev_step">
          ← Back
        </button>
      </div>
    </div>
    """
  end

  # --- Event Handlers ---

  @impl true
  def handle_event("select_service", %{"slug" => slug}, socket) do
    service = Enum.find(socket.assigns.services, &(&1.slug == slug))
    {:noreply, assign(socket, selected_service: service)}
  end

  def handle_event("next_step", _params, socket) do
    socket = track_step_completion(socket)
    {:noreply, advance_step(socket)}
  end

  def handle_event("prev_step", _params, socket) do
    {:noreply, retreat_step(socket)}
  end

  def handle_event("show_new_vehicle", _params, socket) do
    {:noreply, assign(socket, show_new_vehicle_form: true)}
  end

  def handle_event("show_new_address", _params, socket) do
    {:noreply, assign(socket, show_new_address_form: true)}
  end

  def handle_event("save_vehicle", %{"vehicle" => vehicle_params}, socket) do
    customer = socket.assigns.current_customer

    attrs =
      vehicle_params
      |> Map.put("customer_id", customer.id)
      |> Enum.map(fn {k, v} -> {String.to_existing_atom(k), v} end)
      |> Map.new()
      |> Map.update(:year, nil, fn v -> if is_binary(v) and v != "", do: String.to_integer(v), else: nil end)

    case Vehicle
         |> Ash.Changeset.for_create(:create, attrs)
         |> Ash.create() do
      {:ok, vehicle} ->
        track_event(socket, "booking.vehicle_added", %{"vehicle_id" => vehicle.id, "is_new" => true})

        {:noreply,
         socket
         |> assign(
           selected_vehicle: vehicle,
           show_new_vehicle_form: false,
           existing_vehicles: socket.assigns.existing_vehicles ++ [vehicle]
         )}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not save vehicle. Please check your input.")}
    end
  end

  def handle_event("select_vehicle", %{"id" => id}, socket) do
    vehicle = Enum.find(socket.assigns.existing_vehicles, &(&1.id == id))
    track_event(socket, "booking.vehicle_added", %{"vehicle_id" => id, "is_new" => false})
    {:noreply, assign(socket, selected_vehicle: vehicle)}
  end

  def handle_event("save_address", %{"address" => address_params}, socket) do
    customer = socket.assigns.current_customer

    attrs =
      address_params
      |> Map.put("customer_id", customer.id)
      |> Enum.map(fn {k, v} -> {String.to_existing_atom(k), v} end)
      |> Map.new()

    case Address
         |> Ash.Changeset.for_create(:create, attrs)
         |> Ash.create() do
      {:ok, address} ->
        track_event(socket, "booking.address_added", %{"address_id" => address.id, "is_new" => true})

        {:noreply,
         socket
         |> assign(
           selected_address: address,
           show_new_address_form: false,
           existing_addresses: socket.assigns.existing_addresses ++ [address]
         )}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not save address. Please check your input.")}
    end
  end

  def handle_event("select_address", %{"id" => id}, socket) do
    address = Enum.find(socket.assigns.existing_addresses, &(&1.id == id))
    track_event(socket, "booking.address_added", %{"address_id" => id, "is_new" => false})
    {:noreply, assign(socket, selected_address: address)}
  end

  def handle_event("select_date", %{"date" => date_str}, socket) do
    case Date.from_iso8601(date_str) do
      {:ok, date} ->
        duration = socket.assigns.selected_service.duration_minutes

        # Query existing appointments for this date
        {:ok, day_start} = DateTime.new(date, ~T[00:00:00])
        {:ok, day_end} = DateTime.new(Date.add(date, 1), ~T[00:00:00])

        existing =
          MobileCarWash.Scheduling.Appointment
          |> Ash.Query.filter(
            scheduled_at >= ^day_start and
              scheduled_at < ^day_end and
              status in [:pending, :confirmed, :in_progress]
          )
          |> Ash.read!()
          |> Enum.map(&%{scheduled_at: &1.scheduled_at, duration_minutes: &1.duration_minutes})

        slots = Availability.available_slots(date, duration, existing)

        {:noreply,
         assign(socket,
           selected_date: date_str,
           available_slots: slots,
           selected_slot: nil
         )}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("select_slot", %{"slot" => slot_str}, socket) do
    case DateTime.from_iso8601(slot_str) do
      {:ok, datetime, _offset} ->
        track_event(socket, "booking.slot_selected", %{
          "scheduled_at" => slot_str,
          "day_of_week" => Date.day_of_week(DateTime.to_date(datetime))
        })

        {:noreply, assign(socket, selected_slot: datetime)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("confirm_booking", _params, socket) do
    %{
      current_customer: customer,
      selected_service: service,
      selected_vehicle: vehicle,
      selected_address: address,
      selected_slot: slot
    } = socket.assigns

    booking_params = %{
      customer_id: customer.id,
      service_type_id: service.id,
      vehicle_id: vehicle.id,
      address_id: address.id,
      scheduled_at: slot,
      subscription_id: nil
    }

    case Booking.create_booking(booking_params) do
      {:ok, %{appointment: appointment, checkout_url: checkout_url}} when not is_nil(checkout_url) ->
        # Redirect to Stripe Checkout
        elapsed = System.monotonic_time(:millisecond) - socket.assigns.flow_started_at

        track_event(socket, "booking.payment_started", %{
          "appointment_id" => appointment.id,
          "service_slug" => service.slug,
          "price_cents" => appointment.price_cents,
          "total_time_ms" => elapsed
        })

        {:noreply, redirect(socket, external: checkout_url)}

      {:ok, %{appointment: appointment, checkout_url: nil}} ->
        # Fully covered by subscription or Stripe unavailable — show confirmation
        elapsed = System.monotonic_time(:millisecond) - socket.assigns.flow_started_at

        track_event(socket, "booking.completed", %{
          "appointment_id" => appointment.id,
          "service_slug" => service.slug,
          "price_cents" => appointment.price_cents,
          "discount_cents" => appointment.discount_cents,
          "total_time_ms" => elapsed,
          "payment_method" => "subscription"
        })

        {:noreply,
         socket
         |> assign(appointment: appointment, current_step: :confirmed)
         |> put_flash(:info, "Booking confirmed!")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Booking failed: #{inspect(reason)}. Please try again.")}
    end
  end

  # --- Step Navigation ---

  defp advance_step(socket) do
    current = socket.assigns.current_step
    next = next_step(current, socket)

    socket
    |> assign(current_step: next, step_started_at: System.monotonic_time(:millisecond))
    |> load_step_data(next)
  end

  defp retreat_step(socket) do
    current = socket.assigns.current_step
    prev = prev_step(current, socket)
    assign(socket, current_step: prev, step_started_at: System.monotonic_time(:millisecond))
  end

  defp next_step(:select_service, socket) do
    if socket.assigns.current_customer, do: :vehicle, else: :auth
  end

  defp next_step(:auth, socket) do
    if socket.assigns.current_customer, do: :vehicle, else: :auth
  end

  defp next_step(:vehicle, _socket), do: :address
  defp next_step(:address, _socket), do: :schedule
  defp next_step(:schedule, _socket), do: :review
  defp next_step(:review, _socket), do: :confirmed
  defp next_step(step, _socket), do: step

  defp prev_step(:auth, _socket), do: :select_service
  defp prev_step(:vehicle, socket) do
    if socket.assigns.current_customer, do: :select_service, else: :auth
  end
  defp prev_step(:address, _socket), do: :vehicle
  defp prev_step(:schedule, _socket), do: :address
  defp prev_step(:review, _socket), do: :schedule
  defp prev_step(step, _socket), do: step

  defp maybe_advance_past_service(socket) do
    if socket.assigns.selected_service do
      socket
      |> assign(current_step: :select_service)
    else
      socket
    end
  end

  defp load_step_data(socket, :vehicle) do
    customer = socket.assigns.current_customer

    if customer do
      vehicles = Ash.read!(Vehicle, action: :for_customer, arguments: %{customer_id: customer.id})

      assign(socket,
        existing_vehicles: vehicles,
        show_new_vehicle_form: vehicles == []
      )
    else
      socket
    end
  end

  defp load_step_data(socket, :address) do
    customer = socket.assigns.current_customer

    if customer do
      addresses = Ash.read!(Address, action: :for_customer, arguments: %{customer_id: customer.id})

      assign(socket,
        existing_addresses: addresses,
        show_new_address_form: addresses == []
      )
    else
      socket
    end
  end

  defp load_step_data(socket, :schedule) do
    date = socket.assigns.selected_date
    duration = socket.assigns.selected_service.duration_minutes

    case Date.from_iso8601(date) do
      {:ok, parsed_date} ->
        slots = Availability.available_slots(parsed_date, duration, [])
        assign(socket, available_slots: slots)

      _ ->
        socket
    end
  end

  defp load_step_data(socket, _step), do: socket

  defp track_step_completion(socket) do
    elapsed = System.monotonic_time(:millisecond) - socket.assigns.step_started_at

    track_event(socket, "booking.step_completed", %{
      "step" => to_string(socket.assigns.current_step),
      "time_on_step_ms" => elapsed
    })

    socket
  end
end
