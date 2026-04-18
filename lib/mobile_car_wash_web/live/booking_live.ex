defmodule MobileCarWashWeb.BookingLive do
  use MobileCarWashWeb, :live_view

  import MobileCarWashWeb.BookingComponents
  import MobileCarWashWeb.Live.Helpers.EventTracker

  alias MobileCarWash.Scheduling.{ServiceType, BlockAvailability, Booking}
  alias MobileCarWash.Fleet.{Vehicle, Address}
  alias MobileCarWash.Booking.{StateMachine, SessionCache}
  alias MobileCarWash.Billing.{Subscription, SubscriptionUsage}

  require Ash.Query

  # --- Mount: restore state from cache or start fresh ---

  @impl true
  def mount(_params, session, socket) do
    services =
      ServiceType
      |> Ash.Query.filter(active == true)
      |> Ash.read!()
      |> Enum.sort_by(& &1.base_price_cents)

    booking_session_id = derive_session_id(session)

    # Restore from cache if reconnecting
    {restored_step, restored_assigns} =
      case SessionCache.get(booking_session_id) do
        nil -> {:select_service, %{}}
        cached -> restore_from_cache(cached)
      end

    # Build context — prefer session customer, fall back to cached customer (for guests)
    customer = socket.assigns[:current_customer] || restored_assigns[:current_customer]

    base_assigns = %{
      selected_service: restored_assigns[:selected_service],
      current_customer: customer,
      guest_mode: restored_assigns[:guest_mode] || false,
      selected_vehicle: restored_assigns[:selected_vehicle],
      selected_address: restored_assigns[:selected_address],
      selected_slot: restored_assigns[:selected_slot],
      selected_block: restored_assigns[:selected_block],
      appointment: nil
    }

    validated_step = StateMachine.resolve_step(restored_step, base_assigns)

    require Logger
    Logger.warning("MOUNT: restored_step=#{restored_step}, validated=#{validated_step}, customer=#{customer && customer.id}, service=#{base_assigns.selected_service && "yes"}, vehicle=#{base_assigns.selected_vehicle && "yes"}")

    socket =
      socket
      |> assign_session_id()
      |> assign(
        page_title: "Book a Wash",
        meta_description: "Book a mobile car wash or detail online. Choose your service, pick a time, and we come to you. Same-day availability. Veteran-owned.",
        meta_keywords: "book mobile car wash, schedule car detail, online car wash booking, same day car wash, mobile detailing appointment",
        canonical_path: "/book",
        services: services,
        booking_session_id: booking_session_id,
        # State machine
        current_step: validated_step,
        # Accumulated booking data (override on_mount's nil customer with cached guest)
        current_customer: customer,
        selected_service: base_assigns.selected_service,
        selected_vehicle: base_assigns.selected_vehicle,
        selected_address: base_assigns.selected_address,
        selected_slot: base_assigns.selected_slot,
        selected_block: base_assigns.selected_block,
        appointment: nil,
        guest_mode: base_assigns.guest_mode,
        guest_error: nil,
        # UI state
        selected_date: Date.utc_today() |> Date.add(1) |> Date.to_string(),
        available_blocks: [],
        existing_vehicles: [],
        existing_addresses: [],
        show_new_vehicle_form: false,
        show_new_address_form: false,
        # Forms
        vehicle_form: nil,
        address_form: nil,
        # Photos
        uploaded_photos: [],
        # Subscription
        active_subscription: load_active_subscription(customer),
        # Loyalty punch card
        loyalty_card: load_loyalty_card(customer),
        redeem_loyalty: false,
        # Referral
        referral_code: nil,
        referral_discount: 0,
        referral_error: nil,
        # Timing
        step_started_at: System.monotonic_time(:millisecond),
        flow_started_at: System.monotonic_time(:millisecond)
      )
      |> allow_upload(:problem_photo,
        accept: ~w(.jpg .jpeg .png .webp),
        max_entries: 5,
        max_file_size: 10_000_000
      )
      |> load_step_data(validated_step)

    if connected?(socket), do: MobileCarWash.CatalogBroadcaster.subscribe()

    {:ok, socket}
  end

  @impl true
  def handle_info(:services_updated, socket) do
    services =
      ServiceType
      |> Ash.Query.filter(active == true)
      |> Ash.read!()
      |> Enum.sort_by(& &1.base_price_cents)

    {:noreply, assign(socket, services: services)}
  end

  def handle_info(:plans_updated, socket), do: {:noreply, socket}

  # --- Handle Params: only process service param if on step 1 ---

  @impl true
  def handle_params(params, _uri, socket) do
    require Logger
    Logger.warning("HANDLE_PARAMS: current_step=#{socket.assigns.current_step}, params=#{inspect(params)}")

    socket =
      case {params, socket.assigns.current_step} do
        {%{"service" => slug}, :select_service} ->
          case Enum.find(socket.assigns.services, &(&1.slug == slug)) do
            nil -> socket
            service -> assign(socket, selected_service: service)
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

  # === RENDER (unchanged template) ===

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
        <h2 class="text-2xl font-bold mb-6">How would you like to continue?</h2>

        <div :if={@current_customer}>
          <div class="alert alert-success mb-6">
            <span>Welcome back, {@current_customer.name}!</span>
          </div>
          <button class="btn btn-primary" phx-click="next_step">Continue</button>
        </div>

        <div :if={!@current_customer} class="space-y-6">
          <div class="card bg-base-100 shadow-xl border-2 border-primary">
            <div class="card-body">
              <h3 class="card-title">Continue as Guest</h3>
              <p class="text-sm text-base-content/60">
                No account needed. Just provide your contact info and we'll get you booked.
              </p>

              <div :if={@guest_error} class="alert alert-error alert-sm mt-2">
                <span>{@guest_error}</span>
              </div>

              <form phx-submit="guest_checkout" class="mt-4 space-y-3">
                <div class="form-control">
                  <label class="label"><span class="label-text">Name *</span></label>
                  <input type="text" name="guest[name]" class="input input-bordered" required placeholder="Your full name" />
                </div>
                <div class="form-control">
                  <label class="label"><span class="label-text">Email *</span></label>
                  <input type="email" name="guest[email]" class="input input-bordered" required placeholder="your@email.com" />
                </div>
                <div class="form-control">
                  <label class="label"><span class="label-text">Phone</span></label>
                  <input type="tel" name="guest[phone]" class="input input-bordered" placeholder="512-555-0100" />
                </div>
                <button type="submit" class="btn btn-primary btn-block">
                  Continue as Guest
                </button>
              </form>
            </div>
          </div>

          <div class="divider">OR</div>

          <div class="card bg-base-100 shadow">
            <div class="card-body">
              <h3 class="card-title text-base">Have an account?</h3>
              <p class="text-sm text-base-content/60">
                Sign in to use saved vehicles and addresses, or create an account for future bookings.
              </p>
              <div class="flex gap-3 mt-3">
                <.link navigate={~p"/sign-in"} class="btn btn-outline btn-sm flex-1">
                  Sign In
                </.link>
                <.link navigate={~p"/sign-in"} class="btn btn-ghost btn-sm flex-1">
                  Create Account
                </.link>
              </div>
            </div>
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
            <div class="form-control col-span-3">
              <label class="label"><span class="label-text">Vehicle Type *</span></label>
              <div class="grid grid-cols-3 gap-2">
                <label class="cursor-pointer label border rounded-lg p-3 hover:border-primary transition-colors">
                  <div>
                    <input type="radio" name="vehicle[size]" value="car" class="radio radio-primary radio-sm" checked />
                    <span class="ml-2 font-semibold">Car</span>
                    <p class="text-xs text-base-content/50 ml-6">Sedan, Coupe, Compact</p>
                  </div>
                </label>
                <label class="cursor-pointer label border rounded-lg p-3 hover:border-primary transition-colors">
                  <div>
                    <input type="radio" name="vehicle[size]" value="suv_van" class="radio radio-primary radio-sm" />
                    <span class="ml-2 font-semibold">SUV / Van</span>
                    <p class="text-xs text-warning ml-6">+20% price</p>
                  </div>
                </label>
                <label class="cursor-pointer label border rounded-lg p-3 hover:border-primary transition-colors">
                  <div>
                    <input type="radio" name="vehicle[size]" value="pickup" class="radio radio-primary radio-sm" />
                    <span class="ml-2 font-semibold">Pickup</span>
                    <p class="text-xs text-warning ml-6">+50% price</p>
                  </div>
                </label>
              </div>
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

        <!-- Zone indicator -->
        <div :if={@selected_address && @selected_address.zone} class="alert alert-info mt-4">
          <span>
            Service Zone:
            <span class={["badge", MobileCarWash.Zones.badge_class(@selected_address.zone)]}>
              {MobileCarWash.Zones.label(@selected_address.zone)}
            </span>
          </span>
        </div>
        <div :if={@selected_address && is_nil(@selected_address.zone)} class="alert alert-warning mt-4">
          <span>This address may be outside our current service area. We'll confirm availability.</span>
        </div>

        <div :if={@selected_address} class="mt-4 text-right">
          <button class="btn btn-primary" phx-click="next_step">Continue</button>
        </div>
      </div>

      <div :if={@current_step == :photos}>
        <h2 class="text-2xl font-bold mb-6">Problem Area Photos</h2>
        <p class="text-base-content/60 mb-4">
          Have any scratches, stains, or areas that need extra attention?
          Upload photos so the technician knows where to focus. This step is optional.
        </p>

        <!-- Already uploaded photos -->
        <div :if={@uploaded_photos != []} class="flex gap-2 flex-wrap mb-4">
          <div :for={photo <- @uploaded_photos} class="relative">
            <img src={photo.file_path} class="w-24 h-24 object-cover rounded-lg shadow" />
            <p :if={photo.caption} class="text-xs text-center mt-1">{photo.caption}</p>
          </div>
        </div>

        <!-- Upload form -->
        <form phx-submit="save_problem_photos" phx-change="validate_photos" class="space-y-4">
          <div class="form-control">
            <.live_file_input upload={@uploads.problem_photo} class="file-input file-input-bordered w-full" />
          </div>

          <div class="flex gap-2 flex-wrap">
            <div :for={entry <- @uploads.problem_photo.entries} class="relative">
              <.live_img_preview entry={entry} class="w-24 h-24 object-cover rounded-lg" />
              <button type="button" class="btn btn-circle btn-xs btn-error absolute -top-2 -right-2"
                phx-click="cancel_photo_upload" phx-value-ref={entry.ref}>
                ×
              </button>
            </div>
          </div>

          <div class="form-control">
            <input type="text" name="caption" class="input input-bordered input-sm" placeholder="Describe the issue (optional)" />
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text text-xs">Car Part (Optional)</span></label>
            <select name="car_part" class="select select-bordered select-sm">
              <option value="">None selected</option>
              <option value="exterior">Exterior (body panels, hood, doors)</option>
              <option value="windows">Windows (windshield, side windows)</option>
              <option value="wheels">Wheels (tires, rims, wheel wells)</option>
              <option value="interior">Interior (dashboard, seats, carpets)</option>
              <option value="trunk">Trunk (boot area)</option>
              <option value="engine_bay">Engine Bay</option>
              <option value="undercarriage">Undercarriage (chassis, underside)</option>
              <option value="mirrors">Mirrors (side and rear view mirrors)</option>
              <option value="headlights_taillights">Headlights & Taillights</option>
              <option value="bumper">Bumper (front and rear)</option>
              <option value="roof">Roof Panel & Trim</option>
              <option value="sunroof">Sunroof</option>
            </select>
          </div>

          <button :if={@uploads.problem_photo.entries != []} type="submit" class="btn btn-warning btn-sm">
            Upload Photos
          </button>
        </form>

        <div class="mt-6 flex gap-4 justify-end">
          <button class="btn btn-ghost btn-sm" phx-click="next_step">
            Skip — No Photos
          </button>
          <button :if={@uploaded_photos != []} class="btn btn-primary" phx-click="next_step">
            Continue
          </button>
        </div>
      </div>

      <div :if={@current_step == :schedule}>
        <h2 class="text-2xl font-bold mb-6">Pick an Arrival Window</h2>
        <.block_window_picker
          date={@selected_date}
          blocks={@available_blocks}
          selected_block={@selected_block}
        />
        <div :if={@selected_block} class="mt-8 text-right">
          <button class="btn btn-primary" phx-click="next_step">Continue</button>
        </div>
      </div>

      <div :if={@current_step == :review}>
        <h2 class="text-2xl font-bold mb-6">Review Your Booking</h2>

        <div :if={@active_subscription} class="alert alert-success mb-6">
          <div>
            <p class="font-semibold">
              {@active_subscription.plan.name} Plan Applied
            </p>
            <p :if={@active_subscription.plan.basic_washes_per_month > 0} class="text-sm">
              {Map.get(@active_subscription.usage, :basic_washes_used, 0)}/{@active_subscription.plan.basic_washes_per_month} basic washes used this period
            </p>
            <p :if={@active_subscription.plan.deep_clean_discount_percent > 0} class="text-sm">
              {@active_subscription.plan.deep_clean_discount_percent}% off deep cleans
            </p>
          </div>
        </div>

        <!-- Loyalty punch card redemption -->
        <% loyalty_free = MobileCarWash.Loyalty.available_free_washes(@loyalty_card) %>
        <div :if={loyalty_free > 0 && !@active_subscription} class={["alert mb-4", @redeem_loyalty && "alert-success" || "alert-info"]}>
          <div class="flex items-center justify-between w-full flex-wrap gap-2">
            <div>
              <p class="font-semibold">
                {if @redeem_loyalty, do: "🎁 Free wash applied!", else: "🎁 You have #{loyalty_free} free wash#{if loyalty_free != 1, do: "es"} available!"}
              </p>
              <p class="text-sm opacity-75">
                {if @redeem_loyalty, do: "This booking is on us.", else: "Earned from your loyalty punch card."}
              </p>
            </div>
            <button class={["btn btn-sm", @redeem_loyalty && "btn-outline" || "btn-primary"]} phx-click="toggle_loyalty">
              {if @redeem_loyalty, do: "Remove", else: "Apply Free Wash"}
            </button>
          </div>
        </div>

        <!-- Referral code -->
        <div :if={!@redeem_loyalty && !@active_subscription} class="alert mb-4">
          <div :if={!@referral_code} class="w-full">
            <form phx-submit="apply_referral" class="flex items-center gap-2">
              <input
                type="text"
                name="code"
                class="input input-bordered input-sm flex-1"
                placeholder="Referral code"
                maxlength="8"
              />
              <button type="submit" class="btn btn-sm btn-outline">Apply</button>
            </form>
            <p :if={@referral_error} class="text-error text-sm mt-1">{@referral_error}</p>
          </div>
          <div :if={@referral_code} class="flex items-center justify-between w-full">
            <div>
              <p class="font-semibold text-success">$10 referral discount applied!</p>
              <p class="text-sm opacity-75">Code: {@referral_code}</p>
            </div>
            <button class="btn btn-sm btn-outline" phx-click="clear_referral">Remove</button>
          </div>
        </div>

        <% base_price = MobileCarWash.Billing.Pricing.calculate(@selected_service.base_price_cents, @selected_vehicle.size) %>
        <.booking_summary
          appointment={%{
            scheduled_at: @selected_slot,
            price_cents: base_price - @referral_discount,
            discount_cents: if(@redeem_loyalty, do: base_price, else: @referral_discount)
          }}
          service={@selected_service}
          vehicle={@selected_vehicle}
          address={@selected_address}
        />
        <div class="mt-8 flex gap-4 justify-end">
          <button class="btn btn-outline" phx-click="prev_step">Back</button>
          <button class="btn btn-primary btn-lg" phx-click="confirm_booking">
            {if @redeem_loyalty, do: "Confirm — Free Wash!", else: "Confirm Booking"}
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

  # === EVENT HANDLERS ===

  @impl true
  def handle_event("select_service", %{"slug" => slug}, socket) do
    service = Enum.find(socket.assigns.services, &(&1.slug == slug))
    {:noreply, assign(socket, selected_service: service)}
  end

  def handle_event("next_step", _params, socket) do
    context = build_context(socket.assigns)
    current = socket.assigns.current_step

    require Logger
    Logger.warning("NEXT_STEP: current=#{current}, context=#{inspect(Map.take(context, [:selected_service, :current_customer, :selected_vehicle, :selected_address, :selected_slot]), pretty: false)}")

    case StateMachine.transition(:forward, current, context) do
      {:ok, next_step} ->
        Logger.warning("NEXT_STEP: #{current} → #{next_step} ✓")

        socket =
          socket
          |> track_step_completion()
          |> assign(current_step: next_step, step_started_at: System.monotonic_time(:millisecond))
          |> load_step_data(next_step)
          |> persist_booking_state()

        {:noreply, socket}

      {:error, reason} ->
        Logger.warning("NEXT_STEP: #{current} BLOCKED: #{reason}")
        {:noreply, put_flash(socket, :error, "Cannot continue: #{reason}")}
    end
  end

  def handle_event("prev_step", _params, socket) do
    context = build_context(socket.assigns)

    case StateMachine.transition(:back, socket.assigns.current_step, context) do
      {:ok, prev_step} ->
        socket =
          socket
          |> assign(current_step: prev_step, step_started_at: System.monotonic_time(:millisecond))
          |> persist_booking_state()

        {:noreply, socket}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_event("guest_checkout", %{"guest" => guest_params}, socket) do
    alias MobileCarWash.Accounts.Customer

    require Ash.Query
    existing = Customer |> Ash.Query.filter(email == ^guest_params["email"]) |> Ash.read!(authorize?: false)

    result =
      case existing do
        [%{role: :guest} = customer] ->
          # Only allow re-use of existing guest accounts (no password set)
          {:ok, customer}

        [_registered_customer] ->
          # Email belongs to a registered account — don't silently adopt it
          {:error, "An account with this email already exists. Please sign in instead."}

        [] ->
          case Customer
               |> Ash.Changeset.for_create(:create_guest, %{
                 email: guest_params["email"],
                 name: guest_params["name"],
                 phone: guest_params["phone"]
               })
               |> Ash.create() do
            {:ok, customer} ->
              {:ok, customer}

            {:error, _} ->
              {:error, "Could not create guest account. Please check your email and try again."}
          end
      end

    case result do
      {:ok, customer} ->
        socket = assign(socket, current_customer: customer, guest_mode: true, guest_error: nil)
        context = build_context(socket.assigns)

        case StateMachine.transition(:forward, :auth, context) do
          {:ok, next_step} ->
            socket =
              socket
              |> assign(current_step: next_step, step_started_at: System.monotonic_time(:millisecond))
              |> load_step_data(next_step)
              |> persist_booking_state()

            {:noreply, socket}

          {:error, _} ->
            {:noreply, socket}
        end

      {:error, message} ->
        {:noreply, assign(socket, guest_error: message)}
    end
  end

  def handle_event("show_new_vehicle", _params, socket) do
    {:noreply, assign(socket, show_new_vehicle_form: true)}
  end

  def handle_event("show_new_address", _params, socket) do
    {:noreply, assign(socket, show_new_address_form: true)}
  end

  def handle_event("save_vehicle", %{"vehicle" => vehicle_params}, socket) do
    require Logger
    Logger.warning("SAVE_VEHICLE: current_step=#{socket.assigns.current_step}, customer=#{socket.assigns.current_customer && socket.assigns.current_customer.id}")
    customer = socket.assigns.current_customer

    allowed_vehicle_keys = ~w(make model year color size)
    attrs =
      vehicle_params
      |> Map.take(allowed_vehicle_keys)
      |> Map.new(fn {k, v} -> {String.to_existing_atom(k), v} end)
      |> Map.update(:year, nil, fn v -> if is_binary(v) and v != "", do: String.to_integer(v), else: nil end)

    case Vehicle
         |> Ash.Changeset.for_create(:create, attrs)
         |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
         |> Ash.create() do
      {:ok, vehicle} ->
        track_event(socket, "booking.vehicle_added", %{"vehicle_id" => vehicle.id, "is_new" => true})

        {:noreply,
         socket
         |> assign(
           selected_vehicle: vehicle,
           show_new_vehicle_form: false,
           existing_vehicles: socket.assigns.existing_vehicles ++ [vehicle]
         )
         |> persist_booking_state()}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not save vehicle. Please check your input.")}
    end
  end

  def handle_event("select_vehicle", %{"id" => id}, socket) do
    vehicle = Enum.find(socket.assigns.existing_vehicles, &(&1.id == id))
    track_event(socket, "booking.vehicle_added", %{"vehicle_id" => id, "is_new" => false})
    {:noreply, socket |> assign(selected_vehicle: vehicle) |> persist_booking_state()}
  end

  def handle_event("save_address", %{"address" => address_params}, socket) do
    customer = socket.assigns.current_customer

    allowed_address_keys = ~w(street city state zip)
    attrs =
      address_params
      |> Map.take(allowed_address_keys)
      |> Map.new(fn {k, v} -> {String.to_existing_atom(k), v} end)

    case Address
         |> Ash.Changeset.for_create(:create, attrs)
         |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
         |> Ash.create() do
      {:ok, address} ->
        track_event(socket, "booking.address_added", %{"address_id" => address.id, "is_new" => true})

        {:noreply,
         socket
         |> assign(
           selected_address: address,
           show_new_address_form: false,
           existing_addresses: socket.assigns.existing_addresses ++ [address]
         )
         |> persist_booking_state()}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not save address. Please check your input.")}
    end
  end

  def handle_event("select_address", %{"id" => id}, socket) do
    address = Enum.find(socket.assigns.existing_addresses, &(&1.id == id))
    track_event(socket, "booking.address_added", %{"address_id" => id, "is_new" => false})
    {:noreply, socket |> assign(selected_address: address) |> persist_booking_state()}
  end

  def handle_event("validate_photos", _params, socket), do: {:noreply, socket}

  def handle_event("cancel_photo_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :problem_photo, ref)}
  end

  def handle_event("save_problem_photos", params, socket) do
    # Photos are saved temporarily — they'll be linked to the appointment after booking
    # For now, store them in socket assigns so they persist through the flow
    caption = params["caption"]
    car_part_str = params["car_part"]
    car_part = if car_part_str && car_part_str != "", do: String.to_atom(car_part_str), else: nil

    uploaded =
      consume_uploaded_entries(socket, :problem_photo, fn %{path: path}, entry ->
        # Save to storage backend (local or S3)
        photo_opts = [
          uploaded_by: :customer,
          caption: caption
        ]

        photo_opts = if car_part, do: photo_opts ++ [car_part: car_part], else: photo_opts

        {:ok, %{file_path: url}} =
          MobileCarWash.Operations.PhotoUpload.save_file(
            "pending_#{socket.assigns.booking_session_id}",
            path,
            entry.client_name,
            :problem_area,
            photo_opts
          )

        {:ok, %{file_path: url, caption: caption, original_filename: entry.client_name, car_part: car_part}}
      end)

    # Apply presigned URLs so thumbnails display correctly in S3 mode
    uploaded = Enum.map(uploaded, fn photo ->
      Map.put(photo, :file_path, MobileCarWash.Operations.PhotoUpload.url_for(photo))
    end)

    {:noreply,
     socket
     |> assign(uploaded_photos: socket.assigns.uploaded_photos ++ uploaded)
     |> put_flash(:info, "Photos uploaded")}
  end

  def handle_event("select_date", %{"date" => date_str}, socket) do
    case Date.from_iso8601(date_str) do
      {:ok, date} ->
        service = socket.assigns.selected_service
        blocks = BlockAvailability.open_blocks_for_service_range(service.id, date, date)

        {:noreply,
         assign(socket,
           selected_date: date_str,
           available_blocks: blocks,
           selected_block: nil,
           selected_slot: nil
         )}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("select_block", %{"id" => block_id}, socket) do
    case Enum.find(socket.assigns.available_blocks, &(&1.id == block_id)) do
      nil ->
        {:noreply, socket}

      block ->
        track_event(socket, "booking.block_selected", %{
          "block_id" => block.id,
          "starts_at" => DateTime.to_iso8601(block.starts_at),
          "day_of_week" => Date.day_of_week(DateTime.to_date(block.starts_at))
        })

        {:noreply,
         socket
         |> assign(selected_block: block, selected_slot: block.starts_at)
         |> persist_booking_state()}
    end
  end

  def handle_event("toggle_loyalty", _params, socket) do
    {:noreply, assign(socket, redeem_loyalty: !socket.assigns.redeem_loyalty)}
  end

  def handle_event("apply_referral", %{"code" => code}, socket) do
    customer = socket.assigns.current_customer

    if customer do
      case MobileCarWash.Scheduling.Booking.validate_referral_code(String.trim(String.upcase(code)), customer.id) do
        {:ok, _referrer} ->
          {:noreply, assign(socket, referral_code: String.trim(String.upcase(code)), referral_discount: 1000, referral_error: nil)}

        {:error, :self_referral} ->
          {:noreply, assign(socket, referral_code: nil, referral_discount: 0, referral_error: "You can't use your own referral code")}

        {:error, :not_found} ->
          {:noreply, assign(socket, referral_code: nil, referral_discount: 0, referral_error: "Invalid referral code")}
      end
    else
      {:noreply, assign(socket, referral_error: "Sign in to use a referral code")}
    end
  end

  def handle_event("clear_referral", _params, socket) do
    {:noreply, assign(socket, referral_code: nil, referral_discount: 0, referral_error: nil)}
  end

  def handle_event("confirm_booking", _params, socket) do
    %{
      current_customer: customer,
      selected_service: service,
      selected_vehicle: vehicle,
      selected_address: address,
      selected_block: block
    } = socket.assigns

    booking_params = %{
      customer_id: customer.id,
      service_type_id: service.id,
      vehicle_id: vehicle.id,
      address_id: address.id,
      appointment_block_id: block.id,
      subscription_id: socket.assigns.active_subscription && socket.assigns.active_subscription.id,
      loyalty_redeem: socket.assigns.redeem_loyalty,
      referral_code: socket.assigns.referral_code
    }

    case Booking.create_booking(booking_params) do
      {:ok, %{appointment: appointment, checkout_url: checkout_url}} when not is_nil(checkout_url) ->
        elapsed = System.monotonic_time(:millisecond) - socket.assigns.flow_started_at

        track_event(socket, "booking.payment_started", %{
          "appointment_id" => appointment.id,
          "service_slug" => service.slug,
          "price_cents" => appointment.price_cents,
          "total_time_ms" => elapsed
        })

        # Clean up session cache after successful booking
        SessionCache.delete(socket.assigns.booking_session_id)

        {:noreply, redirect(socket, external: checkout_url)}

      {:ok, %{appointment: appointment, checkout_url: nil}} ->
        elapsed = System.monotonic_time(:millisecond) - socket.assigns.flow_started_at

        track_event(socket, "booking.completed", %{
          "appointment_id" => appointment.id,
          "service_slug" => service.slug,
          "price_cents" => appointment.price_cents,
          "discount_cents" => appointment.discount_cents,
          "total_time_ms" => elapsed,
          "payment_method" => "subscription"
        })

        SessionCache.delete(socket.assigns.booking_session_id)

        {:noreply,
         socket
         |> assign(appointment: appointment, current_step: :confirmed)
         |> put_flash(:info, "Booking confirmed!")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Booking failed: #{inspect(reason)}. Please try again.")}
    end
  end

  # === PRIVATE HELPERS ===

  defp build_context(assigns) do
    %{
      selected_service: assigns[:selected_service],
      current_customer: assigns[:current_customer],
      guest_mode: assigns[:guest_mode] || false,
      selected_vehicle: assigns[:selected_vehicle],
      selected_address: assigns[:selected_address],
      selected_slot: assigns[:selected_slot],
      appointment: assigns[:appointment]
    }
  end

  defp persist_booking_state(socket) do
    SessionCache.put(socket.assigns.booking_session_id, %{
      step: socket.assigns.current_step,
      guest_mode: socket.assigns.guest_mode,
      customer_id: socket.assigns.current_customer && socket.assigns.current_customer.id,
      service_id: socket.assigns.selected_service && socket.assigns.selected_service.id,
      vehicle_id: socket.assigns.selected_vehicle && socket.assigns.selected_vehicle.id,
      address_id: socket.assigns.selected_address && socket.assigns.selected_address.id,
      block_id: socket.assigns.selected_block && socket.assigns.selected_block.id
    })

    socket
  end

  defp derive_session_id(session) do
    # Use the CSRF token from the Plug session as a stable identifier
    # This survives WebSocket reconnects
    case session do
      %{"_csrf_token" => token} -> "booking_#{token}"
      _ -> "booking_#{Ash.UUID.generate()}"
    end
  end

  defp restore_from_cache(cached) do
    # Load actual records from DB by ID
    service = cached[:service_id] && safe_get(ServiceType, cached[:service_id])
    customer = cached[:customer_id] && safe_get(MobileCarWash.Accounts.Customer, cached[:customer_id])
    vehicle = cached[:vehicle_id] && safe_get(Vehicle, cached[:vehicle_id])
    address = cached[:address_id] && safe_get(Address, cached[:address_id])

    block = cached[:block_id] && safe_get_block(cached[:block_id])

    assigns = %{
      selected_service: service,
      current_customer: customer,
      selected_vehicle: vehicle,
      selected_address: address,
      selected_block: block,
      selected_slot: block && block.starts_at,
      guest_mode: cached[:guest_mode] || false
    }

    {cached[:step] || :select_service, assigns}
  end

  defp safe_get(resource, id) do
    case Ash.get(resource, id) do
      {:ok, record} -> record
      _ -> nil
    end
  end

  defp safe_get_block(id) do
    case Ash.get(MobileCarWash.Scheduling.AppointmentBlock, id, load: [:appointment_count]) do
      {:ok, record} -> record
      _ -> nil
    end
  end

  defp load_step_data(socket, :vehicle) do
    customer = socket.assigns.current_customer

    if customer && !socket.assigns.guest_mode do
      vehicles =
        Vehicle
        |> Ash.Query.filter(customer_id == ^customer.id)
        |> Ash.read!()

      assign(socket, existing_vehicles: vehicles, show_new_vehicle_form: vehicles == [])
    else
      assign(socket, existing_vehicles: [], show_new_vehicle_form: true)
    end
  end

  defp load_step_data(socket, :address) do
    customer = socket.assigns.current_customer

    if customer && !socket.assigns.guest_mode do
      addresses =
        Address
        |> Ash.Query.filter(customer_id == ^customer.id)
        |> Ash.read!()

      assign(socket, existing_addresses: addresses, show_new_address_form: addresses == [])
    else
      assign(socket, existing_addresses: [], show_new_address_form: true)
    end
  end

  defp load_step_data(socket, :schedule) do
    date = socket.assigns.selected_date
    service = socket.assigns.selected_service

    case Date.from_iso8601(date) do
      {:ok, parsed_date} ->
        blocks = BlockAvailability.open_blocks_for_service_range(service.id, parsed_date, parsed_date)
        assign(socket, available_blocks: blocks)

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

  defp load_loyalty_card(nil), do: nil
  defp load_loyalty_card(customer) do
    case MobileCarWash.Loyalty.get_or_create_card(customer.id) do
      {:ok, card} -> card
      _ -> nil
    end
  end

  defp load_active_subscription(nil), do: nil

  defp load_active_subscription(customer) do
    Subscription
    |> Ash.Query.filter(customer_id == ^customer.id and status == :active)
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.read!()
    |> case do
      [sub | _] ->
        plan = Ash.get!(MobileCarWash.Billing.SubscriptionPlan, sub.plan_id)
        today = Date.utc_today()

        usage =
          SubscriptionUsage
          |> Ash.Query.filter(subscription_id == ^sub.id and period_start <= ^today and period_end >= ^today)
          |> Ash.read!()
          |> List.first() || %{basic_washes_used: 0, deep_cleans_used: 0}

        Map.put(sub, :plan, plan) |> Map.put(:usage, usage)

      [] ->
        nil
    end
  end
end
