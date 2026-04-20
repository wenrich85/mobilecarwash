defmodule MobileCarWashWeb.HealthControllerTest do
  @moduledoc """
  Liveness + readiness probes. DigitalOcean App Platform pings the
  live endpoint every 10s by default — a fast 200 here is the
  difference between a rolling deploy and a stuck deploy.
  """
  use MobileCarWashWeb.ConnCase, async: true

  describe "GET /health (liveness)" do
    test "returns 200 + JSON status=ok when the app is up", %{conn: conn} do
      conn = get(conn, "/health")

      assert conn.status == 200
      body = Jason.decode!(response(conn, 200))

      assert body["status"] == "ok"
      # Should include a version field for debugging rolling deploys
      assert is_binary(body["version"])
    end

    test "bypasses session / auth plugs — no cookie touched", %{conn: conn} do
      conn = get(conn, "/health")

      # Auth / attribution / session plugs should not have run.
      # The cheap way to verify that is that no Set-Cookie header
      # comes back — probes shouldn't accumulate sessions.
      assert get_resp_header(conn, "set-cookie") == []
    end
  end

  describe "GET /ready (readiness)" do
    test "returns 200 when DB is reachable", %{conn: conn} do
      conn = get(conn, "/ready")

      assert conn.status == 200
      body = Jason.decode!(response(conn, 200))

      assert body["status"] == "ready"
      assert body["checks"]["database"] == "ok"
    end
  end
end
