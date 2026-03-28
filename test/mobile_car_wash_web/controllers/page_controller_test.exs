defmodule MobileCarWashWeb.PageControllerTest do
  use MobileCarWashWeb.ConnCase

  test "GET / renders landing page", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Professional Car Wash at Your Door"
  end
end
