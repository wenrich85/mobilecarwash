defmodule MobileCarWashWeb.Plugs.RequireAdmin do
  @moduledoc """
  Controller-side counterpart to the `MobileCarWashWeb.AdminAuth`
  on_mount hook. LiveView routes in the `:admin` live_session are
  gated by the on_mount hook; plain controllers need a plug, hence
  this.

  Halts with:
    * redirect to `/sign-in` when no customer is loaded on the session
    * redirect to `/` with an error flash when the customer is signed
      in but lacks `:admin` role
  """
  import Plug.Conn
  import Phoenix.Controller

  use MobileCarWashWeb, :verified_routes

  def init(opts), do: opts

  def call(conn, _opts) do
    case conn.assigns[:current_user] || conn.assigns[:current_customer] do
      %{role: :admin} ->
        conn

      %{} ->
        conn
        |> put_flash(:error, "Admin access required")
        |> redirect(to: ~p"/")
        |> halt()

      _ ->
        conn
        |> redirect(to: ~p"/sign-in")
        |> halt()
    end
  end
end
