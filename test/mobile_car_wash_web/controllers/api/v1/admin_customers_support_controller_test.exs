defmodule MobileCarWashWeb.Api.V1.AdminCustomersSupportControllerTest do
  use MobileCarWashWeb.ApiCase

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Marketing.{AcquisitionChannel, Tag}

  describe "GET /api/v1/admin/customers" do
    test "requires admin role", %{conn: conn} do
      {authed, _customer, _token} = register_and_sign_in(conn)

      conn = get(authed, ~p"/api/v1/admin/customers")

      assert json_response(conn, 403)
    end

    test "returns native customer rows with channel metadata", %{conn: conn} do
      {authed, _admin, _token} = register_and_sign_in_admin(conn)
      channel = create_channel()
      customer = create_customer(channel)

      conn = get(authed, ~p"/api/v1/admin/customers?q=Native")
      body = json_response(conn, 200)

      assert [returned] = body["data"]
      assert returned["id"] == customer.id
      assert returned["email"] == to_string(customer.email)
      assert returned["name"] == "Native Customer"
      assert returned["phone"] == "+15125551234"
      assert returned["role"] == "customer"
      assert returned["verified"] == false
      assert returned["disabled"] == false
      assert returned["acquired_channel_id"] == channel.id
      assert returned["acquired_channel_name"] == "Native Referral"
      assert returned["lifetime_revenue_cents"] == 0
      assert returned["last_wash_at"] == nil
      assert returned["tags"] == []
    end
  end

  describe "GET /api/v1/admin/customers/:id" do
    test "returns native customer detail payload", %{conn: conn} do
      {authed, _admin, _token} = register_and_sign_in_admin(conn)
      channel = create_channel()
      tag = create_tag()
      customer = create_customer(channel)

      conn = get(authed, ~p"/api/v1/admin/customers/#{customer.id}")
      body = json_response(conn, 200)

      assert body["data"]["id"] == customer.id
      assert body["data"]["email"] == to_string(customer.email)
      assert body["data"]["acquired_channel_name"] == "Native Referral"
      assert body["data"]["note_count"] == 0
      assert body["data"]["notes"] == []
      assert body["data"]["tags"] == []
      assert Enum.any?(body["data"]["available_tags"], &(&1["id"] == tag.id))
      assert Enum.any?(body["data"]["available_channels"], &(&1["id"] == channel.id))
      assert is_list(body["data"]["available_personas"])
      assert is_list(body["data"]["recent_appointments"])
    end
  end

  describe "native customer detail mutations" do
    test "adds toggles and deletes notes", %{conn: conn} do
      {authed, _admin, _token} = register_and_sign_in_admin(conn)
      customer = create_customer(create_channel())

      conn =
        post(authed, ~p"/api/v1/admin/customers/#{customer.id}/notes", %{
          "body" => "Smoke test note",
          "pinned" => true
        })

      body = json_response(conn, 200)
      assert [note] = body["data"]["notes"]
      assert note["body"] == "Smoke test note"
      assert note["pinned"] == true

      conn =
        post(
          authed,
          ~p"/api/v1/admin/customers/#{customer.id}/notes/#{note["id"]}/toggle_pin"
        )

      assert [toggled] = json_response(conn, 200)["data"]["notes"]
      assert toggled["pinned"] == false

      conn =
        delete(
          authed,
          ~p"/api/v1/admin/customers/#{customer.id}/notes/#{note["id"]}"
        )

      assert json_response(conn, 200)["data"]["notes"] == []
    end

    test "applies and removes customer tags", %{conn: conn} do
      {authed, _admin, _token} = register_and_sign_in_admin(conn)
      customer = create_customer(create_channel())
      tag = create_tag()

      conn =
        post(authed, ~p"/api/v1/admin/customers/#{customer.id}/tags", %{
          "tag_id" => tag.id,
          "reason" => "Smoke tag"
        })

      assert [applied] = json_response(conn, 200)["data"]["tags"]
      assert applied["id"] == tag.id
      assert applied["reason"] == "Smoke tag"

      conn = delete(authed, ~p"/api/v1/admin/customers/#{customer.id}/tags/#{tag.id}")

      assert json_response(conn, 200)["data"]["tags"] == []
    end
  end

  describe "GET /api/v1/admin/tags" do
    test "returns admin tag options", %{conn: conn} do
      {authed, _admin, _token} = register_and_sign_in_admin(conn)
      tag = create_tag()

      conn = get(authed, ~p"/api/v1/admin/tags")
      body = json_response(conn, 200)

      assert returned = Enum.find(body["data"], &(&1["id"] == tag.id))
      assert returned["slug"] == tag.slug
      assert returned["name"] == tag.name
      assert returned["description"] == tag.description
      assert returned["color"] == "success"
      assert returned["icon"] == "hero-star"
      assert returned["affects_booking"] == true
      assert returned["protected"] == false
      assert returned["active"] == true
    end
  end

  describe "GET /api/v1/admin/marketing" do
    test "returns native marketing dashboard metadata", %{conn: conn} do
      {authed, _admin, _token} = register_and_sign_in_admin(conn)
      channel = create_channel()

      conn = get(authed, ~p"/api/v1/admin/marketing?period=last_7")
      body = json_response(conn, 200)

      assert body["data"]["period"] == "last_7"
      assert body["data"]["from"]
      assert body["data"]["to"]
      assert body["data"]["summary"]["total_spend_cents"] == 0
      assert body["data"]["leaderboard"] == []

      assert returned =
               Enum.find(body["data"]["channels"], &(&1["channel_id"] == channel.id))

      assert returned["channel_slug"] == channel.slug
      assert returned["channel_name"] == channel.display_name
      assert returned["category"] == "referral"
      assert returned["spend_cents"] == 0
      assert returned["new_customers"] == 0
    end
  end

  defp register_and_sign_in_admin(conn) do
    {authed, customer, token} = register_and_sign_in(conn)

    {:ok, admin} =
      customer
      |> Ash.Changeset.for_update(:update, %{role: :admin})
      |> Ash.update(authorize?: false)

    {authed, admin, token}
  end

  defp create_customer(channel) do
    {:ok, customer} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "native-customer-#{System.unique_integer([:positive])}@example.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Native Customer",
        phone: "+15125551234"
      })
      |> Ash.create()

    customer
    |> Ash.Changeset.for_update(:update, %{})
    |> Ash.Changeset.force_change_attribute(:acquired_channel_id, channel.id)
    |> Ash.update!(authorize?: false)
  end

  defp create_channel do
    unique = System.unique_integer([:positive])

    AcquisitionChannel
    |> Ash.Changeset.for_create(:create, %{
      slug: "native_referral_#{unique}",
      display_name: "Native Referral",
      category: :referral,
      active: true,
      sort_order: unique
    })
    |> Ash.create!(authorize?: false)
  end

  defp create_tag do
    unique = System.unique_integer([:positive])

    Tag
    |> Ash.Changeset.for_create(:create, %{
      slug: "native_vip_#{unique}",
      name: "Native VIP",
      description: "Native app VIP segment",
      color: :success,
      icon: "hero-star",
      affects_booking: true,
      protected: false,
      active: true
    })
    |> Ash.create!(authorize?: false)
  end
end
