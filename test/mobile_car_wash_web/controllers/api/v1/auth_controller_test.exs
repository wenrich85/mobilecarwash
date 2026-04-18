defmodule MobileCarWashWeb.Api.V1.AuthControllerTest do
  @moduledoc """
  Tests for the mobile-facing auth API. Registration and sign-in return a
  bearer JWT token + customer JSON that the mobile app stores and sends on
  subsequent requests.
  """
  use MobileCarWashWeb.ConnCase, async: true

  alias MobileCarWash.Accounts.Customer

  defp create_customer(email) do
    Customer
    |> Ash.Changeset.for_create(:register_with_password, %{
      email: email,
      password: "Password123!",
      password_confirmation: "Password123!",
      name: "Test User",
      phone: "+15125551212"
    })
    |> Ash.create!()
  end

  describe "POST /api/v1/auth/register" do
    test "creates a customer and returns {token, customer}", %{conn: conn} do
      email = "api-reg-#{:rand.uniform(100_000)}@example.com"

      conn =
        post(conn, ~p"/api/v1/auth/register", %{
          email: email,
          password: "Password123!",
          password_confirmation: "Password123!",
          name: "API User",
          phone: "+15125552222"
        })

      body = json_response(conn, 201)

      assert is_binary(body["token"])
      assert String.length(body["token"]) > 20
      assert body["customer"]["email"] == email
      assert body["customer"]["name"] == "API User"
      assert body["customer"]["id"]
      refute Map.has_key?(body["customer"], "hashed_password")
    end

    test "returns 422 when password is too short", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v1/auth/register", %{
          email: "bad-#{:rand.uniform(100_000)}@example.com",
          password: "x",
          password_confirmation: "x",
          name: "Short Pwd"
        })

      assert %{"error" => _} = json_response(conn, 422)
    end

    test "returns 422 when email is already taken", %{conn: conn} do
      email = "dup-#{:rand.uniform(100_000)}@example.com"
      create_customer(email)

      conn =
        post(conn, ~p"/api/v1/auth/register", %{
          email: email,
          password: "Password123!",
          password_confirmation: "Password123!",
          name: "Dup"
        })

      assert %{"error" => _} = json_response(conn, 422)
    end
  end

  describe "POST /api/v1/auth/sign_in" do
    test "returns {token, customer} on valid credentials", %{conn: conn} do
      email = "signin-#{:rand.uniform(100_000)}@example.com"
      create_customer(email)

      conn =
        post(conn, ~p"/api/v1/auth/sign_in", %{
          email: email,
          password: "Password123!"
        })

      body = json_response(conn, 200)

      assert is_binary(body["token"])
      assert body["customer"]["email"] == email
    end

    test "returns 401 on invalid password", %{conn: conn} do
      email = "wrongpw-#{:rand.uniform(100_000)}@example.com"
      create_customer(email)

      conn =
        post(conn, ~p"/api/v1/auth/sign_in", %{
          email: email,
          password: "WrongPassword!"
        })

      assert %{"error" => _} = json_response(conn, 401)
    end

    test "returns 401 on unknown email", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v1/auth/sign_in", %{
          email: "nobody-#{:rand.uniform(100_000)}@example.com",
          password: "Password123!"
        })

      assert %{"error" => _} = json_response(conn, 401)
    end
  end

  describe "POST /api/v1/auth/sign_out" do
    test "requires authentication — returns 401 without token", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/auth/sign_out")
      assert json_response(conn, 401)
    end

    test "revokes the current token when signed in", %{conn: conn} do
      email = "signout-#{:rand.uniform(100_000)}@example.com"
      create_customer(email)

      signin =
        post(conn, ~p"/api/v1/auth/sign_in", %{
          email: email,
          password: "Password123!"
        })

      token = json_response(signin, 200)["token"]

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> post(~p"/api/v1/auth/sign_out")

      assert json_response(conn, 200) == %{"ok" => true}
    end
  end
end
