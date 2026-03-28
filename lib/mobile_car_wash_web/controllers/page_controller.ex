defmodule MobileCarWashWeb.PageController do
  use MobileCarWashWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
