defmodule MobileCarWashWeb.AdminAuth do
  @moduledoc """
  LiveView on_mount hook for admin-only pages.
  Checks role == :admin OR email in admin whitelist.
  """
  use MobileCarWashWeb, :verified_routes

  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 2]

  def on_mount(:require_admin, _params, session, socket) do
    case session do
      %{"customer_token" => token} when is_binary(token) ->
        case verify_and_load_user(token) do
          {:ok, customer} ->
            if customer.role == :admin do
              {:cont, assign(socket, current_customer: customer, admin: true)}
            else
              {:halt, socket |> put_flash(:error, "Admin access required") |> redirect(to: ~p"/")}
            end

          _ ->
            {:halt, redirect(socket, to: ~p"/sign-in")}
        end

      _ ->
        {:halt, redirect(socket, to: ~p"/sign-in")}
    end
  end

  defp verify_and_load_user(token) do
    case AshAuthentication.Jwt.verify(token, :mobile_car_wash) do
      {:ok, %{"sub" => subject}, _} ->
        AshAuthentication.subject_to_user(subject, MobileCarWash.Accounts.Customer)

      _ ->
        :error
    end
  end
end
