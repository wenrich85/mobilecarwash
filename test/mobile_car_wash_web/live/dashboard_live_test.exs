defmodule MobileCarWashWeb.DashboardLiveTest do
  use MobileCarWashWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MobileCarWash.Billing.{Subscription, SubscriptionPlan}

  require Ash.Query

  # Builds a registered customer and signs them in. Returns {conn, customer}.
  defp register_and_sign_in(conn) do
    {:ok, customer} =
      MobileCarWash.Accounts.Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "dash-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Dash Test",
        phone: "+15125550000"
      })
      |> Ash.create()

    conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> post("/auth/customer/password/sign_in", %{
        "customer" => %{
          "email" => to_string(customer.email),
          "password" => "Password123!"
        }
      })
      |> recycle()

    {conn, customer}
  end

  defp create_plan do
    SubscriptionPlan
    |> Ash.Changeset.for_create(:create, %{
      name: "Standard Plan",
      slug: "dash_plan_#{System.unique_integer([:positive])}",
      price_cents: 12_500,
      basic_washes_per_month: 4,
      deep_cleans_per_month: 0,
      deep_clean_discount_percent: 30,
      description: "dashboard test plan"
    })
    |> Ash.create!()
  end

  defp create_active_subscription(customer, plan) do
    Subscription
    |> Ash.Changeset.for_create(:create, %{status: :active})
    |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
    |> Ash.Changeset.force_change_attribute(:plan_id, plan.id)
    |> Ash.create!()
  end

  test "unauthenticated user is redirected to sign-in" do
    conn = build_conn()
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/dashboard")
  end

  test "subscriber-less customer is redirected to /subscribe", %{conn: conn} do
    {conn, _customer} = register_and_sign_in(conn)
    assert {:error, {:redirect, %{to: "/subscribe"}}} = live(conn, ~p"/dashboard")
  end

  test "active subscriber sees the dashboard with plan name and usage", %{conn: conn} do
    {conn, customer} = register_and_sign_in(conn)
    plan = create_plan()
    create_active_subscription(customer, plan)

    {:ok, _view, html} = live(conn, ~p"/dashboard")

    assert html =~ "Your Dashboard"
    assert html =~ "Standard Plan"
    assert html =~ "Basic Washes"
  end
end
