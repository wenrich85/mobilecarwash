defmodule MobileCarWashWeb.Admin.SuppliesLive do
  @moduledoc """
  Admin supplies management — track on-hand quantities of chemicals, equipment,
  and disposables. Restocking automatically records a cash flow expense.
  """
  use MobileCarWashWeb, :live_view

  alias MobileCarWash.Inventory
  alias MobileCarWash.Inventory.Supply

  @categories [:chemicals, :equipment, :disposables, :safety, :other]

  @impl true
  def mount(_params, _session, socket) do
    supplies = Inventory.list_all_supplies()
    low_stock = Inventory.low_stock_supplies()

    {:ok,
     assign(socket,
       page_title: "Supplies",
       supplies: supplies,
       low_stock_ids: MapSet.new(low_stock, & &1.id),
       editing: nil,
       restocking: nil,
       form_data: %{},
       restock_qty: "",
       restock_cost: "",
       restock_notes: "",
       error: nil,
       show_inactive: false,
       viewing_usage_for: nil,
       usage_records: []
     )}
  end

  @impl true
  def handle_event("toggle_inactive", _params, socket) do
    {:noreply, assign(socket, show_inactive: !socket.assigns.show_inactive)}
  end

  def handle_event("new_supply", _params, socket) do
    {:noreply, assign(socket, editing: :new, form_data: default_form(), error: nil)}
  end

  def handle_event("edit_supply", %{"id" => id}, socket) do
    supply = Enum.find(socket.assigns.supplies, &(&1.id == id))
    form_data = %{
      "name" => supply.name,
      "category" => to_string(supply.category),
      "unit" => supply.unit,
      "low_stock_threshold" => supply.low_stock_threshold && Decimal.to_string(supply.low_stock_threshold) || "",
      "unit_cost_cents" => supply.unit_cost_cents && div(supply.unit_cost_cents, 100) |> to_string() || "",
      "supplier" => supply.supplier || "",
      "notes" => supply.notes || "",
      "active" => to_string(supply.active)
    }
    {:noreply, assign(socket, editing: id, form_data: form_data, error: nil)}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, editing: nil, restocking: nil, error: nil)}
  end

  def handle_event("form_change", %{"supply" => params}, socket) do
    {:noreply, assign(socket, form_data: params)}
  end

  def handle_event("save_supply", %{"supply" => params}, socket) do
    attrs = parse_supply_attrs(params)

    result =
      if socket.assigns.editing == :new do
        Supply
        |> Ash.Changeset.for_create(:create, attrs)
        |> Ash.create()
      else
        supply = Enum.find(socket.assigns.supplies, &(&1.id == socket.assigns.editing))
        supply
        |> Ash.Changeset.for_update(:update, attrs)
        |> Ash.update()
      end

    case result do
      {:ok, _} ->
        supplies = Inventory.list_all_supplies()
        low_stock = Inventory.low_stock_supplies()
        {:noreply,
         socket
         |> assign(supplies: supplies, low_stock_ids: MapSet.new(low_stock, & &1.id), editing: nil, error: nil)
         |> put_flash(:info, "Supply saved.")}

      {:error, changeset} ->
        {:noreply, assign(socket, error: format_errors(changeset))}
    end
  end

  def handle_event("start_restock", %{"id" => id}, socket) do
    supply = Enum.find(socket.assigns.supplies, &(&1.id == id))
    default_cost = supply.unit_cost_cents && div(supply.unit_cost_cents, 100) |> to_string() || ""
    {:noreply, assign(socket,
      restocking: id,
      restock_qty: "",
      restock_cost: default_cost,
      restock_notes: "",
      error: nil
    )}
  end

  def handle_event("save_restock", %{"qty" => qty_str, "cost" => cost_str, "notes" => notes}, socket) do
    supply = Enum.find(socket.assigns.supplies, &(&1.id == socket.assigns.restocking))

    with {:ok, qty} <- parse_decimal(qty_str, "Quantity"),
         {:ok, cost_cents} <- parse_dollars(cost_str, "Total cost") do
      case Inventory.restock(supply, qty, cost_cents, if(notes != "", do: notes)) do
        {:ok, _} ->
          supplies = Inventory.list_all_supplies()
          low_stock = Inventory.low_stock_supplies()
          {:noreply,
           socket
           |> assign(supplies: supplies, low_stock_ids: MapSet.new(low_stock, & &1.id), restocking: nil, error: nil)
           |> put_flash(:info, "Restocked #{supply.name}. Cash flow expense recorded.")}

        {:error, reason} ->
          {:noreply, assign(socket, error: inspect(reason))}
      end
    else
      {:error, msg} -> {:noreply, assign(socket, error: msg)}
    end
  end

  def handle_event("use_quantity", %{"id" => id, "qty" => qty_str}, socket) do
    supply = Enum.find(socket.assigns.supplies, &(&1.id == id))

    with {:ok, qty} <- parse_decimal(qty_str, "Quantity") do
      supply
      |> Ash.Changeset.for_update(:use_quantity, %{quantity: qty})
      |> Ash.update()

      supplies = Inventory.list_all_supplies()
      low_stock = Inventory.low_stock_supplies()
      {:noreply,
       socket
       |> assign(supplies: supplies, low_stock_ids: MapSet.new(low_stock, & &1.id))
       |> put_flash(:info, "Usage recorded.")}
    else
      {:error, msg} -> {:noreply, assign(socket, error: msg)}
    end
  end

  def handle_event("view_usage", %{"id" => supply_id}, socket) do
    records = Inventory.usage_for_supply(supply_id)
    {:noreply, assign(socket, viewing_usage_for: supply_id, usage_records: records)}
  end

  def handle_event("close_usage", _params, socket) do
    {:noreply, assign(socket, viewing_usage_for: nil, usage_records: [])}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-5xl mx-auto py-8 px-4">
      <div class="flex items-center justify-between mb-6 flex-wrap gap-3">
        <h1 class="text-2xl font-bold">Supplies</h1>
        <div class="flex gap-2">
          <label class="flex items-center gap-2 text-sm cursor-pointer">
            <input type="checkbox" class="checkbox checkbox-sm" phx-click="toggle_inactive"
                   checked={@show_inactive} />
            Show inactive
          </label>
          <button class="btn btn-primary btn-sm" phx-click="new_supply">+ Add Supply</button>
        </div>
      </div>

      <!-- Low stock alerts -->
      <div :if={MapSet.size(@low_stock_ids) > 0} class="alert alert-warning mb-6">
        <div>
          <p class="font-semibold">⚠ Low stock: {MapSet.size(@low_stock_ids)} item(s) need restocking</p>
          <p class="text-sm">
            {Enum.filter(@supplies, &MapSet.member?(@low_stock_ids, &1.id)) |> Enum.map(& &1.name) |> Enum.join(", ")}
          </p>
        </div>
      </div>

      <!-- Add/Edit form -->
      <div :if={@editing} class="card bg-base-100 shadow mb-6">
        <div class="card-body">
          <h3 class="font-semibold mb-4">{if @editing == :new, do: "Add Supply", else: "Edit Supply"}</h3>
          <form phx-submit="save_supply" phx-change="form_change">
            <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mb-4">
              <div>
                <label class="label text-sm font-medium">Name *</label>
                <input name="supply[name]" type="text" class="input input-bordered w-full"
                       value={@form_data["name"]} required />
              </div>
              <div>
                <label class="label text-sm font-medium">Category</label>
                <select name="supply[category]" class="select select-bordered w-full">
                  <option :for={cat <- @categories} value={cat}
                          selected={@form_data["category"] == to_string(cat)}>
                    {category_label(cat)}
                  </option>
                </select>
              </div>
              <div>
                <label class="label text-sm font-medium">Unit of measure</label>
                <input name="supply[unit]" type="text" class="input input-bordered w-full"
                       value={@form_data["unit"]} placeholder="gallons, bottles, boxes…" />
              </div>
              <div>
                <label class="label text-sm font-medium">Low stock alert threshold</label>
                <input name="supply[low_stock_threshold]" type="number" step="0.01" min="0"
                       class="input input-bordered w-full"
                       value={@form_data["low_stock_threshold"]}
                       placeholder="e.g. 2" />
              </div>
              <div>
                <label class="label text-sm font-medium">Default unit cost ($)</label>
                <input name="supply[unit_cost_cents]" type="number" step="0.01" min="0"
                       class="input input-bordered w-full"
                       value={@form_data["unit_cost_cents"]}
                       placeholder="e.g. 12.50" />
              </div>
              <div>
                <label class="label text-sm font-medium">Supplier</label>
                <input name="supply[supplier]" type="text" class="input input-bordered w-full"
                       value={@form_data["supplier"]} placeholder="Amazon, local store…" />
              </div>
              <div class="md:col-span-2">
                <label class="label text-sm font-medium">Notes</label>
                <input name="supply[notes]" type="text" class="input input-bordered w-full"
                       value={@form_data["notes"]} />
              </div>
              <div :if={@editing != :new} class="flex items-center gap-2">
                <input type="checkbox" name="supply[active]" value="true" class="checkbox"
                       checked={@form_data["active"] == "true"} />
                <label class="text-sm">Active</label>
              </div>
            </div>
            <p :if={@error} class="text-error text-sm mb-3">{@error}</p>
            <div class="flex gap-2">
              <button type="submit" class="btn btn-primary btn-sm">Save</button>
              <button type="button" class="btn btn-ghost btn-sm" phx-click="cancel_edit">Cancel</button>
            </div>
          </form>
        </div>
      </div>

      <!-- Restock form -->
      <div :if={@restocking} class="card bg-base-100 shadow mb-6 border-l-4 border-success">
        <div class="card-body">
          <% supply = Enum.find(@supplies, &(&1.id == @restocking)) %>
          <h3 class="font-semibold mb-1">Restock — {supply && supply.name}</h3>
          <p class="text-sm text-base-content/50 mb-4">
            Current on hand: {supply && format_qty(supply.quantity_on_hand)} {supply && supply.unit}.
            The total cost will be recorded as a cash flow expense.
          </p>
          <form phx-submit="save_restock" class="flex flex-wrap gap-3 items-end">
            <div>
              <label class="label text-xs">Quantity added</label>
              <input name="qty" type="number" step="0.01" min="0.01" required
                     class="input input-bordered input-sm w-28"
                     value={@restock_qty} placeholder="e.g. 4" />
            </div>
            <div>
              <label class="label text-xs">Total cost paid ($)</label>
              <input name="cost" type="number" step="0.01" min="0" required
                     class="input input-bordered input-sm w-28"
                     value={@restock_cost} placeholder="e.g. 45.00" />
            </div>
            <div class="flex-1 min-w-40">
              <label class="label text-xs">Notes (optional)</label>
              <input name="notes" type="text" class="input input-bordered input-sm w-full"
                     value={@restock_notes} placeholder="Amazon order #…" />
            </div>
            <div class="flex gap-2 pb-1">
              <button type="submit" class="btn btn-success btn-sm">Restock & Record Expense</button>
              <button type="button" class="btn btn-ghost btn-sm" phx-click="cancel_edit">Cancel</button>
            </div>
          </form>
          <p :if={@error} class="text-error text-sm mt-2">{@error}</p>
        </div>
      </div>

      <!-- Supplies table grouped by category -->
      <div :for={cat <- @categories} class="mb-6">
        <% cat_supplies = Enum.filter(@supplies, fn s ->
              s.category == cat and (@show_inactive or s.active)
           end) %>
        <div :if={cat_supplies != []}>
          <h3 class="font-semibold text-base-content/60 text-sm uppercase tracking-wide mb-2">
            {category_label(cat)}
          </h3>
          <div class="card bg-base-100 shadow">
            <div class="overflow-x-auto">
              <table class="table table-sm">
                <thead>
                  <tr>
                    <th>Name</th>
                    <th>On Hand</th>
                    <th>Alert At</th>
                    <th>Unit Cost</th>
                    <th>Supplier</th>
                    <th></th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={supply <- cat_supplies}
                      class={[!supply.active && "opacity-40"]}>
                    <td>
                      <div class="flex items-center gap-2">
                        <span class={["font-medium", !supply.active && "line-through"]}>{supply.name}</span>
                        <span :if={MapSet.member?(@low_stock_ids, supply.id)}
                              class="badge badge-warning badge-xs">Low</span>
                        <span :if={!supply.active} class="badge badge-ghost badge-xs">Inactive</span>
                      </div>
                      <div :if={supply.notes} class="text-xs text-base-content/40">{supply.notes}</div>
                    </td>
                    <td class={[
                      "font-semibold",
                      MapSet.member?(@low_stock_ids, supply.id) && "text-warning"
                    ]}>
                      {format_qty(supply.quantity_on_hand)} {supply.unit}
                    </td>
                    <td class="text-base-content/50 text-sm">
                      {if supply.low_stock_threshold,
                        do: "#{format_qty(supply.low_stock_threshold)} #{supply.unit}",
                        else: "—"}
                    </td>
                    <td class="text-sm">
                      {if supply.unit_cost_cents,
                        do: "$#{format_dollars(supply.unit_cost_cents)} / #{supply.unit}",
                        else: "—"}
                    </td>
                    <td class="text-sm text-base-content/50">{supply.supplier || "—"}</td>
                    <td>
                      <div class="flex gap-1">
                        <button class="btn btn-success btn-xs"
                                phx-click="start_restock" phx-value-id={supply.id}>
                          Restock
                        </button>
                        <button class="btn btn-ghost btn-xs"
                                phx-click="edit_supply" phx-value-id={supply.id}>
                          Edit
                        </button>
                        <button class="btn btn-ghost btn-xs"
                                phx-click="view_usage" phx-value-id={supply.id}>
                          Usage
                        </button>
                      </div>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        </div>
      </div>

      <div :if={@supplies == []} class="text-center py-12 text-base-content/50">
        <p class="mb-4">No supplies added yet.</p>
        <button class="btn btn-primary btn-sm" phx-click="new_supply">Add your first supply</button>
      </div>
    </div>

    <!-- Usage history modal -->
    <div :if={@viewing_usage_for} class="modal modal-open">
      <div class="modal-box w-full max-w-2xl">
        <% viewed_supply = Enum.find(@supplies, &(&1.id == @viewing_usage_for)) %>
        <div class="flex justify-between items-center mb-4">
          <h3 class="font-bold text-lg">
            Usage History — {viewed_supply && viewed_supply.name}
          </h3>
          <button class="btn btn-ghost btn-sm btn-square" phx-click="close_usage">✕</button>
        </div>

        <div :if={@usage_records == []} class="text-base-content/50 text-sm py-4 text-center">
          No usage recorded yet.
        </div>

        <div :if={@usage_records != []} class="overflow-x-auto">
          <table class="table table-sm">
            <thead>
              <tr>
                <th>Date</th>
                <th>Qty Used</th>
                <th>Tech</th>
                <th>Van</th>
                <th>Appointment</th>
                <th>Notes</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={rec <- @usage_records}>
                <td class="text-sm">{Calendar.strftime(rec.occurred_at, "%b %d, %Y %I:%M %p")}</td>
                <td class="font-semibold">{format_qty(rec.quantity_used)} {viewed_supply && viewed_supply.unit}</td>
                <td class="text-sm text-base-content/60">
                  {if rec.technician_id, do: String.slice(rec.technician_id, 0, 8) <> "…", else: "—"}
                </td>
                <td class="text-sm text-base-content/60">
                  {if rec.van_id, do: String.slice(rec.van_id, 0, 8) <> "…", else: "—"}
                </td>
                <td class="text-sm text-base-content/60">
                  {if rec.appointment_id, do: String.slice(rec.appointment_id, 0, 8) <> "…", else: "—"}
                </td>
                <td class="text-sm text-base-content/50">{rec.notes || "—"}</td>
              </tr>
            </tbody>
          </table>
        </div>

        <div class="modal-action">
          <button class="btn btn-ghost btn-sm" phx-click="close_usage">Close</button>
        </div>
      </div>
      <div class="modal-backdrop" phx-click="close_usage"></div>
    </div>
    """
  end

  # --- Helpers ---

  @categories [:chemicals, :equipment, :disposables, :safety, :other]
  def categories, do: @categories

  defp category_label(:chemicals), do: "Chemicals"
  defp category_label(:equipment), do: "Equipment"
  defp category_label(:disposables), do: "Disposables"
  defp category_label(:safety), do: "Safety"
  defp category_label(:other), do: "Other"

  defp format_qty(nil), do: "0"
  defp format_qty(%Decimal{} = d) do
    f = Decimal.to_float(d)
    if trunc(f) == f, do: "#{trunc(f)}", else: "#{Float.round(f, 2)}"
  end
  defp format_qty(n), do: to_string(n)

  defp format_dollars(cents) when is_integer(cents) do
    d = div(cents, 100)
    r = rem(cents, 100)
    "#{d}.#{String.pad_leading("#{r}", 2, "0")}"
  end

  defp default_form do
    %{
      "name" => "",
      "category" => "chemicals",
      "unit" => "units",
      "low_stock_threshold" => "",
      "unit_cost_cents" => "",
      "supplier" => "",
      "notes" => "",
      "active" => "true"
    }
  end

  defp parse_supply_attrs(params) do
    %{
      name: params["name"],
      category: String.to_existing_atom(params["category"] || "other"),
      unit: params["unit"] || "units",
      low_stock_threshold: parse_decimal_or_nil(params["low_stock_threshold"]),
      unit_cost_cents: parse_cost_cents(params["unit_cost_cents"]),
      supplier: nil_if_blank(params["supplier"]),
      notes: nil_if_blank(params["notes"]),
      active: params["active"] == "true"
    }
  end

  defp parse_decimal(str, field) do
    case Decimal.parse(String.trim(str || "")) do
      {d, ""} ->
        if Decimal.gt?(d, Decimal.new(0)), do: {:ok, d}, else: {:error, "#{field} must be a positive number"}
      _ ->
        {:error, "#{field} must be a positive number"}
    end
  end

  defp parse_dollars(str, field) do
    str = String.trim(str || "")
    if str == "" do
      {:ok, 0}
    else
      case Float.parse(str) do
        {f, _} when f >= 0 -> {:ok, round(f * 100)}
        _ -> {:error, "#{field} must be a valid dollar amount"}
      end
    end
  end

  defp parse_decimal_or_nil(nil), do: nil
  defp parse_decimal_or_nil(""), do: nil
  defp parse_decimal_or_nil(str) do
    case Decimal.parse(String.trim(str)) do
      {d, ""} -> d
      _ -> nil
    end
  end

  defp parse_cost_cents(nil), do: nil
  defp parse_cost_cents(""), do: nil
  defp parse_cost_cents(str) do
    case Float.parse(String.trim(str)) do
      {f, _} when f > 0 -> round(f * 100)
      _ -> nil
    end
  end

  defp nil_if_blank(nil), do: nil
  defp nil_if_blank(""), do: nil
  defp nil_if_blank(str), do: str

  defp format_errors(%Ash.Error.Invalid{errors: errors}) do
    errors |> Enum.map(& &1.message) |> Enum.join(", ")
  end
  defp format_errors(e), do: inspect(e)
end
