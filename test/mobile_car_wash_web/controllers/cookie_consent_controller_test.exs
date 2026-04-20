defmodule MobileCarWashWeb.CookieConsentControllerTest do
  @moduledoc """
  Marketing Phase 2A / Slice 2: the banner POSTs here to record the
  visitor's choice.
  """
  use MobileCarWashWeb.ConnCase, async: false

  alias MobileCarWash.Analytics.CookieConsent

  test "POST /cookie-consent (accept_all) creates a full-opt-in row",
       %{conn: conn} do
    conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{session_id: "sess_ctrl_1"})
      |> post("/cookie-consent", %{"choice" => "accept_all"})

    assert redirected_to(conn) == "/"

    {:ok, [row]} =
      CookieConsent
      |> Ash.Query.for_read(:for_session, %{session_id: "sess_ctrl_1"})
      |> Ash.read(authorize?: false)

    assert row.analytics == true
    assert row.marketing == true
  end

  test "POST /cookie-consent (essential_only) creates an essential-only row",
       %{conn: conn} do
    conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{session_id: "sess_ctrl_2"})
      |> post("/cookie-consent", %{"choice" => "essential_only"})

    assert redirected_to(conn) == "/"

    {:ok, [row]} =
      CookieConsent
      |> Ash.Query.for_read(:for_session, %{session_id: "sess_ctrl_2"})
      |> Ash.read(authorize?: false)

    assert row.analytics == false
    assert row.marketing == false
  end

  test "POST /cookie-consent (custom) respects per-category flags",
       %{conn: conn} do
    conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{session_id: "sess_ctrl_3"})
      |> post("/cookie-consent", %{
        "choice" => "custom",
        "analytics" => "true",
        "marketing" => "false"
      })

    assert redirected_to(conn) == "/"

    {:ok, [row]} =
      CookieConsent
      |> Ash.Query.for_read(:for_session, %{session_id: "sess_ctrl_3"})
      |> Ash.read(authorize?: false)

    assert row.analytics == true
    assert row.marketing == false
  end

  test "redirects back to the referer when it's a same-host path",
       %{conn: conn} do
    conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{session_id: "sess_ctrl_4"})
      |> put_req_header("referer", "http://www.example.com/book")
      |> post("/cookie-consent", %{"choice" => "accept_all"})

    assert redirected_to(conn) == "/book"
  end

  test "hashes the client IP instead of storing it raw",
       %{conn: conn} do
    conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{session_id: "sess_ctrl_5"})
      |> post("/cookie-consent", %{"choice" => "accept_all"})

    {:ok, [row]} =
      CookieConsent
      |> Ash.Query.for_read(:for_session, %{session_id: "sess_ctrl_5"})
      |> Ash.read(authorize?: false)

    # ip_hash should be a hex-encoded SHA-256 digest (64 chars) — never
    # the raw dotted-quad.
    refute row.ip_hash =~ "."
    assert is_binary(row.ip_hash)
    assert String.length(row.ip_hash) == 64
  end
end
