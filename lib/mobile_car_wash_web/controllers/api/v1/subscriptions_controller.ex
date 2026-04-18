defmodule MobileCarWashWeb.Api.V1.SubscriptionsController do
  @moduledoc """
  Subscription management for the mobile app: list the customer's
  subscriptions and pause / resume / cancel them. (Creation via the app is
  deferred — use Stripe Billing Portal or the web flow for initial signup.)
  """
  use MobileCarWashWeb, :controller

  alias MobileCarWash.Billing.Subscription

  require Ash.Query

  plug MobileCarWashWeb.Plugs.RequireApiAuth
  action_fallback MobileCarWashWeb.Api.V1.FallbackController

  def index(conn, _params) do
    customer = current_customer(conn)

    subs =
      Subscription
      |> Ash.Query.filter(customer_id == ^customer.id)
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.read!(actor: customer)
      |> Enum.map(&subscription_json/1)

    json(conn, %{data: subs})
  end

  def pause(conn, %{"id" => id}), do: transition(conn, id, :pause)
  def resume(conn, %{"id" => id}), do: transition(conn, id, :resume)
  def cancel(conn, %{"id" => id}), do: transition(conn, id, :cancel)

  defp transition(conn, id, action) do
    customer = current_customer(conn)

    with {:ok, sub} <- fetch_owned(id, customer),
         {:ok, updated} <-
           sub
           |> Ash.Changeset.for_update(action, %{})
           |> Ash.update() do
      json(conn, subscription_json(updated))
    end
  end

  defp fetch_owned(id, customer) do
    case Ash.get(Subscription, id, actor: customer) do
      {:ok, %{customer_id: cid} = sub} when cid == customer.id -> {:ok, sub}
      _ -> {:error, :not_found}
    end
  end

  defp subscription_json(s) do
    %{
      id: s.id,
      plan_id: s.plan_id,
      status: s.status,
      current_period_start: s.current_period_start,
      current_period_end: s.current_period_end,
      stripe_subscription_id: s.stripe_subscription_id
    }
  end

  defp current_customer(conn) do
    conn.assigns[:current_user] || conn.assigns[:current_customer]
  end
end
