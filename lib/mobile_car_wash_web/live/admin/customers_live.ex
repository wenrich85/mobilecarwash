defmodule MobileCarWashWeb.Admin.CustomersLive do
  @moduledoc """
  Admin customer list with triage-grade filters, sort, and pagination.

  State lives in the URL so filter combinations can be shared and the
  back button works as expected. Lifecycle columns (last wash, churn
  risk) are computed on each render from the `appointments` table — no
  denormalized columns on `customers`.
  """
  use MobileCarWashWeb, :live_view

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Marketing.AcquisitionChannel
  alias MobileCarWash.Repo

  import Ecto.Query
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

    {:ok,
     socket
     |> assign(page_title: "Customers")
     |> assign(channels: channels)
     |> assign(sort_options: @sort_options)
     |> assign(role_options: @roles)
     |> assign(verified_options: @verified_options)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = %{
      q: param(params, "q", ""),
      channel_id: param(params, "channel", ""),
      role: param(params, "role", ""),
      verified: param(params, "verified", "")
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

  # --- Loading ---

  defp load_customers(socket) do
    %{filters: filters, sort: sort, page: page} = socket.assigns

    # Ash filter pass — channel / role / verified / text search. Cheap
    # enough at solo-operator scale to load the whole filtered set and
    # sort + paginate in memory after enrichment.
    customers =
      Customer
      |> ash_query(filters)
      |> Ash.read!(authorize?: false)
      |> filter_by_query(filters.q)

    ids = Enum.map(customers, & &1.id)
    revenue = revenue_by_customer(ids)
    last_wash = last_completed_by_customer(ids)

    enriched =
      Enum.map(customers, fn c ->
        Map.merge(c, %{
          __lifetime_revenue__: Map.get(revenue, c.id, 0),
          __last_wash_at__: Map.get(last_wash, c.id)
        })
      end)

    sorted = sort_customers(enriched, sort)
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

  defp ash_query(query, filters) do
    query
    |> maybe_filter_channel(filters.channel_id)
    |> maybe_filter_role(filters.role)
    |> maybe_filter_verified(filters.verified)
  end

  defp maybe_filter_channel(q, ""), do: q

  defp maybe_filter_channel(q, channel_id) do
    Ash.Query.filter(q, acquired_channel_id == ^channel_id)
  end

  defp maybe_filter_role(q, ""), do: q

  defp maybe_filter_role(q, role) when is_binary(role) do
    atom = String.to_existing_atom(role)
    Ash.Query.filter(q, role == ^atom)
  rescue
    ArgumentError -> q
  end

  defp maybe_filter_verified(q, "yes"),
    do: Ash.Query.filter(q, not is_nil(email_verified_at))

  defp maybe_filter_verified(q, "no"),
    do: Ash.Query.filter(q, is_nil(email_verified_at))

  defp maybe_filter_verified(q, _), do: q

  defp filter_by_query(customers, ""), do: customers
  defp filter_by_query(customers, nil), do: customers

  defp filter_by_query(customers, query) do
    q = String.downcase(query)

    Enum.filter(customers, fn c ->
      String.contains?(String.downcase(c.name || ""), q) or
        String.contains?(String.downcase(to_string(c.email)), q)
    end)
  end

  defp sort_customers(customers, "joined_desc"),
    do: Enum.sort_by(customers, & &1.inserted_at, {:desc, DateTime})

  defp sort_customers(customers, "joined_asc"),
    do: Enum.sort_by(customers, & &1.inserted_at, {:asc, DateTime})

  defp sort_customers(customers, "ltv_desc"),
    do: Enum.sort_by(customers, & &1.__lifetime_revenue__, :desc)

  defp sort_customers(customers, "last_wash_desc") do
    # Nil last-wash goes to the bottom.
    Enum.sort_by(
      customers,
      fn c -> {c.__last_wash_at__ || ~U[1970-01-01 00:00:00Z], c.inserted_at} end,
      fn a, b ->
        case DateTime.compare(elem(a, 0), elem(b, 0)) do
          :gt -> true
          :lt -> false
          :eq -> DateTime.compare(elem(a, 1), elem(b, 1)) != :lt
        end
      end
    )
  end

  defp sort_customers(customers, "name_asc"),
    do: Enum.sort_by(customers, &String.downcase(&1.name || ""))

  defp sort_customers(customers, _), do: sort_customers(customers, "joined_desc")

  # --- Aggregates ---

  defp revenue_by_customer([]), do: %{}

  defp revenue_by_customer(customer_ids) do
    uuids = Enum.map(customer_ids, &Ecto.UUID.dump!/1)

    query =
      from p in "payments",
        where: p.status == "succeeded",
        where: p.customer_id in ^uuids,
        group_by: p.customer_id,
        select: %{
          customer_id: type(p.customer_id, Ecto.UUID),
          total: sum(p.amount_cents)
        }

    query
    |> Repo.all()
    |> Map.new(fn %{customer_id: cid, total: t} -> {cid, to_int(t)} end)
  end

  defp last_completed_by_customer([]), do: %{}

  defp last_completed_by_customer(customer_ids) do
    uuids = Enum.map(customer_ids, &Ecto.UUID.dump!/1)

    query =
      from a in "appointments",
        where: a.status == "completed",
        where: a.customer_id in ^uuids,
        group_by: a.customer_id,
        select: %{
          customer_id: type(a.customer_id, Ecto.UUID),
          last_at: max(a.scheduled_at)
        }

    query
    |> Repo.all()
    |> Map.new(fn %{customer_id: cid, last_at: at} -> {cid, at} end)
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
      "verified" => filters.verified
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

  defp to_int(nil), do: 0
  defp to_int(%Decimal{} = d), do: Decimal.to_integer(d)
  defp to_int(n) when is_integer(n), do: n

  defp fmt_cents(nil), do: "$0.00"
  defp fmt_cents(0), do: "$0.00"

  defp fmt_cents(cents) when is_integer(cents),
    do: "$" <> :erlang.float_to_binary(cents / 100, decimals: 2)

  defp fmt_date(nil), do: "—"
  defp fmt_date(%DateTime{} = dt), do: Calendar.strftime(dt, "%b %d, %Y")
  defp fmt_date(%NaiveDateTime{} = ndt), do: Calendar.strftime(ndt, "%b %d, %Y")

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
        class="grid grid-cols-1 md:grid-cols-5 gap-2 mb-4"
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

        <button
          :if={
            @filters.q != "" or @filters.channel_id != "" or @filters.role != "" or
              @filters.verified != ""
          }
          phx-click="clear_filters"
          class="btn btn-ghost btn-sm"
        >
          Clear filters
        </button>
      </div>

      <div class="overflow-x-auto bg-base-100 rounded-lg border border-base-300">
        <table class="table">
          <thead>
            <tr>
              <th>Name</th>
              <th>Email</th>
              <th>Role</th>
              <th>Channel</th>
              <th>Last wash</th>
              <th>Risk</th>
              <th class="text-right">Lifetime revenue</th>
              <th>Joined</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={c <- @customers} class="hover">
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
              <td colspan="8" class="text-center py-8 text-base-content/60">
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
