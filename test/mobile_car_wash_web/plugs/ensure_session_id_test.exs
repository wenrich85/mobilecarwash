defmodule MobileCarWashWeb.Plugs.EnsureSessionIdTest do
  @moduledoc """
  Marketing Phase 2A / Slice 2: a stable session_id cookie that
  persists across requests. Every downstream feature (consent,
  attribution, behavior tracking) keys off this id.

  The cookie itself is essential (no consent needed) — same legal
  category as the Phoenix session cookie.
  """
  use MobileCarWashWeb.ConnCase, async: true

  alias MobileCarWashWeb.Plugs.EnsureSessionId

  defp run(conn) do
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> EnsureSessionId.call(EnsureSessionId.init([]))
  end

  test "generates a session_id when none exists", %{conn: conn} do
    conn = run(conn)

    sid = Plug.Conn.get_session(conn, :session_id)
    assert is_binary(sid)
    assert String.starts_with?(sid, "sess_")
  end

  test "re-uses an existing session_id from the session", %{conn: conn} do
    existing = "sess_prewired"

    conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{session_id: existing})
      |> EnsureSessionId.call(EnsureSessionId.init([]))

    assert Plug.Conn.get_session(conn, :session_id) == existing
  end

  test "also assigns :session_id on conn.assigns for the layout", %{conn: conn} do
    conn = run(conn)

    assert conn.assigns[:session_id] == Plug.Conn.get_session(conn, :session_id)
  end
end
