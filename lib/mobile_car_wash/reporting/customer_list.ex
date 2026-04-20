defmodule MobileCarWash.Reporting.CustomerList do
  @moduledoc """
  The filter + enrich + sort pipeline behind the admin customer list.

  Used by two surfaces:

    * `MobileCarWashWeb.Admin.CustomersLive` — paginates the output
      for on-screen rendering.
    * `MobileCarWashWeb.Admin.CustomersExportController` — streams
      the full filtered set to a CSV.

  Keeping this in a plain module (not a LiveView helper, not an Ash
  resource) makes both callers dead-simple and avoids duplicating
  the 3 aggregate queries.
  """

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Repo

  import Ecto.Query
  require Ash.Query

  @type filters :: %{
          optional(:q) => String.t(),
          optional(:channel_id) => String.t(),
          optional(:role) => String.t(),
          optional(:verified) => String.t(),
          optional(:tag_id) => String.t()
        }

  @doc """
  Returns customers matching `filters`, enriched with three extra
  fields the list UI / export both rely on:

    * `__lifetime_revenue__` — cents, summed from succeeded payments
    * `__last_wash_at__` — max(scheduled_at) over completed appointments
    * `__tag_ids__` — list of applied tag uuids
  """
  @spec list_filtered(filters()) :: [struct()]
  def list_filtered(filters) do
    customers =
      Customer
      |> ash_query(filters)
      |> Ash.read!(authorize?: false)
      |> filter_by_query(filters[:q] || "")

    ids = Enum.map(customers, & &1.id)
    revenue = revenue_by_customer(ids)
    last_wash = last_completed_by_customer(ids)
    tag_ids_by_customer = tag_ids_by_customer(ids)

    customers
    |> Enum.map(fn c ->
      Map.merge(c, %{
        __lifetime_revenue__: Map.get(revenue, c.id, 0),
        __last_wash_at__: Map.get(last_wash, c.id),
        __tag_ids__: Map.get(tag_ids_by_customer, c.id, [])
      })
    end)
    |> filter_by_tag(filters[:tag_id] || "")
  end

  @doc "Sort an already-enriched customer list by a URL-friendly key."
  @spec sort(list(), String.t()) :: list()
  def sort(customers, "joined_desc"),
    do: Enum.sort_by(customers, & &1.inserted_at, {:desc, DateTime})

  def sort(customers, "joined_asc"),
    do: Enum.sort_by(customers, & &1.inserted_at, {:asc, DateTime})

  def sort(customers, "ltv_desc"),
    do: Enum.sort_by(customers, & &1.__lifetime_revenue__, :desc)

  def sort(customers, "last_wash_desc") do
    # Nil last-wash goes to the bottom; break ties by inserted_at desc.
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

  def sort(customers, "name_asc"),
    do: Enum.sort_by(customers, &String.downcase(&1.name || ""))

  def sort(customers, _), do: sort(customers, "joined_desc")

  # --- Ash / post filters ---

  defp ash_query(query, filters) do
    query
    |> maybe_filter_channel(filters[:channel_id] || "")
    |> maybe_filter_role(filters[:role] || "")
    |> maybe_filter_verified(filters[:verified] || "")
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

  defp filter_by_tag(customers, ""), do: customers
  defp filter_by_tag(customers, nil), do: customers

  defp filter_by_tag(customers, tag_id) do
    Enum.filter(customers, &(tag_id in &1.__tag_ids__))
  end

  # --- Aggregates (raw Ecto for small joined sums) ---

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

  defp tag_ids_by_customer([]), do: %{}

  defp tag_ids_by_customer(customer_ids) do
    uuids = Enum.map(customer_ids, &Ecto.UUID.dump!/1)

    query =
      from ct in "customer_tags",
        where: ct.customer_id in ^uuids,
        select: %{
          customer_id: type(ct.customer_id, Ecto.UUID),
          tag_id: type(ct.tag_id, Ecto.UUID)
        }

    query
    |> Repo.all()
    |> Enum.group_by(& &1.customer_id, & &1.tag_id)
  end

  defp to_int(nil), do: 0
  defp to_int(%Decimal{} = d), do: Decimal.to_integer(d)
  defp to_int(n) when is_integer(n), do: n
end
