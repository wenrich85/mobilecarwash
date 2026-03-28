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
