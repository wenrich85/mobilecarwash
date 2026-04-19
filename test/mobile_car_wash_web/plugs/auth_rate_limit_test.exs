defmodule MobileCarWashWeb.Plugs.AuthRateLimitTest do
  @moduledoc """
  SECURITY_AUDIT_REPORT HIGH #3: rate limiting only applies to the
  sign-in LiveView mount. The actual POST endpoints used for password
  sign-in and registration (both the LiveView /auth/... macro-generated
  routes and the API /api/v1/auth/* ones) were unrestricted, leaving
  them open to credential-stuffing.

  These tests pin the new AuthRateLimit plug: each auth-sensitive POST
  path gets its own per-IP bucket. The 11th request within the window
  returns 429 regardless of which endpoint we hit.

  Uses the ETS-backed `:rate_limit_buckets` table (shared with the
  other rate limiters), so the setup clears it before each test.
  """
  use MobileCarWashWeb.ConnCase, async: false

  setup do
    # Clear the shared bucket table so tests don't cross-contaminate.
    if :ets.whereis(:rate_limit_buckets) != :undefined do
      :ets.delete_all_objects(:rate_limit_buckets)
    end

    :ok
  end

  describe "API /api/v1/auth/sign_in" do
    test "the 11th bad sign-in from the same IP inside the window gets 429",
         %{conn: conn} do
      payload = %{email: "nobody@test.com", password: "Wrong123!"}

      # 10 failed attempts — each returns 401 (unauthenticated) but the
      # rate limiter is tallying.
      for _ <- 1..10 do
        resp = post(conn, ~p"/api/v1/auth/sign_in", payload)
        assert resp.status in [200, 400, 401, 422]
      end

      # 11th attempt: the plug fires, short-circuits with 429.
      resp = post(conn, ~p"/api/v1/auth/sign_in", payload)
      assert resp.status == 429
    end

    test "GET requests to the same path are NOT rate-limited",
         %{conn: conn} do
      # 20 GETs shouldn't trip anything.
      for _ <- 1..20 do
        conn = get(conn, ~p"/api/v1/auth/sign_in")
        refute conn.status == 429
      end
    end
  end

  describe "API /api/v1/auth/register" do
    test "also gets its own 10-per-minute bucket",
         %{conn: conn} do
      payload = %{
        email: "unique-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Rate Limit",
        phone: "+15125559000"
      }

      for _ <- 1..10 do
        post(conn, ~p"/api/v1/auth/register", payload)
      end

      resp = post(conn, ~p"/api/v1/auth/register", payload)
      assert resp.status == 429
    end
  end

  describe "non-auth paths" do
    test "are unaffected by the auth rate limiter", %{conn: conn} do
      # 15 GETs to a public page — well over the auth bucket limit.
      for _ <- 1..15 do
        conn = get(conn, ~p"/api/v1/services")
        refute conn.status == 429
      end
    end
  end
end
