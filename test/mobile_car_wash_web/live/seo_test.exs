defmodule MobileCarWashWeb.SeoTest do
  @moduledoc """
  SEO surface tests — LocalBusiness JSON-LD + per-route meta tags.
  These are what Google/Bing ingest for rich snippets and local-pack
  placement.
  """
  use MobileCarWashWeb.ConnCase, async: true

  describe "LocalBusiness JSON-LD on /" do
    test "includes the LocalBusiness schema with brand + geo info",
         %{conn: conn} do
      conn = get(conn, "/")
      html = html_response(conn, 200)

      assert html =~ ~s(<script type="application/ld+json")

      # Extract every JSON-LD block; at least one should be LocalBusiness
      [_head | _] =
        Regex.scan(
          ~r|<script type="application/ld\+json"[^>]*>(.*?)</script>|s,
          html
        )

      json =
        Regex.scan(~r|<script type="application/ld\+json"[^>]*>(.*?)</script>|s, html)
        |> Enum.map(fn [_, inner] -> inner end)
        |> Enum.map(&Jason.decode!/1)

      local_business =
        Enum.find(json, fn j -> j["@type"] in ["LocalBusiness", "AutoWash"] end)

      assert local_business != nil, "no LocalBusiness/AutoWash JSON-LD block on /"
      assert local_business["name"] =~ "Driveway Detail"
      assert local_business["address"]["addressRegion"] == "TX"
      assert local_business["address"]["addressLocality"] =~ "San Antonio"
      assert local_business["telephone"] != nil
      assert local_business["url"] =~ "drivewaydetailcosa.com"
    end
  end

  describe "per-route page titles" do
    test "/book has its own title + description", %{conn: conn} do
      conn = get(conn, "/book")
      html = html_response(conn, 200)

      # Title should mention booking, not just the default brand
      assert html =~ "Book" or html =~ "book"
    end

    test "/subscribe has its own title", %{conn: conn} do
      conn = get(conn, "/subscribe")
      html = html_response(conn, 200)
      assert html =~ "Subscri" or html =~ "Plan"
    end

    test "/privacy has its own title", %{conn: conn} do
      conn = get(conn, "/privacy")
      html = html_response(conn, 200)
      assert html =~ "Privacy"
    end
  end

  describe "canonical link" do
    test "homepage canonical resolves to the bare domain", %{conn: conn} do
      conn = get(conn, "/")
      html = html_response(conn, 200)

      assert html =~ ~s(<link rel="canonical" href="https://drivewaydetailcosa.com/")
    end
  end
end
