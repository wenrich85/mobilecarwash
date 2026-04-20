defmodule MobileCarWashWeb.Admin.CustomersLive do
  @moduledoc """
  Admin customer list. Joined date, acquired channel, lifetime revenue
  at a glance. Searchable by name/email. Click through to detail.
  """
  use MobileCarWashWeb, :live_view

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Marketing.AcquisitionChannel
  alias MobileCarWash.Repo

  import Ecto.Query

  @impl true
  def mount(_params, _session, socket) do
    channels =
      AcquisitionChannel
      |> Ash.read!(authorize?: false)
      |> Map.new(&{&1.id, &1})

    {:ok,
     socket
     |> assign(page_title: "Customers")
     |> assign(query: "")
     |> assign(channels: channels)
     |> load_customers("")}
  end

  @impl true
  def handle_event("search", %{"q" => query}, socket) do
    {:noreply,
     socket
     |> assign(query: query)
     |> load_customers(query)}
  end

  defp load_customers(socket, query) do
    customers =
      Customer
      |> Ash.read!(authorize?: false)
      |> Enum.filter(&matches_query?(&1, query))
      |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
      |> Enum.take(200)

    revenue = revenue_by_customer(Enum.map(customers, & &1.id))

    assign(socket, customers: customers, revenue: revenue)
  end

  defp matches_query?(_customer, ""), do: true
  defp matches_query?(_customer, nil), do: true

  defp matches_query?(customer, query) do
    q = String.downcase(query)

    String.contains?(String.downcase(customer.name || ""), q) or
      String.contains?(String.downcase(to_string(customer.email)), q)
  end

  defp revenue_by_customer([]), do: %{}

  defp revenue_by_customer(customer_ids) do
    uuids = Enum.map(customer_ids, fn id -> Ecto.UUID.dump!(id) end)

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

  defp to_int(nil), do: 0
  defp to_int(%Decimal{} = d), do: Decimal.to_integer(d)
  defp to_int(n) when is_integer(n), do: n

  defp fmt_cents(nil), do: "$0.00"
  defp fmt_cents(0), do: "$0.00"

  defp fmt_cents(cents) when is_integer(cents),
    do: "$" <> :erlang.float_to_binary(cents / 100, decimals: 2)

  defp channel_label(channels, nil), do: "—"
  defp channel_label(channels, cid) do
    case Map.get(channels, cid) do
      %{display_name: name} -> name
      _ -> "Unknown"
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-6xl mx-auto py-8 px-4">
      <div class="flex justify-between items-center mb-6">
        <div>
          <h1 class="text-3xl font-bold">Customers</h1>
          <p class="text-base-content/80">Every registered customer + their acquisition + lifetime revenue.</p>
        </div>
      </div>

      <form id="customer-search" phx-change="search" class="mb-4">
        <input
          type="search"
          name="q"
          value={@query}
          placeholder="Search by name or email…"
          class="input input-bordered w-full md:w-96"
        />
      </form>

      <div class="overflow-x-auto bg-base-100 rounded-lg border border-base-300">
        <table class="table">
          <thead>
            <tr>
              <th>Name</th>
              <th>Email</th>
              <th>Role</th>
              <th>Channel</th>
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
              <td class="text-right">{fmt_cents(Map.get(@revenue, c.id, 0))}</td>
              <td class="text-sm text-base-content/60">
                {Calendar.strftime(c.inserted_at, "%b %d, %Y")}
              </td>
            </tr>
            <tr :if={@customers == []}>
              <td colspan="6" class="text-center py-8 text-base-content/60">
                No customers match "{@query}"
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end
end
