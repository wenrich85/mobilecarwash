defmodule MobileCarWashWeb.Admin.ManualAppointmentLive do
  @moduledoc """
  Admin form to manually create an appointment. Supports an existing or new
  client, an inline vehicle + address, and a waive-payment (comp) option that
  still records the full-value transaction.
  """
  use MobileCarWashWeb, :live_view

  alias MobileCarWash.Scheduling.{Booking, ServiceType}
  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Fleet.{Vehicle, Address}
  alias MobileCarWash.Operations.Technician

  require Ash.Query

  @impl true
  def mount(_params, _session, socket) do
    customers = customers()
    first_id = customers |> List.first() |> then(&(&1 && &1.id))
    service_types = service_types()

    {:ok,
     socket
     |> assign(
       page_title: "New Appointment",
       client_mode: "existing",
       waive: false,
       customers: customers,
       service_types: service_types,
       collected_default_cents: default_price(service_types),
       technicians: technicians()
     )
     |> load_customer_fleet(first_id)}
  end

  @impl true
  def handle_event("set_client_mode", %{"mode" => mode}, socket) do
    {:noreply, assign(socket, client_mode: mode)}
  end

  # Keep the "amount collected" default in step with the chosen service.
  def handle_event("select_service", params, socket) do
    id = get_in(params, ["manual_appointment", "service_type_id"]) || params["service_type_id"]
    service = Enum.find(socket.assigns.service_types, &(&1.id == id))
    cents = if service, do: service.base_price_cents, else: socket.assigns.collected_default_cents
    {:noreply, assign(socket, collected_default_cents: cents)}
  end

  # Reload the saved vehicles/addresses when the admin picks a different client.
  def handle_event("select_customer", params, socket) do
    id = get_in(params, ["manual_appointment", "customer_id"]) || params["customer_id"]
    {:noreply, load_customer_fleet(socket, id)}
  end

  def handle_event("toggle_waive", params, socket) do
    {:noreply, assign(socket, waive: params["waive"] == "true")}
  end

  def handle_event("submit", %{"manual_appointment" => p}, socket) do
    case Booking.admin_create_booking(build_params(p)) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Appointment created.")
         |> redirect(to: ~p"/admin/dispatch")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not create appointment: #{inspect(reason)}")}
    end
  end

  defp build_params(p) do
    base = %{
      service_type_id: p["service_type_id"],
      scheduled_at: parse_dt(p["scheduled_at"]),
      technician_id: blank_to_nil(p["technician_id"]),
      notes: blank_to_nil(p["notes"]),
      waive_payment?: p["waive"] == "true",
      comp_reason: blank_to_nil(p["comp_reason"]),
      notify_client?: p["notify_client"] == "true"
    }

    base
    |> put_client(p)
    |> put_vehicle(p)
    |> put_address(p)
    |> put_collected(p)
  end

  # Only meaningful when not waiving: record the amount actually collected.
  # Blank leaves it unset so the orchestrator falls back to the full price.
  defp put_collected(%{waive_payment?: true} = acc, _p), do: acc

  defp put_collected(acc, p) do
    case parse_cents(p["amount_collected"]) do
      cents when is_integer(cents) -> Map.put(acc, :collected_cents, cents)
      _ -> acc
    end
  end

  # Parses a currency string ("30", "30.00", "$1,234.50") to integer cents.
  defp parse_cents(value) when is_binary(value) do
    cleaned = String.replace(value, ~r/[^\d.]/, "")

    case Float.parse(cleaned) do
      {dollars, _} -> round(dollars * 100)
      :error -> nil
    end
  end

  defp parse_cents(_), do: nil

  defp put_client(acc, %{"client_mode" => "existing"} = p),
    do: Map.put(acc, :customer_id, p["customer_id"])

  defp put_client(acc, p) do
    Map.put(acc, :new_customer, %{
      name: p["new_customer_name"],
      email: p["new_customer_email"],
      phone: p["new_customer_phone"]
    })
  end

  # Existing client + an existing vehicle selection uses vehicle_id; otherwise inline.
  defp put_vehicle(acc, %{"vehicle_id" => id}) when is_binary(id) and id != "",
    do: Map.put(acc, :vehicle_id, id)

  defp put_vehicle(acc, p) do
    Map.put(acc, :new_vehicle, %{
      make: p["vehicle_make"],
      model: p["vehicle_model"],
      size: String.to_existing_atom(p["vehicle_size"] || "car")
    })
  end

  defp put_address(acc, %{"address_id" => id}) when is_binary(id) and id != "",
    do: Map.put(acc, :address_id, id)

  defp put_address(acc, p) do
    Map.put(acc, :new_address, %{
      street: p["address_street"],
      city: p["address_city"],
      state: p["address_state"] || "TX",
      zip: p["address_zip"]
    })
  end

  defp parse_dt(value) when is_binary(value) and value != "" do
    {:ok, ndt} = NaiveDateTime.from_iso8601(value <> ":00")
    DateTime.from_naive!(ndt, "Etc/UTC")
  end

  defp parse_dt(_), do: nil

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(v), do: v

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto py-8 px-4">
      <h1 class="text-3xl font-bold mb-6">New Appointment</h1>

      <form id="manual-appointment-form" phx-submit="submit" class="space-y-4">
        <div class="join">
          <button
            type="button"
            class={["btn btn-sm join-item", @client_mode == "existing" && "btn-active"]}
            phx-click="set_client_mode"
            phx-value-mode="existing"
          >
            Existing client
          </button>
          <button
            type="button"
            class={["btn btn-sm join-item", @client_mode == "new" && "btn-active"]}
            phx-click="set_client_mode"
            phx-value-mode="new"
          >
            New client
          </button>
        </div>
        <%!-- sr-only select carries client_mode as a real form field so tests can override it --%>
        <select name="manual_appointment[client_mode]" class="sr-only">
          <option value="existing" selected={@client_mode == "existing"}>Existing</option>
          <option value="new" selected={@client_mode == "new"}>New</option>
        </select>

        <%!-- Both client panels are always rendered; CSS toggles visibility so
             the test framework can find all form fields regardless of mode. --%>
        <div class={[@client_mode != "existing" && "hidden"]}>
          <label class="label label-text">Client</label>
          <select
            name="manual_appointment[customer_id]"
            class="select select-bordered w-full"
            phx-change="select_customer"
          >
            <option :for={c <- @customers} value={c.id} selected={c.id == @selected_customer_id}>
              {c.name} ({c.email})
            </option>
          </select>
        </div>

        <div class={["grid grid-cols-1 gap-2", @client_mode != "new" && "hidden"]}>
          <input
            name="manual_appointment[new_customer_name]"
            placeholder="Name"
            class="input input-bordered w-full"
          />
          <input
            name="manual_appointment[new_customer_email]"
            placeholder="Email"
            class="input input-bordered w-full"
          />
          <input
            name="manual_appointment[new_customer_phone]"
            placeholder="Phone"
            class="input input-bordered w-full"
          />
        </div>

        <%!-- Existing client with saved vehicles: pick one (no duplicate row). --%>
        <div :if={@client_mode == "existing" and @vehicles != []}>
          <label class="label label-text">Vehicle</label>
          <select name="manual_appointment[vehicle_id]" class="select select-bordered w-full">
            <option :for={v <- @vehicles} value={v.id}>
              {v.make} {v.model} ({v.size})
            </option>
          </select>
        </div>

        <%!-- New client, or existing client with no saved vehicle: quick-add. --%>
        <div :if={@client_mode == "new" or @vehicles == []} class="grid grid-cols-3 gap-2">
          <input
            name="manual_appointment[vehicle_make]"
            placeholder="Make"
            class="input input-bordered"
          />
          <input
            name="manual_appointment[vehicle_model]"
            placeholder="Model"
            class="input input-bordered"
          />
          <select name="manual_appointment[vehicle_size]" class="select select-bordered">
            <option value="car">Car</option>
            <option value="suv_van">SUV/Van</option>
            <option value="pickup">Pickup</option>
          </select>
        </div>

        <%!-- Existing client with saved addresses: pick one (no duplicate row). --%>
        <div :if={@client_mode == "existing" and @addresses != []}>
          <label class="label label-text">Address</label>
          <select name="manual_appointment[address_id]" class="select select-bordered w-full">
            <option :for={ad <- @addresses} value={ad.id}>
              {ad.street}, {ad.city} {ad.zip}
            </option>
          </select>
        </div>

        <%!-- New client, or existing client with no saved address: quick-add. --%>
        <div :if={@client_mode == "new" or @addresses == []} class="grid grid-cols-2 gap-2">
          <input
            name="manual_appointment[address_street]"
            placeholder="Street"
            class="input input-bordered"
          />
          <input
            name="manual_appointment[address_city]"
            placeholder="City"
            class="input input-bordered"
          />
          <input
            name="manual_appointment[address_state]"
            value="TX"
            placeholder="State"
            class="input input-bordered"
          />
          <input
            name="manual_appointment[address_zip]"
            placeholder="ZIP"
            class="input input-bordered"
          />
        </div>

        <div class="grid grid-cols-2 gap-2">
          <select
            name="manual_appointment[service_type_id]"
            class="select select-bordered"
            phx-change="select_service"
          >
            <option :for={st <- @service_types} value={st.id}>{st.name}</option>
          </select>
          <input
            type="datetime-local"
            name="manual_appointment[scheduled_at]"
            required
            class="input input-bordered"
          />
        </div>

        <select name="manual_appointment[technician_id]" class="select select-bordered w-full">
          <option value="">No technician (assign later)</option>
          <option :for={t <- @technicians} value={t.id}>{t.name}</option>
        </select>

        <label class="label cursor-pointer justify-start gap-2">
          <input
            type="checkbox"
            name="manual_appointment[waive]"
            value="true"
            class="checkbox"
            phx-click="toggle_waive"
            phx-value-waive={to_string(!@waive)}
          />
          <span class="label-text">Waive payment (comp)</span>
        </label>

        <%!-- Always in DOM; hidden when waive is false so tests can submit comp_reason. --%>
        <input
          name="manual_appointment[comp_reason]"
          placeholder="Reason for comp"
          class={["input input-bordered w-full", !@waive && "hidden"]}
        />

        <%!-- Amount actually collected (cash/partial/off-platform). Hidden while
             waiving; always in DOM so tests can submit it. Defaults to the
             selected service's price. --%>
        <label class={["form-control w-full", @waive && "hidden"]}>
          <span class="label label-text">Amount collected</span>
          <input
            name="manual_appointment[amount_collected]"
            type="text"
            inputmode="decimal"
            value={cents_to_dollars(@collected_default_cents)}
            placeholder="0.00"
            class="input input-bordered w-full"
          />
        </label>

        <label class="label cursor-pointer justify-start gap-2">
          <%!-- Hidden "false" ensures an unchecked box submits false; the visible checkbox overrides it to "true". --%>
          <input type="hidden" name="manual_appointment[notify_client]" value="false" />
          <input
            type="checkbox"
            name="manual_appointment[notify_client]"
            value="true"
            checked
            class="checkbox"
          />
          <span class="label-text">Notify client (confirmation + reminders)</span>
        </label>

        <button type="submit" class="btn btn-primary w-full">Create appointment</button>
      </form>
    </div>
    """
  end

  # Tracks the chosen client and loads their saved vehicles/addresses so the
  # form can offer them as pickers instead of always inserting new Fleet rows.
  defp load_customer_fleet(socket, nil) do
    assign(socket, selected_customer_id: nil, vehicles: [], addresses: [])
  end

  defp load_customer_fleet(socket, customer_id) do
    assign(socket,
      selected_customer_id: customer_id,
      vehicles: vehicles_for(customer_id),
      addresses: addresses_for(customer_id)
    )
  end

  defp vehicles_for(customer_id) do
    Vehicle
    |> Ash.Query.for_read(:for_customer, %{customer_id: customer_id})
    |> Ash.read!(authorize?: false)
  end

  defp addresses_for(customer_id) do
    Address
    |> Ash.Query.for_read(:for_customer, %{customer_id: customer_id})
    |> Ash.read!(authorize?: false)
  end

  defp default_price([%{base_price_cents: cents} | _]) when is_integer(cents), do: cents
  defp default_price(_), do: 0

  defp cents_to_dollars(cents) when is_integer(cents) do
    :erlang.float_to_binary(cents / 100, decimals: 2)
  end

  defp cents_to_dollars(_), do: "0.00"

  defp customers do
    Customer
    |> Ash.Query.filter(role in [:customer, :guest])
    |> Ash.Query.sort(name: :asc)
    |> Ash.read!(authorize?: false)
  end

  defp service_types, do: ServiceType |> Ash.read!(authorize?: false)

  defp technicians do
    Technician
    |> Ash.Query.filter(active == true)
    |> Ash.read!(authorize?: false)
  end
end
