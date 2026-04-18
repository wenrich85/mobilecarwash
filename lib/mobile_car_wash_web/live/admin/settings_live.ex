defmodule MobileCarWashWeb.Admin.SettingsLive do
  @moduledoc """
  Admin settings — manage services and membership plans.
  """
  use MobileCarWashWeb, :live_view

  alias MobileCarWash.Scheduling.{ServiceType, BlockedDate}
  alias MobileCarWash.Billing.SubscriptionPlan
  alias MobileCarWash.CatalogBroadcaster

  require Ash.Query

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Settings",
       tab: :services,
       services: load_services(),
       plans: load_plans(),
       editing_service: nil,
       editing_plan: nil,
       blocked_dates: load_blocked_dates()
     )}
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, tab: String.to_existing_atom(tab), editing_service: nil, editing_plan: nil)}
  end

  # === Services ===

  def handle_event("add_service", %{"service" => params}, socket) do
    attrs = %{
      name: params["name"],
      slug: Slug.slugify(params["name"]),
      description: params["description"],
      base_price_cents: dollars_to_cents(params["price"]),
      duration_minutes: to_int(params["duration"]),
      active: true
    }

    case ServiceType |> Ash.Changeset.for_create(:create, attrs) |> Ash.create() do
      {:ok, _} ->
        CatalogBroadcaster.broadcast_services_updated()
        {:noreply, socket |> assign(services: load_services()) |> put_flash(:info, "Service added")}
      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not add service")}
    end
  end

  def handle_event("edit_service", %{"id" => id}, socket) do
    {:noreply, assign(socket, editing_service: id)}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, editing_service: nil, editing_plan: nil)}
  end

  def handle_event("update_service", %{"id" => id, "service" => params}, socket) do
    case Ash.get(ServiceType, id) do
      {:ok, service} ->
        attrs = %{
          name: params["name"],
          description: params["description"],
          base_price_cents: dollars_to_cents(params["price"]),
          duration_minutes: to_int(params["duration"])
        }

        case service |> Ash.Changeset.for_update(:update, attrs) |> Ash.update() do
          {:ok, _} ->
            CatalogBroadcaster.broadcast_services_updated()
            {:noreply, socket |> assign(services: load_services(), editing_service: nil) |> put_flash(:info, "Service updated")}
          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Could not update service")}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("toggle_service", %{"id" => id}, socket) do
    case Ash.get(ServiceType, id) do
      {:ok, service} ->
        service
        |> Ash.Changeset.for_update(:update, %{active: !service.active})
        |> Ash.update()

        CatalogBroadcaster.broadcast_services_updated()
        {:noreply, assign(socket, services: load_services())}

      _ ->
        {:noreply, socket}
    end
  end

  # === Plans ===

  def handle_event("add_plan", %{"plan" => params}, socket) do
    attrs = %{
      name: params["name"],
      slug: Slug.slugify(params["name"]),
      price_cents: dollars_to_cents(params["price"]),
      basic_washes_per_month: to_int(params["basic_washes"]),
      deep_cleans_per_month: to_int(params["deep_cleans"]),
      deep_clean_discount_percent: to_int(params["discount"]),
      description: params["description"],
      active: true
    }

    case SubscriptionPlan |> Ash.Changeset.for_create(:create, attrs) |> Ash.create() do
      {:ok, _} ->
        CatalogBroadcaster.broadcast_plans_updated()
        {:noreply, socket |> assign(plans: load_plans()) |> put_flash(:info, "Plan added")}
      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not add plan")}
    end
  end

  def handle_event("edit_plan", %{"id" => id}, socket) do
    {:noreply, assign(socket, editing_plan: id)}
  end

  def handle_event("update_plan", %{"id" => id, "plan" => params}, socket) do
    case Ash.get(SubscriptionPlan, id) do
      {:ok, plan} ->
        attrs = %{
          name: params["name"],
          price_cents: dollars_to_cents(params["price"]),
          basic_washes_per_month: to_int(params["basic_washes"]),
          deep_cleans_per_month: to_int(params["deep_cleans"]),
          deep_clean_discount_percent: to_int(params["discount"]),
          description: params["description"]
        }

        case plan |> Ash.Changeset.for_update(:update, attrs) |> Ash.update() do
          {:ok, _} ->
            CatalogBroadcaster.broadcast_plans_updated()
            {:noreply, socket |> assign(plans: load_plans(), editing_plan: nil) |> put_flash(:info, "Plan updated")}
          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Could not update plan")}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("toggle_plan", %{"id" => id}, socket) do
    case Ash.get(SubscriptionPlan, id) do
      {:ok, plan} ->
        plan
        |> Ash.Changeset.for_update(:update, %{active: !plan.active})
        |> Ash.update()

        CatalogBroadcaster.broadcast_plans_updated()
        {:noreply, assign(socket, plans: load_plans())}

      _ ->
        {:noreply, socket}
    end
  end

  # === Blocked Dates ===

  def handle_event("add_blocked_date", %{"blocked" => params}, socket) do
    case Date.from_iso8601(params["date"] || "") do
      {:ok, date} ->
        case BlockedDate
             |> Ash.Changeset.for_create(:create, %{date: date, reason: params["reason"]})
             |> Ash.create() do
          {:ok, _} ->
            {:noreply,
             socket
             |> assign(blocked_dates: load_blocked_dates())
             |> put_flash(:info, "Date blocked: #{date}")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Could not block date (may already be blocked)")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Invalid date")}
    end
  end

  def handle_event("remove_blocked_date", %{"id" => id}, socket) do
    case Ash.get(BlockedDate, id) do
      {:ok, blocked} ->
        Ash.destroy!(blocked)
        {:noreply,
         socket
         |> assign(blocked_dates: load_blocked_dates())
         |> put_flash(:info, "Date unblocked")}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-5xl mx-auto py-8 px-4">
      <h1 class="text-3xl font-bold mb-2">Settings</h1>
      <p class="text-base-content/60 mb-6">Manage services and membership plans.</p>

      <!-- Tabs -->
      <div class="tabs tabs-boxed mb-8">
        <button class={["tab", @tab == :services && "tab-active"]} phx-click="switch_tab" phx-value-tab="services">Services</button>
        <button class={["tab", @tab == :plans && "tab-active"]} phx-click="switch_tab" phx-value-tab="plans">Membership Plans</button>
        <button class={["tab", @tab == :blocked_dates && "tab-active"]} phx-click="switch_tab" phx-value-tab="blocked_dates">Blocked Dates</button>
        <button class={["tab", @tab == :accounting && "tab-active"]} phx-click="switch_tab" phx-value-tab="accounting">Accounting</button>
      </div>

      <!-- Services Tab -->
      <div :if={@tab == :services}>
        <!-- Add Service -->
        <div class="card bg-base-100 shadow mb-6">
          <div class="card-body p-4">
            <h3 class="font-bold mb-3">Add Service</h3>
            <form phx-submit="add_service" class="grid grid-cols-1 md:grid-cols-5 gap-3 items-end">
              <div class="form-control">
                <label class="label label-text text-xs">Name</label>
                <input type="text" name="service[name]" class="input input-bordered input-sm" required placeholder="Premium Detail" />
              </div>
              <div class="form-control">
                <label class="label label-text text-xs">Price ($)</label>
                <input type="number" name="service[price]" class="input input-bordered input-sm" required placeholder="150" step="1" min="1" />
              </div>
              <div class="form-control">
                <label class="label label-text text-xs">Duration (min)</label>
                <input type="number" name="service[duration]" class="input input-bordered input-sm" required placeholder="90" min="15" />
              </div>
              <div class="form-control">
                <label class="label label-text text-xs">Description</label>
                <input type="text" name="service[description]" class="input input-bordered input-sm" placeholder="Short description" />
              </div>
              <button type="submit" class="btn btn-primary btn-sm">Add</button>
            </form>
          </div>
        </div>

        <!-- Service List -->
        <div class="space-y-3">
          <div :for={svc <- @services} class={["card bg-base-100 shadow-sm", !svc.active && "opacity-50"]}>
            <div class="card-body p-4">
              <!-- View mode -->
              <div :if={@editing_service != svc.id} class="flex justify-between items-center">
                <div>
                  <div class="flex items-center gap-2">
                    <h4 class="font-bold">{svc.name}</h4>
                    <span class="badge badge-sm badge-ghost">{svc.slug}</span>
                    <span :if={!svc.active} class="badge badge-sm badge-error">Inactive</span>
                  </div>
                  <p class="text-sm text-base-content/60">{svc.description}</p>
                  <p class="text-sm mt-1">
                    <span class="font-semibold">${div(svc.base_price_cents, 100)}</span>
                    <span class="text-base-content/50"> · {svc.duration_minutes} min</span>
                  </p>
                </div>
                <div class="flex gap-2">
                  <button class="btn btn-ghost btn-xs" phx-click="edit_service" phx-value-id={svc.id}>Edit</button>
                  <button class={["btn btn-xs", if(svc.active, do: "btn-warning", else: "btn-success")]} phx-click="toggle_service" phx-value-id={svc.id}>
                    {if svc.active, do: "Deactivate", else: "Activate"}
                  </button>
                </div>
              </div>

              <!-- Edit mode -->
              <form :if={@editing_service == svc.id} phx-submit="update_service" phx-value-id={svc.id} class="grid grid-cols-1 md:grid-cols-5 gap-3 items-end">
                <div class="form-control">
                  <label class="label label-text text-xs">Name</label>
                  <input type="text" name="service[name]" class="input input-bordered input-sm" value={svc.name} required />
                </div>
                <div class="form-control">
                  <label class="label label-text text-xs">Price ($)</label>
                  <input type="number" name="service[price]" class="input input-bordered input-sm" value={div(svc.base_price_cents, 100)} required step="1" min="1" />
                </div>
                <div class="form-control">
                  <label class="label label-text text-xs">Duration (min)</label>
                  <input type="number" name="service[duration]" class="input input-bordered input-sm" value={svc.duration_minutes} required min="15" />
                </div>
                <div class="form-control">
                  <label class="label label-text text-xs">Description</label>
                  <input type="text" name="service[description]" class="input input-bordered input-sm" value={svc.description} />
                </div>
                <div class="flex gap-1">
                  <button type="submit" class="btn btn-primary btn-sm flex-1">Save</button>
                  <button type="button" class="btn btn-ghost btn-sm" phx-click="cancel_edit">Cancel</button>
                </div>
              </form>
            </div>
          </div>
        </div>
      </div>

      <!-- Plans Tab -->
      <div :if={@tab == :plans}>
        <!-- Add Plan -->
        <div class="card bg-base-100 shadow mb-6">
          <div class="card-body p-4">
            <h3 class="font-bold mb-3">Add Membership Plan</h3>
            <form phx-submit="add_plan" class="grid grid-cols-1 md:grid-cols-3 gap-3 items-end">
              <div class="form-control">
                <label class="label label-text text-xs">Name</label>
                <input type="text" name="plan[name]" class="input input-bordered input-sm" required placeholder="Gold" />
              </div>
              <div class="form-control">
                <label class="label label-text text-xs">Price ($/month)</label>
                <input type="number" name="plan[price]" class="input input-bordered input-sm" required placeholder="150" step="1" min="1" />
              </div>
              <div class="form-control">
                <label class="label label-text text-xs">Basic Washes/mo</label>
                <input type="number" name="plan[basic_washes]" class="input input-bordered input-sm" value="0" min="0" />
              </div>
              <div class="form-control">
                <label class="label label-text text-xs">Deep Cleans/mo</label>
                <input type="number" name="plan[deep_cleans]" class="input input-bordered input-sm" value="0" min="0" />
              </div>
              <div class="form-control">
                <label class="label label-text text-xs">Deep Clean Discount %</label>
                <input type="number" name="plan[discount]" class="input input-bordered input-sm" value="0" min="0" max="100" />
              </div>
              <div class="form-control md:col-span-2">
                <label class="label label-text text-xs">Description</label>
                <input type="text" name="plan[description]" class="input input-bordered input-sm" placeholder="What's included" />
              </div>
              <button type="submit" class="btn btn-primary btn-sm">Add Plan</button>
            </form>
          </div>
        </div>

        <!-- Plan List -->
        <div class="space-y-3">
          <div :for={plan <- @plans} class={["card bg-base-100 shadow-sm", !plan.active && "opacity-50"]}>
            <div class="card-body p-4">
              <!-- View mode -->
              <div :if={@editing_plan != plan.id}>
                <div class="flex justify-between items-start">
                  <div>
                    <div class="flex items-center gap-2">
                      <h4 class="font-bold text-lg">{plan.name}</h4>
                      <span class="badge badge-sm badge-ghost">{plan.slug}</span>
                      <span :if={!plan.active} class="badge badge-sm badge-error">Inactive</span>
                    </div>
                    <p class="text-2xl font-bold mt-1">${div(plan.price_cents, 100)}<span class="text-sm font-normal text-base-content/50">/month</span></p>
                  </div>
                  <div class="flex gap-2">
                    <button class="btn btn-ghost btn-xs" phx-click="edit_plan" phx-value-id={plan.id}>Edit</button>
                    <button class={["btn btn-xs", if(plan.active, do: "btn-warning", else: "btn-success")]} phx-click="toggle_plan" phx-value-id={plan.id}>
                      {if plan.active, do: "Deactivate", else: "Activate"}
                    </button>
                  </div>
                </div>
                <div class="flex flex-wrap gap-3 mt-2 text-sm">
                  <span :if={plan.basic_washes_per_month > 0} class="badge badge-outline">{plan.basic_washes_per_month} basic washes</span>
                  <span :if={plan.deep_cleans_per_month > 0} class="badge badge-outline">{plan.deep_cleans_per_month} deep cleans</span>
                  <span :if={plan.deep_clean_discount_percent > 0} class="badge badge-outline">{plan.deep_clean_discount_percent}% off deep cleans</span>
                </div>
                <p :if={plan.description} class="text-sm text-base-content/60 mt-2">{plan.description}</p>
              </div>

              <!-- Edit mode -->
              <form :if={@editing_plan == plan.id} phx-submit="update_plan" phx-value-id={plan.id} class="grid grid-cols-1 md:grid-cols-3 gap-3 items-end">
                <div class="form-control">
                  <label class="label label-text text-xs">Name</label>
                  <input type="text" name="plan[name]" class="input input-bordered input-sm" value={plan.name} required />
                </div>
                <div class="form-control">
                  <label class="label label-text text-xs">Price ($/month)</label>
                  <input type="number" name="plan[price]" class="input input-bordered input-sm" value={div(plan.price_cents, 100)} required step="1" min="1" />
                </div>
                <div class="form-control">
                  <label class="label label-text text-xs">Basic Washes/mo</label>
                  <input type="number" name="plan[basic_washes]" class="input input-bordered input-sm" value={plan.basic_washes_per_month} min="0" />
                </div>
                <div class="form-control">
                  <label class="label label-text text-xs">Deep Cleans/mo</label>
                  <input type="number" name="plan[deep_cleans]" class="input input-bordered input-sm" value={plan.deep_cleans_per_month} min="0" />
                </div>
                <div class="form-control">
                  <label class="label label-text text-xs">Deep Clean Discount %</label>
                  <input type="number" name="plan[discount]" class="input input-bordered input-sm" value={plan.deep_clean_discount_percent} min="0" max="100" />
                </div>
                <div class="form-control md:col-span-2">
                  <label class="label label-text text-xs">Description</label>
                  <input type="text" name="plan[description]" class="input input-bordered input-sm" value={plan.description} />
                </div>
                <div class="flex gap-1">
                  <button type="submit" class="btn btn-primary btn-sm flex-1">Save</button>
                  <button type="button" class="btn btn-ghost btn-sm" phx-click="cancel_edit">Cancel</button>
                </div>
              </form>
            </div>
          </div>
        </div>
      </div>

      <!-- Blocked Dates Tab -->
      <div :if={@tab == :blocked_dates}>
        <div class="card bg-base-100 shadow mb-6">
          <div class="card-body p-4">
            <h3 class="font-bold mb-3">Block a Date</h3>
            <p class="text-sm text-base-content/60 mb-3">
              Blocked dates won't have available slots. Customers can't book and recurring schedules will skip them.
            </p>
            <form phx-submit="add_blocked_date" class="grid grid-cols-1 md:grid-cols-3 gap-3 items-end">
              <div class="form-control">
                <label class="label label-text text-xs">Date</label>
                <input type="date" name="blocked[date]" class="input input-bordered input-sm" required />
              </div>
              <div class="form-control">
                <label class="label label-text text-xs">Reason (optional)</label>
                <input type="text" name="blocked[reason]" class="input input-bordered input-sm" placeholder="Holiday, vacation, etc." />
              </div>
              <button type="submit" class="btn btn-primary btn-sm">Block Date</button>
            </form>
          </div>
        </div>

        <div :if={@blocked_dates == []} class="text-center py-8 text-base-content/50">
          No dates blocked
        </div>

        <div class="overflow-x-auto">
          <table :if={@blocked_dates != []} class="table table-sm">
            <thead>
              <tr>
                <th>Date</th>
                <th>Day</th>
                <th>Reason</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={bd <- @blocked_dates}>
                <td>{Calendar.strftime(bd.date, "%b %-d, %Y")}</td>
                <td>{Calendar.strftime(bd.date, "%A")}</td>
                <td class="text-base-content/60">{bd.reason || "—"}</td>
                <td>
                  <button
                    class="btn btn-ghost btn-xs text-error"
                    phx-click="remove_blocked_date"
                    phx-value-id={bd.id}
                  >
                    Remove
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <!-- Accounting Tab -->
      <div :if={@tab == :accounting}>
        <div class="card bg-base-100 shadow">
          <div class="card-body p-6">
            <h3 class="font-bold text-lg mb-4">Accounting Integration</h3>
            <p class="text-sm text-base-content/60 mb-6">
              Select your accounting provider. Payments will automatically sync to the configured system.
              Credentials are managed via environment variables at deployment time.
            </p>

            <!-- Current Configuration Display -->
            <div class="bg-base-200 rounded-lg p-4 mb-6">
              <h4 class="font-semibold mb-3">Current Configuration</h4>
              <table class="table table-sm w-full">
                <tr>
                  <td class="font-semibold">Active Provider:</td>
                  <td>
                    {case Application.get_env(:mobile_car_wash, :accounting_provider) do
                      MobileCarWash.Accounting.ZohoBooks -> "Zoho Books"
                      MobileCarWash.Accounting.QuickBooks -> "QuickBooks Online"
                      nil -> "None (Accounting Disabled)"
                      _ -> "Unknown"
                    end}
                  </td>
                </tr>
              </table>
            </div>

            <!-- Environment Variables Reference -->
            <div class="bg-info/10 border border-info rounded-lg p-4">
              <h4 class="font-semibold text-info mb-3">Required Environment Variables</h4>
              <div class="space-y-3 text-sm">
                <div>
                  <p class="font-mono font-semibold">ACCOUNTING_PROVIDER</p>
                  <p class="text-base-content/70">Set to: "zoho", "quickbooks", or "none"</p>
                </div>
                <div :if={is_zoho_configured()} class="border-t border-info/30 pt-3">
                  <p class="font-mono font-semibold">Zoho Books (when ACCOUNTING_PROVIDER=zoho):</p>
                  <ul class="text-base-content/70 ml-4 mt-1 space-y-1">
                    <li>• ZOHO_ORG_ID</li>
                    <li>• ZOHO_CLIENT_ID</li>
                    <li>• ZOHO_CLIENT_SECRET</li>
                    <li>• ZOHO_REFRESH_TOKEN</li>
                  </ul>
                </div>
                <div :if={is_quickbooks_configured()} class="border-t border-info/30 pt-3">
                  <p class="font-mono font-semibold">QuickBooks Online (when ACCOUNTING_PROVIDER=quickbooks):</p>
                  <ul class="text-base-content/70 ml-4 mt-1 space-y-1">
                    <li>• QUICKBOOKS_COMPANY_ID</li>
                    <li>• QUICKBOOKS_CLIENT_ID</li>
                    <li>• QUICKBOOKS_CLIENT_SECRET</li>
                    <li>• QUICKBOOKS_REFRESH_TOKEN</li>
                  </ul>
                </div>
              </div>
              <p class="text-sm text-info mt-4">
                Update environment variables and redeploy to change providers.
              </p>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # --- Helpers ---

  defp is_zoho_configured do
    Application.get_env(:mobile_car_wash, :accounting_provider) == MobileCarWash.Accounting.ZohoBooks
  end

  defp is_quickbooks_configured do
    Application.get_env(:mobile_car_wash, :accounting_provider) == MobileCarWash.Accounting.QuickBooks
  end

  defp load_blocked_dates do
    BlockedDate |> Ash.Query.sort(date: :asc) |> Ash.read!()
  end

  defp load_services do
    ServiceType |> Ash.Query.sort(base_price_cents: :asc) |> Ash.read!()
  end

  defp load_plans do
    SubscriptionPlan |> Ash.Query.sort(price_cents: :asc) |> Ash.read!()
  end

  defp dollars_to_cents(str) when is_binary(str) do
    case Integer.parse(str) do
      {n, _} -> n * 100
      :error -> 0
    end
  end
  defp dollars_to_cents(_), do: 0

  defp to_int(str) when is_binary(str) do
    case Integer.parse(str) do
      {n, _} -> n
      :error -> 0
    end
  end
  defp to_int(_), do: 0
end
