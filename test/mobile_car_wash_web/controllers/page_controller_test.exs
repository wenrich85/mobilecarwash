defmodule MobileCarWashWeb.PageControllerTest do
  use MobileCarWashWeb.ConnCase

  import Phoenix.LiveViewTest

  test "GET / renders landing page", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "Your car, washed where you parked it."
  end
end
