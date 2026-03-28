defmodule MobileCarWashWeb.AdminAuth do
  @moduledoc """
  LiveView on_mount hook for admin-only pages.
  Checks that the authenticated customer's email is in the admin whitelist.

  Configure admin emails in config:

      config :mobile_car_wash, :admin_emails, ["owner@example.com"]
  """
  use MobileCarWashWeb, :verified_routes

  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 2]

  def on_mount(:require_admin, _params, session, socket) do
    admin_emails = Application.get_env(:mobile_car_wash, :admin_emails, [])

    case session do
      %{"customer_token" => token} when is_binary(token) ->
        case AshAuthentication.subject_to_user(token, MobileCarWash.Accounts.Customer) do
          {:ok, customer} ->
            email = to_string(customer.email)

            if email in admin_emails do
              {:cont, assign(socket, current_customer: customer, admin: true)}
            else
              {:halt, socket |> put_flash(:error, "Unauthorized") |> redirect(to: ~p"/")}
            end

          _ ->
            {:halt, redirect(socket, to: ~p"/sign-in")}
        end

      _ ->
        {:halt, redirect(socket, to: ~p"/sign-in")}
    end
  end
end
