defmodule MobileCarWashWeb.AuthRedirectTest do
  use MobileCarWashWeb.ConnCase

  describe "Authentication redirects" do
    test "unauthenticated user trying to access /appointments redirects (302)", %{conn: conn} do
      conn = get(conn, "/appointments")
      assert conn.status == 302

      # Check that redirect goes to /auth/sign_in or similar
      location =
        Enum.find_value(conn.resp_headers, fn
          {"location", value} -> value
          _ -> nil
        end)

      assert location != nil, "Should redirect to a login page"
      IO.inspect(location, label: "Redirect location")
    end

    test "unauthenticated user trying to access /admin/metrics redirects (302)", %{conn: conn} do
      conn = get(conn, "/admin/metrics")
      assert conn.status == 302

      location =
        Enum.find_value(conn.resp_headers, fn
          {"location", value} -> value
          _ -> nil
        end)

      assert location != nil, "Should redirect to a login page"
      IO.inspect(location, label: "Admin redirect location")
    end

    test "unauthenticated user trying to access /tech/ redirects (302)", %{conn: conn} do
      conn = get(conn, "/tech/")
      assert conn.status == 302

      location =
        Enum.find_value(conn.resp_headers, fn
          {"location", value} -> value
          _ -> nil
        end)

      assert location != nil, "Should redirect to a login page"
      IO.inspect(location, label: "Tech redirect location")
    end

    test "/sign-in page is accessible (200)", %{conn: conn} do
      conn = get(conn, "/sign-in")
      assert conn.status == 200
      assert conn.resp_body =~ "Password"
    end
  end
end
