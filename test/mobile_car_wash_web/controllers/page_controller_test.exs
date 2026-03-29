defmodule MobileCarWashWeb.PageControllerTest do
  use MobileCarWashWeb.ConnCase

  import Phoenix.LiveViewTest

  test "GET / renders landing page", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "Professional Car Wash at Your Door"
  end
end
