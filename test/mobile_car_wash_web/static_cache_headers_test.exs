defmodule MobileCarWashWeb.StaticCacheHeadersTest do
  @moduledoc """
  Verifies cache-control headers are set on static assets for browser/CDN caching.
  PageSpeed flagged /images/*.svg as having no cache TTL.
  """
  use MobileCarWashWeb.ConnCase, async: true

  describe "cache-control headers on static assets" do
    test "hashed /assets/* files are served immutable for 1 year", %{conn: conn} do
      conn = get(conn, "/assets/css/app.css")

      assert conn.status == 200
      cache = get_resp_header(conn, "cache-control") |> List.first()
      assert cache =~ "max-age=31536000"
      assert cache =~ "immutable"
    end

    test "SVG images under /images/* are cached for at least 7 days", %{conn: conn} do
      conn = get(conn, "/images/logo_light.svg")

      assert conn.status == 200
      cache = get_resp_header(conn, "cache-control") |> List.first()
      assert cache, "expected cache-control header on /images/*.svg"
      assert cache =~ ~r/max-age=(\d+)/

      [_, seconds] = Regex.run(~r/max-age=(\d+)/, cache)
      assert String.to_integer(seconds) >= 604_800
    end

    test "favicon.ico is cached", %{conn: conn} do
      conn = get(conn, "/favicon.ico")

      assert conn.status == 200
      cache = get_resp_header(conn, "cache-control") |> List.first()
      assert cache, "expected cache-control header on /favicon.ico"
    end

    test "dynamic routes are NOT given long-cache headers", %{conn: conn} do
      conn = get(conn, "/")

      cache = get_resp_header(conn, "cache-control") |> List.first() || ""
      refute cache =~ "immutable"
      refute cache =~ "max-age=31536000"
    end
  end
end
