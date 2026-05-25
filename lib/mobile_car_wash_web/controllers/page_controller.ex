defmodule MobileCarWashWeb.PageController do
  use MobileCarWashWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end

  def terms(conn, _params) do
    render(conn, :terms,
      page_title: "Terms of Service",
      canonical_path: "/terms",
      meta_description: "Terms of Service for Driveway Detail Co mobile car wash and detailing."
    )
  end
end
