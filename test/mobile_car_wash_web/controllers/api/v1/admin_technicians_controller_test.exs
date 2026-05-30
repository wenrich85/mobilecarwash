defmodule MobileCarWashWeb.Api.V1.AdminTechniciansControllerTest do
  use MobileCarWashWeb.ApiCase

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Operations.Technician

  describe "GET /api/v1/admin/technicians" do
    test "requires admin role", %{conn: conn} do
      {authed, _customer, _token} = register_and_sign_in(conn)

      conn = get(authed, ~p"/api/v1/admin/technicians")

      assert json_response(conn, 403)
    end

    test "returns native technician rows", %{conn: conn} do
      {authed, _admin, _token} = register_and_sign_in_admin(conn)
      user_account = create_user_account()
      technician = create_technician(user_account)

      conn = get(authed, ~p"/api/v1/admin/technicians")
      body = json_response(conn, 200)

      assert returned = Enum.find(body["data"], &(&1["id"] == technician.id))
      assert returned["name"] == "Native Tech"
      assert returned["email"] == to_string(user_account.email)
      assert returned["phone"] == "+15125557654"
      assert returned["active"] == true
      assert returned["status"] == "available"
      assert returned["zone"] == "nw"
      assert returned["pay_rate_cents"] == 3_000
      assert returned["pay_rate_pct"] == "0.35"
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

  defp create_user_account do
    Customer
    |> Ash.Changeset.for_create(:register_with_password, %{
      email: "native-tech-#{System.unique_integer([:positive])}@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      name: "Native Tech User",
      phone: "+15125550001"
    })
    |> Ash.create!(authorize?: false)
  end

  defp create_technician(user_account) do
    Technician
    |> Ash.Changeset.for_create(:create, %{
      name: "Native Tech",
      phone: "+15125557654",
      active: true,
      status: :available,
      zone: :nw,
      pay_rate_cents: 3_000,
      pay_rate_pct: Decimal.new("0.35")
    })
    |> Ash.Changeset.force_change_attribute(:user_account_id, user_account.id)
    |> Ash.create!(authorize?: false)
  end
end
