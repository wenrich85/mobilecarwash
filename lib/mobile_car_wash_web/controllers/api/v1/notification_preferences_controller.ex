defmodule MobileCarWashWeb.Api.V1.NotificationPreferencesController do
  @moduledoc """
  Exposes per-channel opt-in booleans for the signed-in customer.

  Email is intentionally excluded — CAN-SPAM compliance is handled through
  unsubscribe links in the emails themselves, not a server-side preference.
  If that changes, add `email_opt_in` to `Customer` and expose it here.
  """
  use MobileCarWashWeb, :controller

  alias MobileCarWash.Accounts.Customer

  plug MobileCarWashWeb.Plugs.RequireApiAuth
  action_fallback MobileCarWashWeb.Api.V1.FallbackController

  def show(conn, _params) do
    customer = current_customer(conn)
    json(conn, %{data: preferences_json(customer)})
  end

  def update(conn, params) do
    customer = current_customer(conn)

    attrs =
      %{}
      |> maybe_put(:sms_opt_in, params["sms_opt_in"])
      |> maybe_put(:push_opt_in, params["push_opt_in"])

    with {:ok, updated} <-
           customer
           |> Ash.Changeset.for_update(:update, attrs)
           |> Ash.update(actor: customer) do
      json(conn, %{data: preferences_json(updated)})
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value) when is_boolean(value), do: Map.put(map, key, value)
  defp maybe_put(map, _key, _), do: map

  defp preferences_json(%Customer{} = c) do
    %{sms_opt_in: c.sms_opt_in, push_opt_in: c.push_opt_in}
  end

  defp current_customer(conn) do
    conn.assigns[:current_user] || conn.assigns[:current_customer]
  end
end
