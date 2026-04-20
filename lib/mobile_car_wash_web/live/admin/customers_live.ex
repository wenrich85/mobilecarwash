defmodule MobileCarWashWeb.Admin.CustomersLive do
  @moduledoc """
  Admin customer list with triage-grade filters, sort, and pagination.

  State lives in the URL so filter combinations can be shared and the
  back button works as expected. Lifecycle columns (last wash, churn
  risk) are computed on each render from the `appointments` table — no
  denormalized columns on `customers`.
  """
  use MobileCarWashWeb, :live_view

  alias MobileCarWash.Accounts.CustomerNote
  alias MobileCarWash.Marketing.{AcquisitionChannel, CustomerTag, Tag}
  alias MobileCarWash.Reporting.CustomerList

  require Ash.Query

  @page_size 50

  @sort_options [
    {"joined_desc", "Newest first"},
    {"joined_asc", "Oldest first"},
    {"ltv_desc", "Lifetime revenue (high → low)"},
    {"last_wash_desc", "Most recent wash"},
    {"name_asc", "Name (A → Z)"}
  ]

  @roles [
    {"", "Any role"},
    {"customer", "Customer"},
    {"guest", "Guest"},
    {"technician", "Technician"},
    {"admin", "Admin"}
  ]

  @verified_options [
    {"", "Any"},
    {"yes", "Verified only"},
    {"no", "Unverified only"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    channels =
      AcquisitionChannel
      |> Ash.read!(authorize?: false)
      |> Map.new(&{&1.id, &1})

    tags =
      Tag
      |> Ash.Query.for_read(:active)
      |> Ash.read!(authorize?: false)

    tag_by_id = Map.new(tags, &{&1.id, &1})

    {:ok,
     socket
     |> assign(page_title: "Customers")
     |> assign(channels: channels)
     |> assign(tags: tags)
     |> assign(tag_by_id: tag_by_id)
     |> assign(sort_options: @sort_options)
     |> assign(role_options: @roles)
     |> assign(verified_options: @verified_options)
     |> assign(selected_ids: MapSet.new())}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = %{
      q: param(params, "q", ""),
      channel_id: param(params, "channel", ""),
      role: param(params, "role", ""),
      verified: param(params, "verified", ""),
      tag_id: param(params, "tag", "")
    }

    sort = param(params, "sort", "joined_desc")
    page = params |> param("page", "1") |> parse_page()

    {:noreply,
     socket
     |> assign(filters: filters, sort: sort, page: page)
     |> load_customers()}
  end

  @impl true
  def handle_event("filter", params, socket) do
    # Merge incoming form values onto existing URL state, reset to page 1.
    query =
      %{
        "q" => Map.get(params, "q", ""),
        "channel" => Map.get(params, "channel", ""),
        "role" => Map.get(params, "role", ""),
        "verified" => Map.get(params, "verified", ""),
        "tag" => Map.get(params, "tag", ""),
        "sort" => socket.assigns.sort
      }
      |> trim_blanks()

    {:noreply, push_patch(socket, to: ~p"/admin/customers?#{query}", replace: true)}
  end

  def handle_event("sort", %{"sort" => sort}, socket) do
    query =
      socket.assigns.filters
      |> filters_to_query()
      |> Map.put("sort", sort)
      |> trim_blanks()

    {:noreply, push_patch(socket, to: ~p"/admin/customers?#{query}", replace: true)}
  end

  def handle_event("clear_filters", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/admin/customers", replace: true)}
  end

  def handle_event("toggle_select", %{"id" => id}, socket) do
    selected =
      if MapSet.member?(socket.assigns.selected_ids, id) do
        MapSet.delete(socket.assigns.selected_ids, id)
      else
        MapSet.put(socket.assigns.selected_ids, id)
      end

    {:noreply, assign(socket, selected_ids: selected)}
  end

  def handle_event("clear_selection", _params, socket) do
    {:noreply, assign(socket, selected_ids: MapSet.new())}
  end

  def handle_event("bulk_tag", %{"tag_id" => ""}, socket) do
    {:noreply, put_flash(socket, :error, "Pick a tag to apply")}
  end

  def handle_event("bulk_tag", %{"tag_id" => tag_id}, socket) do
    case Ash.get(Tag, tag_id, authorize?: false) do
      {:ok, tag} ->
        ids = MapSet.to_list(socket.assigns.selected_ids)
        admin_id = socket.assigns.current_customer.id
        {applied, skipped} = apply_tag_to_customers(ids, tag, admin_id)

        flash =
          case {applied, skipped} do
            {n, 0} -> "Tagged #{n} customer(s) with #{tag.name}"
            {0, n} -> "All #{n} already had #{tag.name}"
            {a, s} -> "Tagged #{a}, skipped #{s} already tagged"
          end

        {:noreply,
         socket
         |> assign(selected_ids: MapSet.new())
         |> put_flash(:info, flash)
         |> load_customers()}

      _ ->
        {:noreply, put_flash(socket, :error, "Tag not found")}
    end
  end

  # Attempts to tag each customer. Returns {applied_count, skipped_count}.
  # Skipped = duplicate-pair (customer already has the tag).
  defp apply_tag_to_customers(ids, tag, admin_id) do
    Enum.reduce(ids, {0, 0}, fn cid, {ok, skip} ->
      case CustomerTag
           |> Ash.Changeset.for_create(:tag, %{
             customer_id: cid,
             tag_id: tag.id,
             author_id: admin_id
           })
           |> Ash.create(authorize?: false) do
        {:ok, _} ->
          CustomerNote
          |> Ash.Changeset.for_create(:add, %{
            customer_id: cid,
            author_id: admin_id,
            body: "Tagged customer: #{tag.name} (bulk).",
            pinned: false
          })
          |> Ash.create!(authorize?: false)

          {ok + 1, skip}

        {:error, _} ->
          # Most common cause: unique-pair violation (already tagged).
          {ok, skip + 1}
      end
    end)
  end

  # --- Loading ---

  defp load_customers(socket) do
    %{filters: filters, sort: sort, page: page} = socket.assigns

    sorted =
      filters
      |> CustomerList.list_filtered()
      |> CustomerList.sort(sort)

    total = length(sorted)
    pages = max(1, div(total + @page_size - 1, @page_size))
    page = min(page, pages)
    page_rows = sorted |> Enum.drop((page - 1) * @page_size) |> Enum.take(@page_size)

    assign(socket,
      customers: page_rows,
      total: total,
      page: page,
      pages: pages
    )
  end

  # --- URL / params helpers ---

  defp param(params, key, default) do
    case Map.get(params, key) do
      nil -> default
      "" -> default
      v when is_binary(v) -> v
      _ -> default
    end
  end

  defp parse_page(value) do
    case Integer.parse(value || "") do
      {n, _} when n > 0 -> n
      _ -> 1
    end
  end

  defp filters_to_query(filters) do
    %{
      "q" => filters.q,
      "channel" => filters.channel_id,
      "role" => filters.role,
      "verified" => filters.verified,
      "tag" => filters.tag_id
    }
  end

  defp trim_blanks(params) do
    params
    |> Enum.reject(fn {_, v} -> v in [nil, ""] end)
    |> Map.new()
  end

  defp page_query(filters, sort, page) do
    filters
    |> filters_to_query()
    |> Map.put("sort", sort)
    |> Map.put("page", Integer.to_string(page))
    |> trim_blanks()
  end

  # --- Formatting ---

  defp fmt_cents(nil), do: "$0.00"
  defp fmt_cents(0), do: "$0.00"

  defp fmt_cents(cents) when is_integer(cents),
    do: "$" <> :erlang.float_to_binary(cents / 100, decimals: 2)

  defp fmt_date(nil), do: "—"
  defp fmt_date(%DateTime{} = dt), do: Calendar.strftime(dt, "%b %d, %Y")
  defp fmt_date(%NaiveDateTime{} = ndt), do: Calendar.strftime(ndt, "%b %d, %Y")

  defp tag_badge_class(%{color: :primary}), do: "badge-primary"
  defp tag_badge_class(%{color: :success}), do: "badge-success"
  defp tag_badge_class(%{color: :warning}), do: "badge-warning"
  defp tag_badge_class(%{color: :error}), do: "badge-error"
  defp tag_badge_class(%{color: :info}), do: "badge-info"
  defp tag_badge_class(_), do: "badge-neutral"

  defp channel_label(_channels, nil), do: "—"

  defp channel_label(channels, cid) do
    case Map.get(channels, cid) do
      %{display_name: name} -> name
      _ -> "Unknown"
    end
  end

  # Churn risk buckets. Returns {label, badge_class}.
  defp risk(nil, _inserted_at), do: {"new", "badge-ghost"}

  defp risk(%DateTime{} = last_wash, _inserted_at) do
    days = DateTime.diff(DateTime.utc_now(), last_wash, :second) |> div(86_400)
    risk_bucket(days)
  end

  defp risk(%NaiveDateTime{} = last_wash, _inserted_at) do
    # NaiveDateTime fallback — treat as UTC.
    last_dt = DateTime.from_naive!(last_wash, "Etc/UTC")
    risk(last_dt, nil)
  end

  defp risk_bucket(days) when days <= 30, do: {"active", "badge-success"}
  defp risk_bucket(days) when days <= 60, do: {"watch", "badge-warning"}
  defp risk_bucket(days) when days <= 120, do: {"at risk", "badge-error"}
  defp risk_bucket(_), do: {"churned", "badge-neutral"}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto py-8 px-4">
      <div class="flex justify-between items-center mb-6">
        <div>
          <h1 class="text-3xl font-bold">Customers</h1>
          <p class="text-base-content/80">
            {@total} total. Filter, sort, and triage by lifecycle stage.
          </p>
        </div>
      </div>

      <form
        id="customer-filters"
        phx-change="filter"
        phx-submit="filter"
        class="grid grid-cols-1 md:grid-cols-6 gap-2 mb-4"
      >
        <input
          type="search"
          name="q"
          value={@filters.q}
          placeholder="Search name or email…"
          class="input input-bordered md:col-span-2"
        />

        <select name="channel" class="select select-bordered">
          <option value="">Any channel</option>
          <option
            :for={{_, c} <- @channels}
            value={c.id}
            selected={c.id == @filters.channel_id}
          >
            {c.display_name}
          </option>
        </select>

        <select name="role" class="select select-bordered">
          <option
            :for={{val, label} <- @role_options}
            value={val}
            selected={val == @filters.role}
          >
            {label}
          </option>
        </select>

        <select name="verified" class="select select-bordered">
          <option
            :for={{val, label} <- @verified_options}
            value={val}
            selected={val == @filters.verified}
          >
            {label}
          </option>
        </select>

        <select name="tag" class="select select-bordered">
          <option value="">Any tag</option>
          <option :for={t <- @tags} value={t.id} selected={t.id == @filters.tag_id}>
            {t.name}
          </option>
        </select>
      </form>

      <div class="flex flex-wrap items-center justify-between gap-2 mb-3">
        <form id="customer-sort" phx-change="sort">
          <label class="text-sm text-base-content/70 mr-2">Sort</label>
          <select name="sort" class="select select-bordered select-sm">
            <option
              :for={{val, label} <- @sort_options}
              value={val}
              selected={val == @sort}
            >
              {label}
            </option>
          </select>
        </form>

        <div class="flex items-center gap-2">
          <button
            :if={
              @filters.q != "" or @filters.channel_id != "" or @filters.role != "" or
                @filters.verified != "" or @filters.tag_id != ""
            }
            phx-click="clear_filters"
            class="btn btn-ghost btn-sm"
          >
            Clear filters
          </button>

          <a
            id="export-csv"
            href={~p"/admin/customers/export.csv?#{page_query(@filters, @sort, 1)}"}
            class="btn btn-outline btn-sm"
          >
            Export CSV
          </a>
        </div>
      </div>

      <div
        :if={MapSet.size(@selected_ids) > 0}
        id="bulk-toolbar"
        class="alert alert-info mb-3 flex flex-col md:flex-row md:items-center gap-3"
      >
        <div class="flex-1 text-sm">
          <span class="font-semibold">{MapSet.size(@selected_ids)}</span> selected
        </div>

        <form
          id="bulk-tag-form"
          phx-submit="bulk_tag"
          class="join"
        >
          <select name="tag_id" class="select select-bordered select-sm join-item">
            <option value="">Apply tag…</option>
            <option :for={t <- @tags} value={t.id}>{t.name}</option>
          </select>
          <button type="submit" class="btn btn-sm btn-primary join-item">Apply</button>
        </form>

        <button
          type="button"
          phx-click="clear_selection"
          class="btn btn-ghost btn-sm"
        >
          Clear selection
        </button>
      </div>

      <div class="overflow-x-auto bg-base-100 rounded-lg border border-base-300">
        <table class="table">
          <thead>
            <tr>
              <th class="w-10"></th>
              <th>Name</th>
              <th>Email</th>
              <th>Role</th>
              <th>Channel</th>
              <th>Tags</th>
              <th>Last wash</th>
              <th>Risk</th>
              <th class="text-right">Lifetime revenue</th>
              <th>Joined</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={c <- @customers} class="hover">
              <td>
                <input
                  type="checkbox"
                  id={"select-#{c.id}"}
                  phx-click="toggle_select"
                  phx-value-id={c.id}
                  checked={MapSet.member?(@selected_ids, c.id)}
                  class="checkbox checkbox-sm"
                />
              </td>
              <td class="font-medium">
                <.link navigate={~p"/admin/customers/#{c.id}"} class="link link-hover">
                  {c.name}
                </.link>
              </td>
              <td class="text-sm text-base-content/70 truncate">{c.email}</td>
              <td>
                <span class="badge badge-sm badge-ghost">{c.role}</span>
              </td>
              <td class="text-sm">{channel_label(@channels, c.acquired_channel_id)}</td>
              <td>
                <div class="flex flex-wrap gap-1">
                  <span
                    :for={tid <- c.__tag_ids__}
                    :if={Map.has_key?(@tag_by_id, tid)}
                    class={"badge badge-xs " <> tag_badge_class(Map.get(@tag_by_id, tid))}
                  >
                    {Map.get(@tag_by_id, tid).name}
                  </span>
                </div>
              </td>
              <td class="text-sm text-base-content/70">{fmt_date(c.__last_wash_at__)}</td>
              <td>
                <% {label, cls} = risk(c.__last_wash_at__, c.inserted_at) %>
                <span class={"badge badge-sm " <> cls}>{label}</span>
              </td>
              <td class="text-right">{fmt_cents(c.__lifetime_revenue__)}</td>
              <td class="text-sm text-base-content/60">
                {Calendar.strftime(c.inserted_at, "%b %d, %Y")}
              </td>
            </tr>
            <tr :if={@customers == []}>
              <td colspan="10" class="text-center py-8 text-base-content/60">
                No customers match those filters.
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <div :if={@pages > 1} class="flex items-center justify-between mt-4">
        <div class="text-sm text-base-content/60">
          Page {@page} of {@pages}
        </div>
        <div class="join">
          <.link
            :if={@page > 1}
            patch={~p"/admin/customers?#{page_query(@filters, @sort, @page - 1)}"}
            class="btn btn-sm join-item"
          >
            ← Prev
          </.link>
          <.link
            :if={@page < @pages}
            patch={~p"/admin/customers?#{page_query(@filters, @sort, @page + 1)}"}
            class="btn btn-sm join-item"
          >
            Next →
          </.link>
        </div>
      </div>
    </div>
    """
  end
end
