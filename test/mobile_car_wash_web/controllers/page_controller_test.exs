defmodule MobileCarWashWeb.PageControllerTest do
  use MobileCarWashWeb.ConnCase

  import Phoenix.LiveViewTest

  test "GET / renders landing page", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "Your car, washed where you parked it."
  end

  test "GET /terms returns terms page", %{conn: conn} do
    conn = get(conn, ~p"/terms")

    assert html_response(conn, 200) =~ "Terms"
  end
end
