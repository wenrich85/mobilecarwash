defmodule MobileCarWashWeb.Api.V1.SubscriptionsControllerTest do
  use MobileCarWashWeb.ApiCase

  alias MobileCarWash.Billing.{Subscription, SubscriptionPlan}

  defp create_plan do
    SubscriptionPlan
    |> Ash.Changeset.for_create(:create, %{
      name: "API Basic",
      slug: "api_basic_#{:rand.uniform(100_000)}",
      price_cents: 9000,
      basic_washes_per_month: 2
    })
    |> Ash.create!()
  end

  defp create_subscription(customer_id, plan_id) do
    Subscription
    |> Ash.Changeset.for_create(:create, %{
      status: :active,
      current_period_start: Date.utc_today(),
      current_period_end: Date.add(Date.utc_today(), 30)
    })
    |> Ash.Changeset.force_change_attribute(:customer_id, customer_id)
    |> Ash.Changeset.force_change_attribute(:plan_id, plan_id)
    |> Ash.create!()
  end

  describe "GET /api/v1/subscriptions" do
    test "requires authentication", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/subscriptions")
      assert json_response(conn, 401)
    end

    test "returns current customer's subscriptions", %{conn: conn} do
      {authed, customer, _} = register_and_sign_in(conn)
      plan = create_plan()
      sub = create_subscription(customer.id, plan.id)

      conn = get(authed, ~p"/api/v1/subscriptions")
      body = json_response(conn, 200)

      assert [returned] = body["data"]
      assert returned["id"] == sub.id
      assert returned["status"] == "active"
    end
  end

  describe "POST /api/v1/subscriptions/:id/pause" do
    test "transitions an active subscription to :paused", %{conn: conn} do
      {authed, customer, _} = register_and_sign_in(conn)
      plan = create_plan()
      sub = create_subscription(customer.id, plan.id)

      conn = post(authed, ~p"/api/v1/subscriptions/#{sub.id}/pause")
      body = json_response(conn, 200)
      assert body["status"] == "paused"
    end

    test "returns 404 when the subscription belongs to someone else", %{conn: conn} do
      {authed, _, _} = register_and_sign_in(conn)
      plan = create_plan()

      {:ok, other} =
        MobileCarWash.Accounts.Customer
        |> Ash.Changeset.for_create(:create_guest, %{
          email: "sub-other-#{:rand.uniform(100_000)}@example.com",
          name: "X"
        })
        |> Ash.create()

      sub = create_subscription(other.id, plan.id)

      conn = post(authed, ~p"/api/v1/subscriptions/#{sub.id}/pause")
      assert json_response(conn, 404)
    end
  end

  describe "POST /api/v1/subscriptions/:id/resume" do
    test "transitions a paused subscription back to :active", %{conn: conn} do
      {authed, customer, _} = register_and_sign_in(conn)
      plan = create_plan()
      sub = create_subscription(customer.id, plan.id)

      {:ok, _} = sub |> Ash.Changeset.for_update(:pause, %{}) |> Ash.update()

      conn = post(authed, ~p"/api/v1/subscriptions/#{sub.id}/resume")
      body = json_response(conn, 200)
      assert body["status"] == "active"
    end
  end

  describe "POST /api/v1/subscriptions/:id/cancel" do
    test "transitions the subscription to :cancelled", %{conn: conn} do
      {authed, customer, _} = register_and_sign_in(conn)
      plan = create_plan()
      sub = create_subscription(customer.id, plan.id)

      conn = post(authed, ~p"/api/v1/subscriptions/#{sub.id}/cancel")
      body = json_response(conn, 200)
      assert body["status"] == "cancelled"
    end
  end
end
