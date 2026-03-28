defmodule MobileCarWashWeb.LiveAuth do
  @moduledoc """
  LiveView on_mount hooks for authentication.

  - `:maybe_load_customer` — loads the customer if authenticated, but doesn't redirect.
    Use for pages that work both authenticated and unauthenticated (landing, booking).
  - `:require_customer` — redirects to sign-in if not authenticated.
    Use for protected pages (dashboard, account settings).
  """
  use MobileCarWashWeb, :verified_routes

  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 2]

  def on_mount(:maybe_load_customer, _params, session, socket) do
    socket = assign(socket, current_customer: nil)

    case session do
      %{"customer_token" => token} when is_binary(token) ->
        case AshAuthentication.subject_to_user(token, MobileCarWash.Accounts.Customer) do
          {:ok, customer} ->
            {:cont, assign(socket, current_customer: customer)}

          _ ->
            {:cont, socket}
        end

      _ ->
        {:cont, socket}
    end
  end

  def on_mount(:require_customer, _params, session, socket) do
    socket = assign(socket, current_customer: nil)

    # In dev, allow unauthenticated access for easier testing
    if Application.get_env(:mobile_car_wash, :dev_routes) do
      {:cont, assign(socket, current_customer: load_first_customer())}
    else
      case session do
        %{"customer_token" => token} when is_binary(token) ->
          case AshAuthentication.subject_to_user(token, MobileCarWash.Accounts.Customer) do
            {:ok, customer} ->
              {:cont, assign(socket, current_customer: customer)}

            _ ->
              {:halt, redirect(socket, to: ~p"/sign-in")}
          end

        _ ->
          {:halt, redirect(socket, to: ~p"/sign-in")}
      end
    end
  end

  defp load_first_customer do
    case Ash.read!(MobileCarWash.Accounts.Customer) do
      [customer | _] -> customer
      [] -> nil
    end
  end
end
