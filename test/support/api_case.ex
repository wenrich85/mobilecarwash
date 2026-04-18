defmodule MobileCarWashWeb.ApiCase do
  @moduledoc """
  Shared helpers for API v1 controller tests. Provides a fixture for
  creating a signed-in customer and a pre-authenticated conn.
  """
  use ExUnit.CaseTemplate

  using do
    quote do
      use MobileCarWashWeb.ConnCase, async: true
      import MobileCarWashWeb.ApiCase
    end
  end

  alias MobileCarWash.Accounts.Customer

  def register_and_sign_in(conn, opts \\ []) do
    email = opts[:email] || "api-case-#{:rand.uniform(100_000)}@example.com"
    name = opts[:name] || "API User"

    {:ok, customer} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: email,
        password: "Password123!",
        password_confirmation: "Password123!",
        name: name,
        phone: opts[:phone] || "+15125551000"
      })
      |> Ash.create()

    # Store the token so load_from_bearer accepts it.
    token = customer.__metadata__[:token]

    AshAuthentication.TokenResource.Actions.store_token(
      MobileCarWash.Accounts.Token,
      %{"token" => token, "purpose" => "user"},
      []
    )

    authed_conn =
      conn
      |> Phoenix.ConnTest.recycle()
      |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")

    {authed_conn, customer, token}
  end
end
