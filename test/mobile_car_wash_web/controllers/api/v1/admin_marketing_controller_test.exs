defmodule MobileCarWashWeb.Api.V1.AdminMarketingControllerTest do
  use MobileCarWashWeb.ApiCase

  alias MobileCarWash.Marketing.AcquisitionChannel

  describe "POST /api/v1/admin/marketing/spends" do
    test "requires admin role", %{conn: conn} do
      {authed, _customer, _token} = register_and_sign_in(conn)
      channel = create_channel()

      conn =
        post(authed, ~p"/api/v1/admin/marketing/spends", %{
          "channel_id" => channel.id,
          "spent_on" => Date.to_iso8601(Date.utc_today()),
          "amount_cents" => 2_500,
          "notes" => "Native test"
        })

      assert json_response(conn, 403)
    end

    test "records spend and returns refreshed native marketing rollups", %{conn: conn} do
      {authed, _admin, _token} = register_and_sign_in_admin(conn)
      channel = create_channel()

      conn =
        post(authed, ~p"/api/v1/admin/marketing/spends", %{
          "channel_id" => channel.id,
          "spent_on" => Date.to_iso8601(Date.utc_today()),
          "amount_cents" => 3_200,
          "notes" => "Native app campaign"
        })

      body = json_response(conn, 201)

      assert body["data"]["period"] == "last_30"
      assert body["data"]["summary"]["total_spend_cents"] == 3_200

      assert returned =
               Enum.find(body["data"]["channels"], &(&1["channel_id"] == channel.id))

      assert returned["channel_slug"] == channel.slug
      assert returned["channel_name"] == channel.display_name
      assert returned["category"] == "paid"
      assert returned["spend_cents"] == 3_200
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

  defp create_channel do
    unique = System.unique_integer([:positive])

    AcquisitionChannel
    |> Ash.Changeset.for_create(:create, %{
      slug: "native-paid-#{unique}",
      display_name: "Native Paid #{unique}",
      category: :paid,
      active: true,
      sort_order: 10
    })
    |> Ash.create!(authorize?: false)
  end
end
