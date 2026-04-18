defmodule MobileCarWash.Billing.Changes.SyncStripeCatalog do
  @moduledoc """
  Ash change that keeps a resource (ServiceType, SubscriptionPlan) in sync
  with Stripe's Products & Prices catalog.

  On create: creates a Stripe Product + Price and stores the IDs.
  On update:
    - name/description change → updates the Stripe Product in place
    - price change → archives the old Price and creates a new one
      (Stripe Prices are immutable on amount)
    - active flipped to false → archives both Product and Price

  Options:
    * `:price_attribute` — the attribute holding the price in cents
      (`:base_price_cents` for ServiceType, `:price_cents` for SubscriptionPlan)
    * `:recurring` — true for subscription plans (monthly price), false for one-time
  """
  use Ash.Resource.Change

  alias MobileCarWash.Billing.StripeClient

  @impl true
  def change(changeset, opts, _context) do
    price_attr = Keyword.fetch!(opts, :price_attribute)
    recurring? = Keyword.get(opts, :recurring, false)

    case changeset.action.type do
      :create -> handle_create(changeset, price_attr, recurring?)
      :update -> handle_update(changeset, price_attr, recurring?)
      _ -> changeset
    end
  end

  defp handle_create(changeset, price_attr, recurring?) do
    name = Ash.Changeset.get_attribute(changeset, :name)
    description = Ash.Changeset.get_attribute(changeset, :description)
    price_cents = Ash.Changeset.get_attribute(changeset, price_attr)

    with {:ok, %{id: product_id}} <-
           StripeClient.create_product(compact(%{name: name, description: description})),
         {:ok, %{id: price_id}} <-
           StripeClient.create_price(price_params(product_id, price_cents, recurring?)) do
      changeset
      |> Ash.Changeset.force_change_attribute(:stripe_product_id, product_id)
      |> Ash.Changeset.force_change_attribute(:stripe_price_id, price_id)
    else
      {:error, reason} ->
        Ash.Changeset.add_error(changeset, field: :stripe_product_id, message: inspect(reason))
    end
  end

  defp handle_update(changeset, price_attr, recurring?) do
    product_id = changeset.data.stripe_product_id
    old_price_id = changeset.data.stripe_price_id

    changeset
    |> maybe_update_product(product_id)
    |> maybe_rotate_price(product_id, old_price_id, price_attr, recurring?)
    |> maybe_archive(product_id, old_price_id)
  end

  defp maybe_update_product(changeset, nil), do: changeset

  defp maybe_update_product(changeset, product_id) do
    updates =
      %{}
      |> put_if_changing(changeset, :name)
      |> put_if_changing(changeset, :description)

    if map_size(updates) == 0 do
      changeset
    else
      case StripeClient.update_product(product_id, updates) do
        {:ok, _} ->
          changeset

        {:error, reason} ->
          Ash.Changeset.add_error(changeset, field: :stripe_product_id, message: inspect(reason))
      end
    end
  end

  defp maybe_rotate_price(changeset, _product_id, _old_price_id, price_attr, _recurring?)
       when is_nil(price_attr),
       do: changeset

  defp maybe_rotate_price(changeset, product_id, old_price_id, price_attr, recurring?) do
    cond do
      not Ash.Changeset.changing_attribute?(changeset, price_attr) ->
        changeset

      is_nil(product_id) ->
        changeset

      true ->
        new_amount = Ash.Changeset.get_attribute(changeset, price_attr)

        with {:ok, _} <- StripeClient.archive_price(old_price_id),
             {:ok, %{id: new_price_id}} <-
               StripeClient.create_price(price_params(product_id, new_amount, recurring?)) do
          Ash.Changeset.force_change_attribute(changeset, :stripe_price_id, new_price_id)
        else
          {:error, reason} ->
            Ash.Changeset.add_error(changeset,
              field: :stripe_price_id,
              message: inspect(reason)
            )
        end
    end
  end

  defp maybe_archive(changeset, product_id, price_id) do
    cond do
      not Ash.Changeset.changing_attribute?(changeset, :active) ->
        changeset

      Ash.Changeset.get_attribute(changeset, :active) != false ->
        changeset

      is_nil(product_id) ->
        changeset

      true ->
        _ = StripeClient.archive_product(product_id)
        if price_id, do: StripeClient.archive_price(price_id)
        changeset
    end
  end

  defp price_params(product_id, amount, recurring?) do
    base = %{product: product_id, unit_amount: amount, currency: "usd"}
    if recurring?, do: Map.put(base, :recurring, %{interval: "month"}), else: base
  end

  defp put_if_changing(map, changeset, attr) do
    if Ash.Changeset.changing_attribute?(changeset, attr) do
      Map.put(map, attr, Ash.Changeset.get_attribute(changeset, attr))
    else
      map
    end
  end

  defp compact(map) do
    Map.reject(map, fn {_k, v} -> is_nil(v) end)
  end
end
