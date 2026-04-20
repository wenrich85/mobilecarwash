defmodule MobileCarWash.Marketing.Personas do
  @moduledoc """
  Rule engine for Persona membership. Evaluates each Persona's
  `criteria` map against a Customer and the derived data we have
  about them (lifetime revenue, subscription, latest event metadata).

  Intentionally simple — a handful of hard-coded predicates keyed
  off strings in the criteria map. If this grows past ~6 predicates
  it's time for a proper DSL / query builder; for now, YAGNI.

  Supported predicates (all top-level keys in the criteria map):

    * "acquired_channel_slug"       — exact match (string)
    * "device_type"                 — exact match on latest event
    * "lifetime_revenue_cents"      — %{"gte" => n, "lte" => n}
    * "has_subscription"            — boolean

  Empty criteria `%{}` always matches (the "all customers" persona).
  """

  alias MobileCarWash.Marketing.{AcquisitionChannel, Persona, PersonaMembership}
  alias MobileCarWash.Repo

  import Ecto.Query
  require Ash.Query

  @doc """
  Returns `true` when `customer` satisfies every predicate in
  `persona.criteria`. AND semantics; any predicate returning false
  short-circuits the whole match.
  """
  @spec matches?(Persona.t(), map()) :: boolean()
  def matches?(%Persona{criteria: criteria}, customer) when is_map(criteria) do
    criteria
    |> Map.to_list()
    |> Enum.all?(fn {key, value} -> predicate(key, value, customer) end)
  end

  @doc """
  Recomputes auto-assigned persona memberships for a single customer.

  For each active Persona: if the customer matches AND a membership
  doesn't exist, create one (manually_assigned: false). Existing
  memberships (manual or auto) are never revoked — admin tags stick,
  and rule-engine tags stick until manually unassigned.
  """
  @spec assign_matching!(map()) :: :ok
  def assign_matching!(%{id: customer_id} = customer) do
    active_personas =
      Persona
      |> Ash.Query.for_read(:active)
      |> Ash.read!(authorize?: false)

    existing =
      PersonaMembership
      |> Ash.Query.for_read(:for_customer, %{customer_id: customer_id})
      |> Ash.read!(authorize?: false)
      |> MapSet.new(& &1.persona_id)

    Enum.each(active_personas, fn persona ->
      if matches?(persona, customer) and not MapSet.member?(existing, persona.id) do
        PersonaMembership
        |> Ash.Changeset.for_create(:assign, %{
          customer_id: customer_id,
          persona_id: persona.id,
          manually_assigned: false
        })
        |> Ash.create!(authorize?: false)
      end
    end)

    :ok
  end

  # --- Predicates ---

  defp predicate("acquired_channel_slug", expected, customer) when is_binary(expected) do
    case customer_channel_slug(customer) do
      nil -> false
      slug -> slug == expected
    end
  end

  defp predicate("device_type", expected, customer) when is_binary(expected) do
    case latest_device_type(customer) do
      nil -> false
      actual -> to_string(actual) == expected
    end
  end

  defp predicate("lifetime_revenue_cents", bounds, customer) when is_map(bounds) do
    revenue = lifetime_revenue_cents(customer)

    Enum.all?(bounds, fn
      {"gte", n} when is_integer(n) -> revenue >= n
      {"lte", n} when is_integer(n) -> revenue <= n
      _ -> true
    end)
  end

  defp predicate("has_subscription", expected, customer) when is_boolean(expected) do
    has_subscription?(customer) == expected
  end

  # Unknown predicate — fail-closed so misconfigured criteria don't
  # silently match every customer.
  defp predicate(_key, _value, _customer), do: false

  # --- Derived customer attributes ---

  defp customer_channel_slug(%{acquired_channel_id: nil}), do: nil

  defp customer_channel_slug(%{acquired_channel_id: channel_id}) do
    case Ash.get(AcquisitionChannel, channel_id, authorize?: false) do
      {:ok, chan} -> chan.slug
      _ -> nil
    end
  end

  defp customer_channel_slug(_), do: nil

  defp latest_device_type(%{id: customer_id}) do
    query =
      from e in "events",
        where: e.customer_id == type(^customer_id, Ecto.UUID),
        order_by: [desc: e.inserted_at],
        limit: 1,
        select: e.device_type

    case Repo.one(query) do
      nil -> nil
      "" -> nil
      device_type -> device_type
    end
  end

  defp latest_device_type(_), do: nil

  defp lifetime_revenue_cents(%{id: customer_id}) do
    query =
      from p in "payments",
        where: p.customer_id == type(^customer_id, Ecto.UUID),
        where: p.status == "succeeded",
        select: coalesce(sum(p.amount_cents), 0)

    case Repo.one(query) do
      nil -> 0
      %Decimal{} = d -> Decimal.to_integer(d)
      n when is_integer(n) -> n
    end
  end

  defp lifetime_revenue_cents(_), do: 0

  defp has_subscription?(%{id: customer_id}) do
    query =
      from s in "subscriptions",
        where: s.customer_id == type(^customer_id, Ecto.UUID),
        where: s.status == "active",
        select: count(s.id),
        limit: 1

    (Repo.one(query) || 0) > 0
  end

  defp has_subscription?(_), do: false
end
