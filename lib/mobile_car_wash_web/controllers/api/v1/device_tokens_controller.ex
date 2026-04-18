defmodule MobileCarWashWeb.Api.V1.DeviceTokensController do
  @moduledoc """
  APNs / FCM device-token registration for the mobile apps.

  `POST /api/v1/device_tokens` is idempotent — iOS reissues tokens after
  reinstalls and over time, and clients should call this on every
  `didRegisterForRemoteNotificationsWithDeviceToken` callback. The backing
  Ash action upserts on the token string.

  `DELETE /api/v1/device_tokens/:id` is called on explicit sign-out to
  deactivate the row. `AuthController.sign_out` also deactivates all of a
  customer's tokens as a backstop in case the client's DELETE fails.
  """
  use MobileCarWashWeb, :controller

  alias MobileCarWash.Notifications.DeviceToken

  plug MobileCarWashWeb.Plugs.RequireApiAuth
  action_fallback MobileCarWashWeb.Api.V1.FallbackController

  def create(conn, params) do
    customer = current_customer(conn)

    attrs = %{
      token: params["token"],
      platform: parse_platform(params["platform"]),
      app_version: params["app_version"],
      device_model: params["device_model"],
      customer_id: customer.id
    }

    with {:ok, token} <-
           DeviceToken
           |> Ash.Changeset.for_create(:register, attrs, actor: customer)
           |> Ash.create(actor: customer) do
      conn
      |> put_status(:created)
      |> json(%{data: token_json(token)})
    end
  end

  def delete(conn, %{"id" => id}) do
    customer = current_customer(conn)

    with {:ok, token} <- Ash.get(DeviceToken, id, actor: customer),
         {:ok, _} <-
           token
           |> Ash.Changeset.for_update(:deactivate, %{}, actor: customer)
           |> Ash.update(actor: customer) do
      json(conn, %{ok: true})
    else
      # Ash returns Forbidden when the policy filters the row out — from the
      # caller's point of view that's indistinguishable from "not found" and
      # leaks no ownership info.
      {:error, %Ash.Error.Forbidden{}} -> {:error, :not_found}
      {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Query.NotFound{} | _]}} -> {:error, :not_found}
      other -> other
    end
  end

  defp parse_platform(nil), do: :ios
  defp parse_platform("ios"), do: :ios
  defp parse_platform("android"), do: :android
  defp parse_platform(_), do: :ios

  defp token_json(t) do
    %{
      id: t.id,
      token: t.token,
      platform: to_string(t.platform),
      active: t.active,
      app_version: t.app_version,
      device_model: t.device_model,
      last_seen_at: t.last_seen_at
    }
  end

  defp current_customer(conn) do
    conn.assigns[:current_user] || conn.assigns[:current_customer]
  end
end
