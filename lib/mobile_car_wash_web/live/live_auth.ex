defmodule MobileCarWashWeb.LiveAuth do
  @moduledoc """
  LiveView on_mount hooks for role-based authentication.

  - `:maybe_load_customer` — loads user if authenticated, no redirect
  - `:require_customer` — any authenticated user (customer, tech, admin)
  - `:require_technician` — technician or admin role only
  """
  use MobileCarWashWeb, :verified_routes

  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 2]

  def on_mount(:maybe_load_customer, _params, session, socket) do
    {:cont, assign(socket, current_customer: load_customer(session))}
  end

  def on_mount(:require_customer, _params, session, socket) do
    case load_customer(session) do
      nil -> {:halt, redirect(socket, to: ~p"/sign-in")}
      customer -> {:cont, assign(socket, current_customer: customer)}
    end
  end

  def on_mount(:require_technician, _params, session, socket) do
    case load_customer(session) do
      %{role: role} = customer when role in [:technician, :admin] ->
        {:cont, assign(socket, current_customer: customer)}

      nil ->
        {:halt, redirect(socket, to: ~p"/sign-in")}

      _ ->
        {:halt, socket |> put_flash(:error, "Technician access required") |> redirect(to: ~p"/")}
    end
  end

  defp load_customer(session) do
    case session do
      %{"customer_token" => token} when is_binary(token) ->
        case AshAuthentication.subject_to_user(token, MobileCarWash.Accounts.Customer) do
          {:ok, customer} -> customer
          _ -> nil
        end

      _ ->
        nil
    end
  end
end
