defmodule MobileCarWashWeb.Plugs.RequireTechAuth do
  @moduledoc """
  Plug for tech-facing API routes under `/api/v1/tech/*`. Requires a valid
  JWT (via `load_from_bearer`) AND that the signed-in customer's role is
  `:technician` or `:admin`.

  - 401 JSON when no token or token rejected.
  - 403 JSON when signed in but role is `:customer` / `:guest`.
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

      %{role: role} when role in [:technician, :admin] ->
        conn

      _ ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "forbidden", message: "Technician role required"})
        |> halt()
    end
  end
end
