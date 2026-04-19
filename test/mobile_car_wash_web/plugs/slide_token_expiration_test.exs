defmodule MobileCarWashWeb.Plugs.SlideTokenExpirationTest do
  @moduledoc """
  SECURITY_AUDIT_REPORT MEDIUM #5: tokens issued at sign-in expired
  after 7 days with no rotation. If a token leaked, the attacker had
  up to 7 days and the user's next sign-in extended nothing — they
  just accumulated more live tokens. Active users also got abruptly
  booted on day 7.

  SlideTokenExpiration plug runs after the session / bearer auth step.
  If the signed-in user's current token has less than the configured
  threshold remaining (default 48 hours of a 7-day life), the plug
  mints a fresh 7-day token and:

    * sets it on the response as `x-refresh-token` for API callers
    * writes it into the session for browser callers

  The old token is left alone — it expires naturally. That avoids
  race conditions with in-flight concurrent requests carrying the
  same token and keeps rotation "soft".

  Tests drive the plug directly through Plug.Conn since the behaviour
  depends on the token's exp claim, which is easier to stub than to
  time-travel around.
  """
  use MobileCarWashWeb.ConnCase, async: true

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWashWeb.Plugs.SlideTokenExpiration

  defp register_customer do
    {:ok, customer} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "slide-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Slide Test",
        phone: "+15125552000"
      })
      |> Ash.create()

    customer
  end

  defp sign_token_with_remaining(customer, seconds_remaining) do
    secret = Application.fetch_env!(:mobile_car_wash, :token_signing_secret)
    signer = Joken.Signer.create("HS256", secret)

    now = System.system_time(:second)
    iat = now - 60
    exp = now + seconds_remaining

    claims = %{
      "sub" => AshAuthentication.user_to_subject(customer),
      "iat" => iat,
      "nbf" => iat,
      "exp" => exp,
      "jti" => Ecto.UUID.generate(),
      "aud" => "~> 2.0",
      "iss" => "AshAuthentication v#{Application.spec(:ash_authentication, :vsn)}",
      "purpose" => "user"
    }

    {:ok, token, _} = Joken.generate_and_sign(%{}, claims, signer)
    token
  end

  describe "when no user is assigned to the conn" do
    test "does nothing", %{conn: conn} do
      conn = SlideTokenExpiration.call(conn, SlideTokenExpiration.init([]))
      assert get_resp_header(conn, "x-refresh-token") == []
    end
  end

  describe "when the user's token is fresh (> threshold remaining)" do
    test "does NOT attach a refresh header", %{conn: conn} do
      customer = register_customer()
      # 7 days in seconds — well above the 48h default threshold
      token = sign_token_with_remaining(customer, 7 * 24 * 3600)

      conn =
        conn
        |> assign(:current_customer, customer)
        |> put_req_header("authorization", "Bearer #{token}")

      conn = SlideTokenExpiration.call(conn, SlideTokenExpiration.init([]))

      assert get_resp_header(conn, "x-refresh-token") == []
    end
  end

  describe "when the user's token is close to expiry" do
    test "attaches a fresh valid token via x-refresh-token header",
         %{conn: conn} do
      customer = register_customer()
      # 1 hour remaining — well under 48h threshold
      token = sign_token_with_remaining(customer, 3600)

      conn =
        conn
        |> assign(:current_customer, customer)
        |> put_req_header("authorization", "Bearer #{token}")

      conn = SlideTokenExpiration.call(conn, SlideTokenExpiration.init([]))

      [new_token] = get_resp_header(conn, "x-refresh-token")
      refute new_token == token

      # The new token verifies and resolves to the same customer
      assert {:ok, %{"sub" => sub}, _} =
               AshAuthentication.Jwt.verify(new_token, :mobile_car_wash)

      assert sub == AshAuthentication.user_to_subject(customer)
    end

    test "also updates the web session so LiveView picks it up",
         %{conn: conn} do
      customer = register_customer()
      old_token = sign_token_with_remaining(customer, 3600)

      conn =
        conn
        |> Phoenix.ConnTest.init_test_session(%{"customer_token" => old_token})
        |> assign(:current_customer, customer)

      conn = SlideTokenExpiration.call(conn, SlideTokenExpiration.init([]))

      refreshed = get_session(conn, "customer_token")
      refute refreshed == old_token
      refute is_nil(refreshed)
    end
  end
end
