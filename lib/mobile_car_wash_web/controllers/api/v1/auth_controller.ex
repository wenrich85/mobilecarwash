defmodule MobileCarWashWeb.Api.V1.AuthController do
  @moduledoc """
  Mobile-facing authentication. Register/sign-in return a JWT + customer
  JSON; sign-out revokes the token so future requests with it are rejected.
  """
  use MobileCarWashWeb, :controller

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWashWeb.Api.V1.CustomerJSON

  require Ash.Query

  action_fallback MobileCarWashWeb.Api.V1.FallbackController

  def register(conn, params) do
    attrs = %{
      email: params["email"],
      password: params["password"],
      password_confirmation: params["password_confirmation"] || params["password"],
      name: params["name"],
      phone: params["phone"]
    }

    case Customer
         |> Ash.Changeset.for_create(:register_with_password, attrs)
         |> Ash.create() do
      {:ok, customer} ->
        token = customer.__metadata__[:token]
        store_token(token)

        conn
        |> put_status(:created)
        |> json(%{token: token, customer: CustomerJSON.render(customer)})

      error ->
        error
    end
  end

  def sign_in(conn, %{"email" => email, "password" => password}) do
    case Customer
         |> Ash.Query.for_read(:sign_in_with_password, %{
           email: email,
           password: password
         })
         |> Ash.read_one() do
      {:ok, %{} = customer} ->
        token = customer.__metadata__[:token]
        store_token(token)

        json(conn, %{token: token, customer: CustomerJSON.render(customer)})

      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "invalid_credentials"})
    end
  end

  def sign_in(conn, _params) do
    conn
    |> put_status(:unauthorized)
    |> json(%{error: "invalid_credentials"})
  end

  def sign_out(conn, _params) do
    case conn.assigns[:current_user] || conn.assigns[:current_customer] do
      nil ->
        conn |> put_status(:unauthorized) |> json(%{error: "unauthorized"})

      _customer ->
        revoke_bearer_token(conn)
        json(conn, %{ok: true})
    end
  end

  # --- helpers ---

  defp store_token(nil), do: :ok

  defp store_token(token) do
    AshAuthentication.TokenResource.Actions.store_token(
      MobileCarWash.Accounts.Token,
      %{"token" => token, "purpose" => "user"},
      []
    )

    :ok
  end

  defp revoke_bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] ->
        AshAuthentication.TokenResource.Actions.revoke(
          MobileCarWash.Accounts.Token,
          token,
          []
        )

        :ok

      _ ->
        :ok
    end
  end
end
