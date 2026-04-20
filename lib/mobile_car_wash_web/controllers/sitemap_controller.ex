defmodule MobileCarWashWeb.SitemapController do
  @moduledoc """
  Dynamic XML sitemap. Built from a hard-coded list of public routes
  — safer than introspecting the router (which would leak admin /
  tech / auth paths into the sitemap) and easier to keep in sync.

  Search engines re-crawl this at their own schedule; we can add a
  `lastmod` per route if needed but YAGNI for now.
  """
  use MobileCarWashWeb, :controller

  @base_url "https://drivewaydetailcosa.com"

  # Paths that should be indexed. Admin / tech / auth / photo routes
  # are deliberately excluded.
  @public_paths [
    {"/", "daily", "1.0"},
    {"/book", "weekly", "0.9"},
    {"/subscribe", "weekly", "0.9"},
    {"/privacy", "yearly", "0.3"}
  ]

  def show(conn, _params) do
    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(200, build_xml())
  end

  defp build_xml do
    urls =
      Enum.map_join(@public_paths, "\n", fn {path, changefreq, priority} ->
        """
          <url>
            <loc>#{@base_url}#{path}</loc>
            <changefreq>#{changefreq}</changefreq>
            <priority>#{priority}</priority>
          </url>\
        """
      end)

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
    #{urls}
    </urlset>
    """
  end
end
