defmodule MobileCarWashWeb.Admin.DispatchLiveCommandCenterTest do
  use MobileCarWashWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  require Ash.Query

  alias MobileCarWash.Accounts.Customer

  defp create_admin do
    {:ok, admin} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "admin-command-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Command Admin",
        phone: "+15125550301"
      })
      |> Ash.create()

    admin
    |> Ash.Changeset.for_update(:update, %{role: :admin})
    |> Ash.update!(authorize?: false)
  end

  defp sign_in(conn, user) do
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> post("/auth/customer/password/sign_in", %{
      "customer" => %{
        "email" => to_string(user.email),
        "password" => "Password123!"
      }
    })
    |> recycle()
  end

  test "admin dispatch renders command center regions", %{conn: conn} do
    conn = conn |> sign_in(create_admin())

    {:ok, view, _html} = live(conn, ~p"/admin/dispatch")

    assert has_element?(view, "#dispatch-command-bar")
    assert has_element?(view, "#dispatch-metrics")
    assert has_element?(view, "#dispatch-exceptions")
    assert has_element?(view, "#dispatch-assignment-queue")
    assert has_element?(view, "#dispatch-technician-workload")
    assert has_element?(view, "#dispatch-map")
  end
end
