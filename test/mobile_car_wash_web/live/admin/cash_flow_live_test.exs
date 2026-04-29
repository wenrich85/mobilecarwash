defmodule MobileCarWashWeb.Admin.CashFlowLiveTest do
  @moduledoc """
  Character tests for the Cash Flow Dashboard at /admin/cash-flow.
  Locks in mount, action button labels, animation toggle, and
  modal-open events.
  """
  use MobileCarWashWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  require Ash.Query

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.CashFlow.Account, as: CashFlowAccount

  setup do
    # The Dashboard renders a SVG bucket diagram that pulls all 5
    # cash-flow accounts. Seed them up-front so the page mounts without
    # KeyError on @accounts.expense and friends.
    for attrs <- [
          %{account_type: :expense, name: "Expense Account", color: :blue},
          %{account_type: :tax, name: "Tax Account", color: :red},
          %{account_type: :business_savings, name: "Business Savings", color: :blue},
          %{account_type: :investment, name: "Investment Account", color: :blue},
          %{account_type: :personal_salary, name: "Personal Salary", color: :green}
        ] do
      existing =
        CashFlowAccount
        |> Ash.Query.filter(account_type == ^attrs.account_type)
        |> Ash.read!()

      if existing == [] do
        CashFlowAccount
        |> Ash.Changeset.for_create(:create, attrs)
        |> Ash.create!()
      end
    end

    :ok
  end

  defp register_admin! do
    {:ok, customer} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "admin-cash-flow-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Cash Flow Admin",
        phone: "+15125559400"
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
        email: "non-admin-cf-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Civilian CF",
        phone: "+15125559500"
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

      {:ok, _view, html} = live(conn, ~p"/admin/cash-flow")

      assert html =~ "Cash Flow"
    end

    test "non-admin is redirected", %{conn: conn} do
      customer = register_customer!()
      conn = sign_in(conn, customer)

      assert {:error, {:redirect, _}} = live(conn, ~p"/admin/cash-flow")
    end
  end

  describe "page content" do
    test "renders all 5 action button labels", %{conn: conn} do
      admin = register_admin!()
      conn = sign_in(conn, admin)

      {:ok, _view, html} = live(conn, ~p"/admin/cash-flow")

      # Tightened to match the actual rendered labels which include
      # leading sigils/emojis (Task 8 will strip these later).
      assert html =~ "+ Record Income"
      assert html =~ "- Record Expense"
      assert html =~ "↩ Rebalance to Expense"
      assert html =~ "💰 Pay Salary"
      assert html =~ "⚙️ Settings"
    end

    # TODO(plan4-task9): assert the Projections nav link href once the
    # brand band header is added in Task 9.
  end

  describe "events" do
    test "toggle_animations event does not crash the page", %{conn: conn} do
      admin = register_admin!()
      conn = sign_in(conn, admin)

      {:ok, view, _html} = live(conn, ~p"/admin/cash-flow")

      result = render_click(view, "toggle_animations")
      assert is_binary(result)
    end

    test "open_modal event for deposit does not crash the page", %{conn: conn} do
      admin = register_admin!()
      conn = sign_in(conn, admin)

      {:ok, view, _html} = live(conn, ~p"/admin/cash-flow")

      result = render_click(view, "open_modal", %{"modal" => "deposit"})
      assert is_binary(result)
    end
  end
end
