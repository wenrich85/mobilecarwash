defmodule MobileCarWashWeb.BookingSubscriptionPriceTest do
  @moduledoc """
  The live price hero must reflect subscription discounts so an active
  subscriber sees the amount they will actually be charged — not the
  pre-subscription price. A covered basic wash should read $0.00.

  async: false — sign-in writes a session token and the subscription rows
  must be visible to the spawned LiveView process (shared SQL sandbox).
  """
  use MobileCarWashWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  require Ash.Query

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Scheduling.ServiceType
  alias MobileCarWash.Fleet.Vehicle
  alias MobileCarWash.Billing.{SubscriptionPlan, Subscription}

  setup %{conn: conn} do
    {:ok, customer} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "sub-price-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Sub Price Test",
        phone: "+15125550000"
      })
      |> Ash.create()

    service =
      ServiceType
      |> Ash.Changeset.for_create(:create, %{
        name: "Basic Wash",
        slug: "basic_wash",
        description: "x",
        base_price_cents: 5_000,
        duration_minutes: 45
      })
      |> Ash.create!()

    car =
      Vehicle
      |> Ash.Changeset.for_create(:create, %{make: "Toyota", model: "Camry", year: 2021})
      |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
      |> Ash.Changeset.force_change_attribute(:size, :car)
      |> Ash.create!()

    plan =
      SubscriptionPlan
      |> Ash.Changeset.for_create(:create, %{
        name: "Basic Plan",
        slug: "basic_plan_#{System.unique_integer([:positive])}",
        price_cents: 9_000,
        basic_washes_per_month: 4,
        deep_cleans_per_month: 0,
        deep_clean_discount_percent: 25,
        description: "covers basic washes"
      })
      |> Ash.create!()

    Subscription
    |> Ash.Changeset.for_create(:create, %{status: :active})
    |> Ash.Changeset.force_change_attribute(:customer_id, customer.id)
    |> Ash.Changeset.force_change_attribute(:plan_id, plan.id)
    |> Ash.create!()

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

    %{conn: conn, service: service, car: car}
  end

  test "active subscriber sees the subscription-discounted total in the hero", %{
    conn: conn,
    car: car
  } do
    {:ok, view, _html} = live(conn, "/book")

    render_click(view, "select_service", %{"slug" => "basic_wash"})
    # Single page: the vehicle section is already unlocked; pick the saved car.
    html = render_click(view, "select_vehicle", %{"id" => car.id})

    # Covered basic wash on a car: full $50 base is discounted away → $0.00,
    # matching what create_booking would actually charge.
    assert html =~ "$0.00"
    refute html =~ "$50.00"
  end
end
