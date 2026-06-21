defmodule MobileCarWashWeb.BookingLive do
  use MobileCarWashWeb, :live_view

  import MobileCarWashWeb.BookingComponents
  import MobileCarWashWeb.Live.Helpers.EventTracker

  alias MobileCarWash.Scheduling.{ServiceType, BlockAvailability, Booking}
  alias MobileCarWash.Fleet.{Address, GeocoderClient, Vehicle}
  alias MobileCarWash.Booking.{BookingSections, SessionCache}
  alias MobileCarWash.Billing.{Subscription, SubscriptionUsage, Pricing}
  alias MobileCarWash.Analytics
  alias MobileCarWash.Vehicles.NhtsaClient

  require Ash.Query

  # --- Mount: restore state from cache or start fresh ---

  @impl true
  def mount(_params, session, socket) do
    services =
      ServiceType
      |> Ash.Query.filter(active == true)
      |> Ash.read!()
      |> Enum.sort_by(& &1.base_price_cents)

    add_ons =
      MobileCarWash.Scheduling.AddOn
      |> Ash.Query.filter(active == true)
      |> Ash.read!()
      |> Enum.sort_by(& &1.sort_order)

    booking_session_id = derive_session_id(session)

    # Restore from cache if reconnecting
    restored_assigns =
      case SessionCache.get(booking_session_id) do
        nil -> %{}
        cached -> restore_from_cache(cached)
      end

    # Build context — prefer session customer, fall back to cached customer (for guests)
    customer = socket.assigns[:current_customer] || restored_assigns[:current_customer]

    socket =
      socket
      |> assign_session_id()
      |> assign(
        page_title: "Book a Wash",
        meta_description:
          "Book a mobile car wash or detail online. Choose your service, pick a time, and we come to you. Same-day availability. Veteran-owned.",
        meta_keywords:
          "book mobile car wash, schedule car detail, online car wash booking, same day car wash, mobile detailing appointment",
        canonical_path: "/book",
        services: services,
        available_add_ons: add_ons,
        selected_add_ons: restored_assigns[:selected_add_ons] || [],
        booking_session_id: booking_session_id,
        # Cookie banner detection — used by the review section's mobile sticky CTA
        # to avoid being hidden behind the cookie banner on first-visit mobile users.
        current_consent: Analytics.consent_for_session(Map.get(session, "session_id")),
        # Accumulated booking data (override on_mount's nil customer with cached guest)
        current_customer: customer,
        selected_service: restored_assigns[:selected_service],
        selected_vehicle: restored_assigns[:selected_vehicle],
        selected_address: restored_assigns[:selected_address],
        selected_slot: restored_assigns[:selected_slot],
        selected_block: restored_assigns[:selected_block],
        appointment: nil,
        guest_mode: restored_assigns[:guest_mode] || false,
        guest_error: nil,
        # Guest contact form (shown at Review & Pay for non-signed-in users)
        guest_form: %{"name" => "", "email" => "", "phone" => ""},
        # UI state
        selected_date: Date.utc_today() |> Date.add(1) |> Date.to_string(),
        available_blocks: [],
        existing_vehicles: [],
        existing_addresses: [],
        show_new_vehicle_form: false,
        show_new_address_form: false,
        address_query: "",
        address_suggestions: [],
        loading_suggestions: false,
        # NHTSA dropdown data
        vehicle_makes: NhtsaClient.popular_makes(),
        vehicle_models: [],
        loading_models: false,
        vin_error: nil,
        # Forms
        vehicle_form: %{
          "make" => "",
          "year" => "",
          "model" => "",
          "color" => "",
          "size" => "car",
          "vin" => "",
          "body_class" => ""
        },
        address_form: nil,
        # Subscription
        active_subscription: load_active_subscription(customer),
        # Loyalty punch card
        loyalty_card: load_loyalty_card(customer),
        redeem_loyalty: false,
        # Referral
        referral_code: nil,
        referral_discount: 0,
        referral_error: nil,
        # Price hero
        receipt_expanded: false,
        price_breakdown: nil,
        # Timing
        flow_started_at: System.monotonic_time(:millisecond)
      )
      # Compute the price hero from any restored service/vehicle so a resumed
      # session never renders with a nil breakdown (which would crash the
      # review summary's total access).
      |> assign_price_breakdown()
      # Eager-load every section's data — the whole page renders at once.
      |> load_step_data(:vehicle)
      |> load_step_data(:address)
      |> load_step_data(:schedule)

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

  def handle_info(:add_ons_updated, socket) do
    add_ons =
      MobileCarWash.Scheduling.AddOn
      |> Ash.Query.filter(active == true)
      |> Ash.read!()
      |> Enum.sort_by(& &1.sort_order)

    {:noreply, assign(socket, available_add_ons: add_ons)}
  end

  # --- Handle Params: pre-select a service from the URL (?service=slug) ---

  @impl true
  def handle_params(params, _uri, socket) do
    socket =
      case params do
        %{"service" => slug} when is_nil(socket.assigns.selected_service) ->
          case Enum.find(socket.assigns.services, &(&1.slug == slug)) do
            nil -> socket
            service -> socket |> assign(selected_service: service) |> assign_price_breakdown()
          end

        _ ->
          socket
      end

    if connected?(socket) do
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
      <MobileCarWashWeb.PriceHeader.price_header
        breakdown={@price_breakdown}
        expanded={@receipt_expanded}
      />

      <%!-- Top sign-in prompt (optional; returning customers) --%>
      <div
        :if={is_nil(@current_customer)}
        class="my-4 flex items-center justify-between gap-3 rounded-box bg-base-200 px-4 py-3"
      >
        <span class="text-sm text-base-content/80">Have an account?</span>
        <.link href={~p"/book/sign-in"} class="btn btn-ghost btn-sm">Sign in</.link>
      </div>
      <div
        :if={@current_customer}
        class="my-4 rounded-box bg-success/10 border border-success/30 px-4 py-2 text-sm text-success"
      >
        Signed in as {@current_customer.name}
      </div>

      <.booking_section
        id="section-service"
        index={1}
        title="Service"
        status={BookingSections.status(:service, build_context(assigns))}
      >
        <p class="text-sm text-base-content/60 mb-4">Two tiers. No hidden fees.</p>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <.service_card
            :for={service <- @services}
            service={service}
            selected={@selected_service && @selected_service.id == service.id}
          />
        </div>
      </.booking_section>

      <.booking_section
        id="section-add_ons"
        index={2}
        title="Add-ons"
        status={BookingSections.status(:add_ons, build_context(assigns))}
      >
        <p class="text-sm text-base-content/70 mb-4">Optional add-ons — tap to include.</p>

        <div class="space-y-2">
          <button
            :for={addon <- @available_add_ons}
            type="button"
            phx-click="toggle_add_on"
            phx-value-id={addon.id}
            class={[
              "w-full flex items-center justify-between rounded-box border p-4 text-left transition",
              Enum.any?(@selected_add_ons, &(&1.id == addon.id)) && "border-success bg-success/10",
              !Enum.any?(@selected_add_ons, &(&1.id == addon.id)) && "border-base-300"
            ]}
          >
            <span class="flex items-center gap-3">
              <.icon name="hero-sparkles" class="size-5 text-base-content/60" />
              <span>
                <span class="block font-semibold text-base-content">{addon.name}</span>
                <span :if={addon.description} class="block text-xs text-base-content/60">
                  {addon.description}
                </span>
              </span>
            </span>
            <span class="font-semibold text-base-content">
              +{Pricing.format_cents(addon.price_cents)}
            </span>
          </button>
        </div>
      </.booking_section>

      <.booking_section
        id="section-vehicle"
        index={3}
        title="Your vehicle"
        status={BookingSections.status(:vehicle, build_context(assigns))}
      >
        <p class="text-sm text-base-content/60 mb-4">Pick a saved vehicle, or add a new one.</p>

        <%!-- Saved vehicles list --%>
        <div :if={@existing_vehicles != []} class="space-y-3 mb-6">
          <.saved_record_card
            :for={vehicle <- @existing_vehicles}
            title={"#{vehicle.year} #{vehicle.make} #{vehicle.model}"}
            subtitle={"#{vehicle.color} · #{vehicle.size}"}
            selected={@selected_vehicle && @selected_vehicle.id == vehicle.id}
            phx-click="select_vehicle"
            phx-value-id={vehicle.id}
          />
        </div>

        <%!-- "Add New" toggle button (only when ≥1 saved records) --%>
        <button
          :if={@existing_vehicles != [] and !@show_new_vehicle_form}
          class="btn btn-outline btn-sm mb-6"
          phx-click="show_new_vehicle"
        >
          + Add new vehicle
        </button>

        <%!-- VIN autofill shortcut --%>
        <form
          :if={(@existing_vehicles == [] and is_nil(@selected_vehicle)) or @show_new_vehicle_form}
          phx-submit="decode_vin"
          class="bg-base-200 border border-base-300 rounded-box p-4 space-y-2 mb-4"
        >
          <label class="text-sm font-semibold text-base-content block">⚡ Autofill from VIN</label>
          <div class="flex gap-2">
            <input
              type="text"
              name="vin"
              value={@vehicle_form["vin"]}
              placeholder="1HGCM82633A004352"
              maxlength="17"
              class="input input-bordered flex-1 uppercase"
              autocomplete="off"
            />
            <button type="submit" class="btn btn-secondary" phx-disable-with="Decoding…">
              Autofill
            </button>
          </div>
          <p :if={@vin_error} class="text-xs text-error">{@vin_error}</p>
        </form>

        <%!-- Manual dropdown form --%>
        <form
          :if={(@existing_vehicles == [] and is_nil(@selected_vehicle)) or @show_new_vehicle_form}
          phx-change="vehicle_form_change"
          phx-submit="save_vehicle"
          class="bg-base-100 border border-base-300 rounded-box p-5 space-y-4 mb-6"
        >
          <div :if={@existing_vehicles == []} class="text-sm font-semibold text-base-content">
            Add your vehicle
          </div>

          <div class="grid grid-cols-1 sm:grid-cols-3 gap-3">
            <label class="form-control w-full">
              <span class="label-text font-semibold mb-1">Make</span>
              <select name="vehicle[make]" class="select select-bordered w-full" required>
                <option value="" disabled selected={@vehicle_form["make"] == ""}>Select make</option>
                <option :for={mk <- @vehicle_makes} value={mk} selected={@vehicle_form["make"] == mk}>
                  {mk}
                </option>
              </select>
            </label>

            <label class="form-control w-full">
              <span class="label-text font-semibold mb-1">Year</span>
              <select name="vehicle[year]" class="select select-bordered w-full" required>
                <option value="" disabled selected={@vehicle_form["year"] == ""}>Select year</option>
                <option
                  :for={yr <- vehicle_years()}
                  value={yr}
                  selected={to_string(@vehicle_form["year"]) == to_string(yr)}
                >
                  {yr}
                </option>
              </select>
            </label>

            <label class="form-control w-full">
              <span class="label-text font-semibold mb-1">Model</span>
              <select
                name="vehicle[model]"
                class="select select-bordered w-full"
                required
                disabled={@loading_models or @vehicle_models == []}
              >
                <option value="" disabled selected={@vehicle_form["model"] == ""}>
                  {cond do
                    @loading_models -> "Loading models…"
                    @vehicle_models == [] -> "Pick make & year first"
                    true -> "Select model"
                  end}
                </option>
                <option
                  :for={md <- @vehicle_models}
                  value={md.name}
                  selected={@vehicle_form["model"] == md.name}
                >
                  {md.name}
                </option>
              </select>
              <span
                :if={@loading_models}
                class="text-xs text-base-content/60 mt-1 flex items-center gap-1"
              >
                <span class="loading loading-spinner loading-xs"></span> Loading models…
              </span>
            </label>
          </div>

          <div>
            <label class="text-sm font-semibold text-base-content mb-2 block">Color</label>
            <div class="flex flex-wrap gap-3">
              <label :for={{name, hex} <- vehicle_colors()} class="cursor-pointer" title={name}>
                <input
                  type="radio"
                  name="vehicle[color]"
                  value={name}
                  class="sr-only peer"
                  checked={@vehicle_form["color"] == name}
                />
                <span
                  class="block border-2 border-base-300 peer-checked:border-cyan-500 peer-checked:ring-2 peer-checked:ring-cyan-500 transition"
                  style={"background-color: #{hex}; width: 2rem; height: 2rem; border-radius: 9999px;"}
                >
                </span>
              </label>
            </div>
          </div>

          <div>
            <label class="text-sm font-semibold text-base-content mb-2 block">Vehicle type</label>
            <div
              :if={@vehicle_form["model"] != "" or @vehicle_form["vin"] != ""}
              class="inline-flex items-center gap-2 rounded-lg border border-base-300 bg-base-200 px-3 py-2"
              role="status"
              aria-label={"Detected vehicle type: #{size_badge(@vehicle_form["size"]).label} #{size_badge(@vehicle_form["size"]).modifier}"}
            >
              <span class="text-lg">{size_badge(@vehicle_form["size"]).icon}</span>
              <span class="text-sm font-semibold">{size_badge(@vehicle_form["size"]).label}</span>
              <span class="text-xs text-warning">{size_badge(@vehicle_form["size"]).modifier}</span>
              <span class="text-xs text-base-content/50">· auto-detected</span>
            </div>
            <p
              :if={@vehicle_form["model"] == "" and @vehicle_form["vin"] == ""}
              class="text-sm text-base-content/50"
            >
              Pick your model and we'll detect the type.
            </p>
          </div>

          <input type="hidden" name="vehicle[size]" value={@vehicle_form["size"]} />
          <input type="hidden" name="vehicle[vin]" value={@vehicle_form["vin"]} />
          <input type="hidden" name="vehicle[body_class]" value={@vehicle_form["body_class"]} />

          <button type="submit" class="btn btn-primary w-full">Save vehicle</button>
        </form>

        <div
          :if={@selected_vehicle && @existing_vehicles == [] && !@show_new_vehicle_form}
          class="flex items-center justify-between rounded-box border border-base-300 bg-base-100 p-4"
        >
          <div class="text-sm font-semibold">
            {@selected_vehicle.year} {@selected_vehicle.make} {@selected_vehicle.model}
          </div>
          <button type="button" class="btn btn-ghost btn-sm" phx-click="show_new_vehicle">
            Change
          </button>
        </div>
      </.booking_section>

      <.booking_section
        id="section-address"
        index={4}
        title="Service location"
        status={BookingSections.status(:address, build_context(assigns))}
      >
        <p class="text-sm text-base-content/60 mb-4">
          Start typing your address and pick a match, or enter it manually.
        </p>

        <%!-- Saved addresses (signed-in customers) --%>
        <div :if={@existing_addresses != []} class="space-y-3 mb-6">
          <.saved_record_card
            :for={addr <- @existing_addresses}
            title={addr.street}
            subtitle={"#{addr.city}, #{addr.state} #{addr.zip}"}
            selected={@selected_address && @selected_address.id == addr.id}
            phx-click="select_address"
            phx-value-id={addr.id}
          />
        </div>

        <%!-- Address typeahead --%>
        <form phx-change="address_search" autocomplete="off" class="mb-2">
          <.input
            name="q"
            type="text"
            value={@address_query}
            label="Search address"
            placeholder="123 Main St, San Antonio"
            phx-debounce="250"
          />
        </form>

        <div :if={@loading_suggestions} class="text-xs text-base-content/50 mb-2">
          Searching…
        </div>

        <ul
          :if={@address_suggestions != []}
          class="menu bg-base-100 border border-base-300 rounded-box mb-4 p-1 w-full"
        >
          <li :for={{s, i} <- Enum.with_index(@address_suggestions)}>
            <button
              type="button"
              phx-click="select_suggestion"
              phx-value-index={i}
              class="text-left"
            >
              {s.label}
            </button>
          </li>
        </ul>

        <%!-- Manual entry fallback --%>
        <details class="mb-4">
          <summary class="text-sm text-primary cursor-pointer">Enter address manually</summary>
          <form
            phx-submit="save_address"
            class="bg-base-100 border border-base-300 rounded-box p-5 space-y-3 mt-3"
          >
            <.input
              name="address[street]"
              type="text"
              label="Street address"
              placeholder="123 Main St"
              required
            />
            <div class="grid grid-cols-1 sm:grid-cols-3 gap-3">
              <.input
                name="address[city]"
                type="text"
                label="City"
                placeholder="San Antonio"
                required
              />
              <.input name="address[state]" type="text" label="State" value="TX" required />
              <.input name="address[zip]" type="text" label="ZIP" placeholder="78261" required />
            </div>
            <button type="submit" class="btn btn-primary w-full">Save address</button>
          </form>
        </details>

        <%!-- Selected address summary --%>
        <div
          :if={@selected_address}
          class="flex items-center justify-between rounded-box border border-base-300 bg-base-100 p-4 mb-4"
        >
          <div class="text-sm font-semibold">
            {@selected_address.street}, {@selected_address.city} {@selected_address.state} {@selected_address.zip}
          </div>
        </div>

        <%!-- Confirmation map (only once we have coordinates) --%>
        <div
          :if={@selected_address && @selected_address.latitude && @selected_address.longitude}
          id="address-map"
          phx-hook="AddressMap"
          phx-update="ignore"
          data-lat={@selected_address.latitude}
          data-lng={@selected_address.longitude}
          class="h-56 w-full rounded-box border border-base-300 mb-4 z-0"
        >
        </div>

        <%!-- Zone banner --%>
        <div
          :if={@selected_address && @selected_address.zone}
          class="bg-success/10 border border-success/30 rounded-lg p-3 mb-4 text-sm text-success"
        >
          ✓ In service area · <strong>{MobileCarWash.Zones.label(@selected_address.zone)}</strong>
        </div>

        <div
          :if={@selected_address && is_nil(@selected_address.zone)}
          class="bg-warning/10 border border-warning/30 rounded-lg p-3 mb-4 text-sm text-warning"
        >
          ⚠ Outside our service area — we'll confirm or refund.
        </div>
      </.booking_section>

      <.booking_section
        id="section-schedule"
        index={5}
        title="Pick a time"
        status={BookingSections.status(:schedule, build_context(assigns))}
      >
        <p class="text-sm text-base-content/60 mb-4">
          We'll confirm your exact arrival time by midnight the day before.
        </p>

        <.block_window_picker
          date={@selected_date}
          blocks={@available_blocks}
          selected_block={@selected_block}
        />
      </.booking_section>

      <.booking_section
        id="section-review"
        index={6}
        title="Review & Pay"
        status={BookingSections.status(:review, build_context(assigns))}
      >
        <%!-- Subscription banner --%>
        <div
          :if={@active_subscription}
          class="bg-success/10 border border-success/30 rounded-box p-4 mb-4"
        >
          <div class="text-sm font-semibold text-success">
            {@active_subscription.plan.name} plan applied
          </div>
          <div
            :if={@active_subscription.plan.basic_washes_per_month > 0}
            class="text-xs text-success/80 mt-1"
          >
            {Map.get(@active_subscription.usage, :basic_washes_used, 0)}/{@active_subscription.plan.basic_washes_per_month} basic washes used this period
          </div>
          <div
            :if={@active_subscription.plan.deep_clean_discount_percent > 0}
            class="text-xs text-success/80 mt-1"
          >
            {@active_subscription.plan.deep_clean_discount_percent}% off deep cleans
          </div>
        </div>

        <%!-- Loyalty (with toggle) --%>
        <% loyalty_free = MobileCarWash.Loyalty.available_free_washes(@loyalty_card) %>
        <div
          :if={loyalty_free > 0 && !@active_subscription}
          class={[
            "rounded-box p-4 mb-4",
            if(@redeem_loyalty,
              do: "bg-success/10 border border-success/30",
              else: "bg-info/10 border border-info/30"
            )
          ]}
        >
          <div class="flex items-center justify-between gap-3 flex-wrap">
            <div>
              <div class={[
                "text-sm font-semibold",
                if(@redeem_loyalty, do: "text-success", else: "text-info")
              ]}>
                {if @redeem_loyalty,
                  do: "🎁 Free wash applied!",
                  else:
                    "🎁 You have #{loyalty_free} free wash#{if loyalty_free != 1, do: "es"} available"}
              </div>
              <div class="text-xs text-base-content/60 mt-0.5">
                {if @redeem_loyalty,
                  do: "This booking is on us.",
                  else: "Earned from your loyalty punch card."}
              </div>
            </div>
            <button
              class={["btn btn-sm", if(@redeem_loyalty, do: "btn-outline", else: "btn-primary")]}
              phx-click="toggle_loyalty"
            >
              {if @redeem_loyalty, do: "Remove", else: "Apply free wash"}
            </button>
          </div>
        </div>

        <%!-- Referral --%>
        <div
          :if={!@redeem_loyalty && !@active_subscription}
          class="bg-base-100 border border-base-300 rounded-box p-4 mb-4"
        >
          <div :if={!@referral_code}>
            <form phx-submit="apply_referral" class="flex items-center gap-2">
              <input
                type="text"
                name="code"
                class="input input-bordered input-sm flex-1 h-10"
                placeholder="Referral code"
                maxlength="8"
              />
              <button type="submit" class="btn btn-sm btn-outline">Apply</button>
            </form>
            <p :if={@referral_error} class="text-error text-xs mt-2">{@referral_error}</p>
          </div>
          <div :if={@referral_code} class="flex items-center justify-between gap-3">
            <div>
              <div class="text-sm font-semibold text-success">$10 referral discount applied</div>
              <div class="text-xs text-base-content/60 mt-0.5">Code: {@referral_code}</div>
            </div>
            <button class="btn btn-sm btn-outline" phx-click="clear_referral">Remove</button>
          </div>
        </div>

        <%!-- Booking summary — only once every required selection is present --%>
        <.booking_summary
          :if={@selected_service && @selected_vehicle && @selected_address && @selected_slot}
          appointment={
            %{
              scheduled_at: @selected_slot,
              price_cents: @price_breakdown.total_cents,
              discount_cents: @price_breakdown.discount_cents
            }
          }
          service={@selected_service}
          vehicle={@selected_vehicle}
          address={@selected_address}
        />

        <%!-- Guest contact info — collected here, the customer is created at Pay --%>
        <div :if={is_nil(@current_customer)} class="mt-4 space-y-3 border-t border-base-300 pt-4">
          <h3 class="text-sm font-semibold text-base-content">Your contact info</h3>
          <p :if={@guest_error} class="text-sm text-error">{@guest_error}</p>
          <form phx-change="guest_form_change" id="guest-contact" class="space-y-3">
            <.input name="guest[name]" type="text" label="Name" value={@guest_form["name"]} required />
            <.input
              name="guest[email]"
              type="email"
              label="Email"
              value={@guest_form["email"]}
              required
            />
            <.input name="guest[phone]" type="tel" label="Phone" value={@guest_form["phone"]} />
          </form>
        </div>

        <button
          class="btn btn-primary w-full mt-4"
          phx-click="confirm_booking"
          disabled={not BookingSections.payable?(build_context(assigns))}
        >
          {cond do
            @current_customer && @price_breakdown ->
              "Pay #{Pricing.format_cents(@price_breakdown.total_cents)}"

            @current_customer ->
              "Pay"

            true ->
              "Continue to payment"
          end}
        </button>
      </.booking_section>
    </div>
    """
  end

  # === EVENT HANDLERS ===

  @impl true
  def handle_event("select_service", %{"slug" => slug}, socket) do
    prev_ctx = build_context(socket.assigns)
    service = Enum.find(socket.assigns.services, &(&1.slug == slug))

    socket =
      socket
      |> assign(selected_service: service)
      |> assign_price_breakdown()
      |> persist_booking_state()
      |> maybe_scroll(prev_ctx)

    {:noreply, socket}
  end

  def handle_event("toggle_add_on", %{"id" => id}, socket) do
    add_on = Enum.find(socket.assigns.available_add_ons, &(&1.id == id))

    if is_nil(add_on) do
      {:noreply, socket}
    else
      selected =
        if Enum.any?(socket.assigns.selected_add_ons, &(&1.id == id)) do
          Enum.reject(socket.assigns.selected_add_ons, &(&1.id == id))
        else
          socket.assigns.selected_add_ons ++ [add_on]
        end

      socket =
        socket
        |> assign(selected_add_ons: selected)
        |> assign_price_breakdown()
        |> persist_booking_state()

      {:noreply, socket}
    end
  end

  def handle_event("guest_form_change", %{"guest" => params}, socket) do
    form = Map.merge(socket.assigns.guest_form, Map.take(params, ~w(name email phone)))
    {:noreply, assign(socket, guest_form: form)}
  end

  def handle_event("show_new_vehicle", _params, socket) do
    {:noreply, assign(socket, show_new_vehicle_form: true)}
  end

  def handle_event("show_new_address", _params, socket) do
    {:noreply, assign(socket, show_new_address_form: true)}
  end

  def handle_event("vehicle_form_change", %{"vehicle" => params}, socket) do
    prev = socket.assigns.vehicle_form
    incoming = Map.take(params, ~w(make year model color))
    form = Map.merge(prev, incoming)

    make_year_changed? = {form["make"], form["year"]} != {prev["make"], prev["year"]}

    cond do
      # Make+year both chosen and changed → fetch models asynchronously.
      make_year_changed? and form["make"] != "" and form["year"] != "" ->
        make = form["make"]
        year = form["year"]
        form = Map.put(form, "model", "")

        socket =
          socket
          |> assign(
            vehicle_form: form,
            vehicle_models: [],
            loading_models: true,
            vin_error: nil
          )
          |> start_async(:load_models, fn ->
            NhtsaClient.models_for_make_year(make, year)
          end)

        {:noreply, socket}

      # Make or year cleared → nothing to fetch.
      make_year_changed? ->
        {:noreply,
         assign(socket,
           vehicle_form: Map.put(form, "model", ""),
           vehicle_models: [],
           loading_models: false,
           vin_error: nil
         )}

      # Model (or color) changed → auto-detect size from the selected model.
      true ->
        form =
          if form["model"] != "" and form["model"] != prev["model"] do
            case Enum.find(socket.assigns.vehicle_models, &(&1.name == form["model"])) do
              %{size: size} -> Map.put(form, "size", to_string(size))
              nil -> form
            end
          else
            form
          end

        {:noreply, assign(socket, vehicle_form: form, vin_error: nil)}
    end
  end

  def handle_event("decode_vin", %{"vin" => vin}, socket) do
    vin = vin |> String.trim() |> String.upcase()

    if vin == "" do
      {:noreply, socket}
    else
      case NhtsaClient.decode_vin(vin) do
        {:ok, decoded} ->
          models =
            case NhtsaClient.models_for_make_year(decoded.make, decoded.year) do
              {:ok, m} -> m
              _ -> []
            end

          # Ensure the decoded model is selectable even if it isn't in the list
          models =
            if decoded.model && decoded.model != "" &&
                 not Enum.any?(models, &(&1.name == decoded.model)),
               do: [%{name: decoded.model, size: decoded.size} | models],
               else: models

          form = %{
            "make" => decoded.make,
            "year" => to_string(decoded.year),
            "model" => decoded.model || "",
            "color" => socket.assigns.vehicle_form["color"],
            "size" => to_string(decoded.size),
            "vin" => vin,
            "body_class" => decoded.body_class || ""
          }

          {:noreply,
           socket
           |> cancel_async(:load_models)
           |> assign(
             vehicle_form: form,
             vehicle_models: models,
             loading_models: false,
             vin_error: nil
           )}

        {:error, _reason} ->
          {:noreply,
           assign(socket,
             vin_error: "Couldn't read that VIN — enter your vehicle below."
           )}
      end
    end
  end

  def handle_event(
        "save_vehicle",
        %{"vehicle" => vehicle_params},
        %{assigns: %{current_customer: nil}} = socket
      ) do
    prev_ctx = build_context(socket.assigns)

    attrs =
      vehicle_params
      |> Map.take(~w(make model year color size vin body_class))
      |> Map.new(fn {k, v} -> {String.to_existing_atom(k), v} end)
      |> Map.update(:year, nil, fn v ->
        if is_binary(v) and v != "", do: String.to_integer(v), else: nil
      end)
      |> Map.update(:vin, nil, fn v -> if v in ["", nil], do: nil, else: v end)
      |> Map.update(:body_class, nil, fn v -> if v in ["", nil], do: nil, else: v end)
      |> Map.update(:size, :car, &size_to_atom/1)

    # Unsaved selection (id: nil) — persisted at Pay once the guest customer exists.
    vehicle = struct(Vehicle, attrs)

    {:noreply,
     socket
     |> assign(selected_vehicle: vehicle, show_new_vehicle_form: false)
     |> assign_price_breakdown()
     |> persist_booking_state()
     |> maybe_scroll(prev_ctx)}
  end

  def handle_event("save_vehicle", %{"vehicle" => vehicle_params}, socket) do
    prev_ctx = build_context(socket.assigns)
    customer = socket.assigns.current_customer

    allowed_vehicle_keys = ~w(make model year color size vin body_class)

    attrs =
      vehicle_params
      |> Map.take(allowed_vehicle_keys)
      |> Map.new(fn {k, v} -> {String.to_existing_atom(k), v} end)
      |> Map.update(:year, nil, fn v ->
        if is_binary(v) and v != "", do: String.to_integer(v), else: nil
      end)
      |> Map.update(:vin, nil, fn v -> if v in ["", nil], do: nil, else: v end)
      |> Map.update(:body_class, nil, fn v -> if v in ["", nil], do: nil, else: v end)

    case Vehicle
         |> Ash.Changeset.for_create(:create, attrs)
         |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
         |> Ash.create() do
      {:ok, vehicle} ->
        track_event(socket, "booking.vehicle_added", %{
          "vehicle_id" => vehicle.id,
          "is_new" => true
        })

        {:noreply,
         socket
         |> assign(
           selected_vehicle: vehicle,
           show_new_vehicle_form: false,
           existing_vehicles: socket.assigns.existing_vehicles ++ [vehicle]
         )
         |> assign_price_breakdown()
         |> persist_booking_state()
         |> maybe_scroll(prev_ctx)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not save vehicle. Please check your input.")}
    end
  end

  def handle_event("select_vehicle", %{"id" => id}, socket) do
    prev_ctx = build_context(socket.assigns)
    vehicle = Enum.find(socket.assigns.existing_vehicles, &(&1.id == id))
    track_event(socket, "booking.vehicle_added", %{"vehicle_id" => id, "is_new" => false})

    {:noreply,
     socket
     |> assign(selected_vehicle: vehicle)
     |> assign_price_breakdown()
     |> persist_booking_state()
     |> maybe_scroll(prev_ctx)}
  end

  def handle_event(
        "save_address",
        %{"address" => address_params},
        %{assigns: %{current_customer: nil}} = socket
      ) do
    prev_ctx = build_context(socket.assigns)

    attrs =
      address_params
      |> Map.take(~w(street city state zip))
      |> Map.new(fn {k, v} -> {String.to_existing_atom(k), v} end)

    address =
      struct(Address, Map.put(attrs, :zone, MobileCarWash.Zones.zone_for_zip(attrs[:zip])))

    {:noreply,
     socket
     |> assign(selected_address: address, show_new_address_form: false)
     |> persist_booking_state()
     |> maybe_scroll(prev_ctx)}
  end

  def handle_event("save_address", %{"address" => address_params}, socket) do
    prev_ctx = build_context(socket.assigns)
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
        track_event(socket, "booking.address_added", %{
          "address_id" => address.id,
          "is_new" => true
        })

        {:noreply,
         socket
         |> assign(
           selected_address: address,
           show_new_address_form: false,
           existing_addresses: socket.assigns.existing_addresses ++ [address]
         )
         |> persist_booking_state()
         |> maybe_scroll(prev_ctx)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not save address. Please check your input.")}
    end
  end

  def handle_event("select_address", %{"id" => id}, socket) do
    prev_ctx = build_context(socket.assigns)
    address = Enum.find(socket.assigns.existing_addresses, &(&1.id == id))
    track_event(socket, "booking.address_added", %{"address_id" => id, "is_new" => false})

    {:noreply,
     socket
     |> assign(selected_address: address)
     |> persist_booking_state()
     |> maybe_scroll(prev_ctx)}
  end

  def handle_event("address_search", %{"q" => q}, socket) do
    q = String.trim(q)

    if String.length(q) < 4 do
      {:noreply,
       assign(socket, address_query: q, address_suggestions: [], loading_suggestions: false)}
    else
      {:noreply,
       socket
       |> assign(address_query: q, loading_suggestions: true)
       |> start_async(:geocode_suggest, fn -> GeocoderClient.suggest(q) end)}
    end
  end

  def handle_event("select_suggestion", %{"index" => index}, socket) do
    prev_ctx = build_context(socket.assigns)

    case Enum.at(socket.assigns.address_suggestions, String.to_integer(index)) do
      nil ->
        {:noreply, socket}

      s ->
        case choose_geocoded_address(socket, s, prev_ctx) do
          {:ok, socket} ->
            {:noreply,
             socket
             |> assign(address_suggestions: [], address_query: "", loading_suggestions: false)
             |> push_event("address_map_set", %{lat: s.lat, lng: s.lng})}

          {:error, socket} ->
            {:noreply, socket}
        end
    end
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
    prev_ctx = build_context(socket.assigns)

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
         |> assign_price_breakdown()
         |> persist_booking_state()
         |> maybe_scroll(prev_ctx)}
    end
  end

  def handle_event("toggle_loyalty", _params, socket) do
    socket =
      socket
      |> assign(redeem_loyalty: !socket.assigns.redeem_loyalty)
      |> assign_price_breakdown()

    {:noreply, socket}
  end

  def handle_event("apply_referral", %{"code" => code}, socket) do
    customer = socket.assigns.current_customer

    if customer do
      case MobileCarWash.Scheduling.Booking.validate_referral_code(
             String.trim(String.upcase(code)),
             customer.id
           ) do
        {:ok, _referrer} ->
          {:noreply,
           socket
           |> assign(
             referral_code: String.trim(String.upcase(code)),
             referral_discount: 1000,
             referral_error: nil
           )
           |> assign_price_breakdown()}

        {:error, :self_referral} ->
          {:noreply,
           socket
           |> assign(
             referral_code: nil,
             referral_discount: 0,
             referral_error: "You can't use your own referral code"
           )
           |> assign_price_breakdown()}

        {:error, :not_found} ->
          {:noreply,
           socket
           |> assign(
             referral_code: nil,
             referral_discount: 0,
             referral_error: "Invalid referral code"
           )
           |> assign_price_breakdown()}
      end
    else
      {:noreply,
       socket
       |> assign(referral_error: "Sign in to use a referral code")
       |> assign_price_breakdown()}
    end
  end

  def handle_event("clear_referral", _params, socket) do
    socket =
      socket
      |> assign(referral_code: nil, referral_discount: 0, referral_error: nil)
      |> assign_price_breakdown()

    {:noreply, socket}
  end

  def handle_event("toggle_receipt", _params, socket) do
    {:noreply, assign(socket, receipt_expanded: !socket.assigns.receipt_expanded)}
  end

  def handle_event("confirm_booking", _params, socket) do
    if BookingSections.payable?(build_context(socket.assigns)) do
      with {:ok, socket} <- ensure_customer(socket),
           {:ok, socket} <- persist_pending_records(socket) do
        do_confirm_booking(socket)
      else
        {:error, message} -> {:noreply, assign(socket, guest_error: message)}
      end
    else
      {:noreply, put_flash(socket, :error, "Please complete all sections before paying.")}
    end
  end

  defp do_confirm_booking(socket) do
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
      subscription_id:
        socket.assigns.active_subscription && socket.assigns.active_subscription.id,
      loyalty_redeem: socket.assigns.redeem_loyalty,
      referral_code: socket.assigns.referral_code,
      add_on_ids: Enum.map(socket.assigns.selected_add_ons || [], & &1.id)
    }

    case Booking.create_booking(booking_params) do
      {:ok, %{appointment: appointment, checkout_url: checkout_url}}
      when not is_nil(checkout_url) ->
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
         |> put_flash(:info, "Booking confirmed!")
         |> push_navigate(to: ~p"/book/success?id=#{appointment.id}")}

      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, "Booking failed: #{inspect(reason)}. Please try again.")}
    end
  end

  # === ASYNC CALLBACKS ===

  @impl true
  def handle_async(:load_models, {:ok, {:ok, models}}, socket) do
    {:noreply, assign(socket, vehicle_models: models, loading_models: false)}
  end

  def handle_async(:load_models, {:ok, {:error, _reason}}, socket) do
    {:noreply, assign(socket, vehicle_models: [], loading_models: false)}
  end

  def handle_async(:load_models, {:exit, _reason}, socket) do
    {:noreply, assign(socket, vehicle_models: [], loading_models: false)}
  end

  def handle_async(:geocode_suggest, {:ok, {:ok, suggestions}}, socket) do
    {:noreply, assign(socket, address_suggestions: suggestions, loading_suggestions: false)}
  end

  def handle_async(:geocode_suggest, {:ok, {:error, _reason}}, socket) do
    {:noreply, assign(socket, address_suggestions: [], loading_suggestions: false)}
  end

  def handle_async(:geocode_suggest, {:exit, _reason}, socket) do
    {:noreply, assign(socket, address_suggestions: [], loading_suggestions: false)}
  end

  # === PRIVATE HELPERS ===

  # Returns {:ok, socket_with_customer} | {:error, message}. Signed-in users
  # pass through untouched; guests are looked up / created from guest_form at
  # the moment of payment.
  defp ensure_customer(%{assigns: %{current_customer: %{} = _c}} = socket), do: {:ok, socket}

  defp ensure_customer(socket) do
    alias MobileCarWash.Accounts.Customer

    guest = socket.assigns.guest_form

    existing =
      Customer
      |> Ash.Query.filter(email == ^guest["email"])
      |> Ash.read!(authorize?: false)

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
                 email: guest["email"],
                 name: guest["name"],
                 phone: guest["phone"]
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
        {:ok, assign(socket, current_customer: customer, guest_mode: true, guest_error: nil)}

      {:error, message} ->
        {:error, message}
    end
  end

  defp persist_pending_records(socket) do
    with {:ok, socket} <- persist_pending_vehicle(socket) do
      persist_pending_address(socket)
    end
  end

  defp persist_pending_vehicle(
         %{assigns: %{selected_vehicle: %{id: nil} = v, current_customer: c}} = socket
       ) do
    attrs = Map.take(v, [:make, :model, :year, :color, :size, :vin, :body_class])

    case Vehicle
         |> Ash.Changeset.for_create(:create, attrs)
         |> Ash.Changeset.force_change_attribute(:customer_id, c.id)
         |> Ash.create() do
      {:ok, saved} -> {:ok, assign(socket, selected_vehicle: saved)}
      {:error, _} -> {:error, "Could not save your vehicle. Please check the details."}
    end
  end

  defp persist_pending_vehicle(socket), do: {:ok, socket}

  # Guest: hold the geocoded address in-memory (persisted at Pay).
  defp choose_geocoded_address(%{assigns: %{current_customer: nil}} = socket, s, prev_ctx) do
    address =
      struct(Address, %{
        street: s.street,
        city: s.city,
        state: s.state,
        zip: s.zip,
        latitude: s.lat,
        longitude: s.lng,
        zone: MobileCarWash.Zones.zone_for_zip(s.zip)
      })

    {:ok,
     socket
     |> assign(selected_address: address, show_new_address_form: false)
     |> persist_booking_state()
     |> maybe_scroll(prev_ctx)}
  end

  # Signed-in: persist the geocoded address immediately (zone is set by the
  # Address resource's SetZoneFromZip change; coords are accepted as-is).
  defp choose_geocoded_address(socket, s, prev_ctx) do
    customer = socket.assigns.current_customer

    case Address
         |> Ash.Changeset.for_create(:create, %{
           street: s.street,
           city: s.city,
           state: s.state,
           zip: s.zip,
           latitude: s.lat,
           longitude: s.lng
         })
         |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
         |> Ash.create() do
      {:ok, address} ->
        {:ok,
         socket
         |> assign(
           selected_address: address,
           existing_addresses: socket.assigns.existing_addresses ++ [address]
         )
         |> persist_booking_state()
         |> maybe_scroll(prev_ctx)}

      {:error, _} ->
        {:error,
         put_flash(socket, :error, "Could not save that address. Please try manual entry.")}
    end
  end

  defp persist_pending_address(
         %{assigns: %{selected_address: %{id: nil} = a, current_customer: c}} = socket
       ) do
    attrs = Map.take(a, [:street, :city, :state, :zip, :latitude, :longitude])

    case Address
         |> Ash.Changeset.for_create(:create, attrs)
         |> Ash.Changeset.force_change_attribute(:customer_id, c.id)
         |> Ash.create() do
      {:ok, saved} -> {:ok, assign(socket, selected_address: saved)}
      {:error, _} -> {:error, "Could not save your address. Please check the details."}
    end
  end

  defp persist_pending_address(socket), do: {:ok, socket}

  # Progressive-reveal nicety: if the latest selection flipped a section from
  # :locked to :active, smooth-scroll the browser to it. Best-effort — the page
  # works without JS.
  defp maybe_scroll(socket, prev_ctx) do
    new_ctx = build_context(socket.assigns)

    newly_active =
      Enum.find(BookingSections.sections(), fn section ->
        BookingSections.status(section, prev_ctx) == :locked and
          BookingSections.status(section, new_ctx) == :active
      end)

    case newly_active do
      nil -> socket
      section -> push_event(socket, "scroll_to", %{id: "section-#{section}"})
    end
  end

  defp build_context(assigns) do
    %{
      selected_service: assigns[:selected_service],
      current_customer: assigns[:current_customer],
      guest_mode: assigns[:guest_mode] || false,
      guest_form: assigns[:guest_form],
      selected_vehicle: assigns[:selected_vehicle],
      selected_address: assigns[:selected_address],
      selected_slot: assigns[:selected_slot],
      selected_add_ons: assigns[:selected_add_ons],
      appointment: assigns[:appointment]
    }
  end

  defp persist_booking_state(socket) do
    SessionCache.put(socket.assigns.booking_session_id, %{
      guest_mode: socket.assigns.guest_mode,
      customer_id: socket.assigns.current_customer && socket.assigns.current_customer.id,
      service_id: socket.assigns.selected_service && socket.assigns.selected_service.id,
      vehicle_id: socket.assigns.selected_vehicle && socket.assigns.selected_vehicle.id,
      address_id: socket.assigns.selected_address && socket.assigns.selected_address.id,
      block_id: socket.assigns.selected_block && socket.assigns.selected_block.id,
      addon_ids: Enum.map(socket.assigns.selected_add_ons || [], & &1.id)
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

    customer =
      cached[:customer_id] && safe_get(MobileCarWash.Accounts.Customer, cached[:customer_id])

    vehicle = cached[:vehicle_id] && safe_get(Vehicle, cached[:vehicle_id])
    address = cached[:address_id] && safe_get(Address, cached[:address_id])

    block = cached[:block_id] && safe_get_block(cached[:block_id])

    add_ons =
      (cached[:addon_ids] || [])
      |> Enum.map(&safe_get(MobileCarWash.Scheduling.AddOn, &1))
      |> Enum.reject(fn a -> is_nil(a) or not a.active end)

    assigns = %{
      selected_service: service,
      current_customer: customer,
      selected_vehicle: vehicle,
      selected_address: address,
      selected_block: block,
      selected_slot: block && block.starts_at,
      guest_mode: cached[:guest_mode] || false,
      selected_add_ons: add_ons
    }

    assigns
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

    with %{} <- service,
         {:ok, parsed_date} <- Date.from_iso8601(date) do
      blocks =
        BlockAvailability.open_blocks_for_service_range(service.id, parsed_date, parsed_date)

      assign(socket, available_blocks: blocks)
    else
      _ -> socket
    end
  end

  defp load_step_data(socket, _step), do: socket

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
          |> Ash.Query.filter(
            subscription_id == ^sub.id and period_start <= ^today and period_end >= ^today
          )
          |> Ash.read!()
          |> List.first() || %{basic_washes_used: 0, deep_cleans_used: 0}

        Map.put(sub, :plan, plan) |> Map.put(:usage, usage)

      [] ->
        nil
    end
  end

  defp assign_price_breakdown(socket) do
    assign(socket, price_breakdown: compute_price_breakdown(socket.assigns))
  end

  defp compute_price_breakdown(%{selected_service: nil}), do: nil

  defp compute_price_breakdown(assigns) do
    base = assigns.selected_service.base_price_cents
    slug = assigns.selected_service.slug
    size = assigns.selected_vehicle && assigns.selected_vehicle.size

    sized = if size, do: Pricing.calculate(base, size), else: base

    # Mirror the server's discount stacking so the hero total equals the
    # charge: subscription first (off the base), then loyalty (zeroes the
    # remainder) or referral (capped at the post-subscription price).
    plan = assigns[:active_subscription] && assigns.active_subscription.plan
    sub_discount = Pricing.subscription_discount_cents(base, slug, plan)
    after_sub = max(sized - sub_discount, 0)

    discount =
      cond do
        assigns[:redeem_loyalty] -> sized
        true -> sub_discount + min(assigns[:referral_discount] || 0, after_sub)
      end

    Pricing.breakdown(%{
      base_price_cents: base,
      vehicle_size: size,
      addon_lines: Pricing.addon_lines(assigns[:selected_add_ons] || []),
      discount_cents: discount
    })
  end

  defp vehicle_years do
    current = Date.utc_today().year + 1
    Enum.to_list(current..1990//-1)
  end

  defp size_to_atom(s) when s in ["car", "suv_van", "pickup"], do: String.to_existing_atom(s)
  defp size_to_atom(s) when is_atom(s), do: s
  defp size_to_atom(_), do: :car

  defp size_badge("suv_van"), do: %{icon: "🚙", label: "SUV / Van", modifier: "+20%"}
  defp size_badge("pickup"), do: %{icon: "🚛", label: "Pickup", modifier: "+50%"}
  defp size_badge(_), do: %{icon: "🚗", label: "Car", modifier: "+0"}

  defp vehicle_colors do
    [
      {"Black", "#1a1a1a"},
      {"White", "#f5f5f5"},
      {"Silver", "#c0c0c0"},
      {"Gray", "#808080"},
      {"Red", "#c0392b"},
      {"Blue", "#2563eb"},
      {"Green", "#16a34a"},
      {"Tan", "#d2b48c"}
    ]
  end
end
