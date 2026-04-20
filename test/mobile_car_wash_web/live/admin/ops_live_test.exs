defmodule MobileCarWashWeb.Admin.OpsLiveTest do
  @moduledoc """
  /admin/ops — owner-facing operational health dashboard.
  Shows per-queue Oban depths, recent job failures, and basic
  runtime info.
  """
  use MobileCarWashWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MobileCarWash.Accounts.Customer

  defp register_admin! do
    {:ok, customer} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "ops-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Ops Admin",
        phone: "+15125557600"
      })
      |> Ash.create()

    customer
    |> Ash.Changeset.for_update(:update, %{role: :admin})
    |> Ash.update!(authorize?: false)
  end

  defp sign_in(conn, customer) do
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> post("/auth/customer/password/sign_in", %{
      "customer" => %{
        "email" => to_string(customer.email),
        "password" => "Password123!"
      }
    })
    |> recycle()
  end

  test "anonymous is redirected", %{conn: conn} do
    conn = get(conn, ~p"/admin/ops")
    assert redirected_to(conn) == "/sign-in"
  end

  test "admin sees queue depths for every configured queue", %{conn: conn} do
    admin = register_admin!()
    conn = sign_in(conn, admin)

    {:ok, _lv, html} = live(conn, ~p"/admin/ops")

    # Headers
    assert html =~ "Operations"
    assert html =~ "Queue"

    # Every configured queue should render a row
    for q <- ~w(default notifications billing analytics maintenance ai) do
      assert html =~ q, "missing queue row: #{q}"
    end
  end

  test "admin sees runtime stats", %{conn: conn} do
    admin = register_admin!()
    conn = sign_in(conn, admin)

    {:ok, _lv, html} = live(conn, ~p"/admin/ops")

    assert html =~ "Uptime" or html =~ "uptime"
    assert html =~ "Memory" or html =~ "memory"
  end

  test "refresh button reloads stats", %{conn: conn} do
    admin = register_admin!()
    conn = sign_in(conn, admin)

    {:ok, lv, _} = live(conn, ~p"/admin/ops")

    html = lv |> element("#refresh-ops") |> render_click()
    assert html =~ "Operations"
  end
end
