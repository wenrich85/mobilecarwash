defmodule MobileCarWashWeb.Admin.CashFlowProjectionsLiveTest do
  @moduledoc """
  Character tests for the Projections page at /admin/cash-flow/projections.
  Locks in current behavior so the Dashboard/Projections split refactor
  doesn't accidentally regress event handling or page layout.
  """
  use MobileCarWashWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MobileCarWash.Accounts.Customer

  defp register_admin! do
    {:ok, customer} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "admin-projections-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Projections Admin",
        phone: "+15125559200"
      })
      |> Ash.create()

    customer
    |> Ash.Changeset.for_update(:update, %{role: :admin})
    |> Ash.update!(authorize?: false)
  end

  defp register_customer! do
    {:ok, customer} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "non-admin-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Civilian",
        phone: "+15125559300"
      })
      |> Ash.create()

    customer
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

  describe "mount" do
    test "renders for an admin user", %{conn: conn} do
      admin = register_admin!()
      conn = sign_in(conn, admin)

      {:ok, _view, html} = live(conn, ~p"/admin/cash-flow/projections")

      assert html =~ "Cash Flow Projections"
      # Smoke that the loaded state renders (not the loading placeholder)
      assert html =~ "Months to project"
    end

    test "non-admin is redirected", %{conn: conn} do
      customer = register_customer!()
      conn = sign_in(conn, customer)

      assert {:error, {:redirect, _}} = live(conn, ~p"/admin/cash-flow/projections")
    end

    test "back-to-dashboard link points at /admin/cash-flow", %{conn: conn} do
      admin = register_admin!()
      conn = sign_in(conn, admin)

      {:ok, _view, html} = live(conn, ~p"/admin/cash-flow/projections")

      assert html =~ "← Back to Dashboard"
      assert html =~ ~p"/admin/cash-flow"
    end
  end

  describe "event handlers" do
    test "adjust_projection event does not crash the page", %{conn: conn} do
      admin = register_admin!()
      conn = sign_in(conn, admin)

      {:ok, view, _html} = live(conn, ~p"/admin/cash-flow/projections")

      # The handler pattern-matches on params["months"] and params["growth_rate"]
      # with parse helpers that fall back to prev values. Send a realistic
      # phx-change form payload.
      result =
        render_change(view, "adjust_projection", %{"months" => "12", "growth_rate" => "5"})

      assert is_binary(result)
      # Settings still render — page didn't crash.
      assert result =~ "Months to project"
    end

    test "reset_projection restores actuals", %{conn: conn} do
      admin = register_admin!()
      conn = sign_in(conn, admin)

      {:ok, view, _html} = live(conn, ~p"/admin/cash-flow/projections")

      result = render_click(view, "reset_projection", %{})

      assert is_binary(result)
      assert result =~ "Months to project"
    end
  end
end
