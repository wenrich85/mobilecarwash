defmodule MobileCarWashWeb.Plugs.RequireApiAuth do
  @moduledoc """
  Plug for protected API v1 routes. Requires that `load_from_bearer` has
  populated `:current_user` or `:current_customer` in the conn. Responds with
  401 JSON otherwise.
  """
  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  def init(opts), do: opts

  def call(conn, _opts) do
    case conn.assigns[:current_user] || conn.assigns[:current_customer] do
      nil ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "unauthorized"})
        |> halt()

      _customer ->
        conn
    end
  end
end
