defmodule MobileCarWashWeb.Admin.DashboardLiveTest do
  @moduledoc """
  Tests for the admin hub landing page at /admin.
  """
  use MobileCarWashWeb.ConnCase, async: true

  describe "auth guard" do
    test "non-authenticated user is redirected to sign-in", %{conn: conn} do
      conn = get(conn, ~p"/admin")
      assert redirected_to(conn) == "/sign-in"
    end
  end
end
