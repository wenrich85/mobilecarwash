defmodule MobileCarWashWeb.SitemapControllerTest do
  @moduledoc """
  Dynamic /sitemap.xml — built from the router so new public routes
  get indexed automatically.
  """
  use MobileCarWashWeb.ConnCase, async: true

  test "GET /sitemap.xml returns a valid XML sitemap", %{conn: conn} do
    conn = get(conn, "/sitemap.xml")

    assert response_content_type(conn, :xml) =~ "xml"
    xml = response(conn, 200)

    # XML declaration + urlset root element
    assert xml =~ ~s(<?xml version="1.0" encoding="UTF-8"?>)
    assert xml =~ ~s(<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">)

    # Every public route should appear as a <loc>
    for path <- ~w(/ /book /subscribe /privacy) do
      url =
        case path do
          "/" -> "https://drivewaydetailcosa.com/"
          other -> "https://drivewaydetailcosa.com" <> other
        end

      assert xml =~ "<loc>#{url}</loc>",
             "sitemap missing <loc> for #{url}"
    end

    # Admin / tech / auth / dev must NEVER appear
    refute xml =~ "/admin"
    refute xml =~ "/tech"
    refute xml =~ "/auth"
    refute xml =~ "/dev"
  end

  test "GET /sitemap.xml sets the proper content type", %{conn: conn} do
    conn = get(conn, "/sitemap.xml")
    [ct | _] = get_resp_header(conn, "content-type")
    assert String.starts_with?(ct, "application/xml") or String.starts_with?(ct, "text/xml")
  end
end
