defmodule MobileCarWashWeb.Admin.CustomersExportControllerTest do
  @moduledoc """
  CSV export of the admin customer list. Respects the same URL filters
  as /admin/customers (channel, role, verified, tag, text search) but
  ignores pagination — a single CSV covers the full filtered set.
  """
  use MobileCarWashWeb.ConnCase, async: false

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Marketing
  alias MobileCarWash.Marketing.{CustomerTag, Tag}

  defp register_admin! do
    {:ok, c} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "export-admin-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Export Admin",
        phone: "+15125557800"
      })
      |> Ash.create()

    c
    |> Ash.Changeset.for_update(:update, %{role: :admin})
    |> Ash.update!(authorize?: false)
  end

  defp register_customer!(name \\ "Export Target") do
    {:ok, c} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "exp-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: name,
        phone:
          "+1512555#{:rand.uniform(9999) |> Integer.to_string() |> String.pad_leading(4, "0")}"
      })
      |> Ash.create()

    c
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

  describe "auth guard" do
    test "anonymous users redirect to /sign-in", %{conn: conn} do
      conn = get(conn, ~p"/admin/customers/export.csv")
      assert redirected_to(conn) == "/sign-in"
    end

    test "signed-in non-admin is forbidden", %{conn: conn} do
      not_admin = register_customer!("Not An Admin")
      conn = sign_in(conn, not_admin)
      conn = get(conn, ~p"/admin/customers/export.csv")

      # Redirected away from admin (to / with a flash).
      assert redirected_to(conn) == "/"
    end
  end

  describe "CSV body" do
    test "returns text/csv with a header row + all customers", %{conn: conn} do
      admin = register_admin!()
      a = register_customer!("Alpha Exporter")
      b = register_customer!("Bravo Exporter")

      conn = sign_in(conn, admin)
      conn = get(conn, ~p"/admin/customers/export.csv")

      assert response_content_type(conn, :csv) =~ "text/csv"

      body = response(conn, 200)

      assert body =~
               "name,email,phone,role,channel,tags,last_wash_at,lifetime_revenue_cents,joined_at"

      assert body =~ a.name
      assert body =~ b.name
      assert body =~ to_string(a.email)
    end

    test "respects the channel filter", %{conn: conn} do
      :ok = Marketing.seed_channels!()

      {:ok, [meta]} =
        MobileCarWash.Marketing.AcquisitionChannel
        |> Ash.Query.for_read(:by_slug, %{slug: "meta_paid"})
        |> Ash.read(authorize?: false)

      admin = register_admin!()

      {:ok, on_meta} =
        Customer
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "meta-#{System.unique_integer([:positive])}@test.com",
          password: "Password123!",
          password_confirmation: "Password123!",
          name: "On Meta Channel",
          phone: "+15125550001",
          acquired_channel_id: meta.id
        })
        |> Ash.create()

      off_meta = register_customer!("Off Any Channel")

      conn = sign_in(conn, admin)
      conn = get(conn, ~p"/admin/customers/export.csv?channel=#{meta.id}")
      body = response(conn, 200)

      assert body =~ on_meta.name
      refute body =~ off_meta.name
    end

    test "respects the tag filter", %{conn: conn} do
      :ok = Marketing.seed_tags!()

      {:ok, [vip]} =
        Tag
        |> Ash.Query.for_read(:by_slug, %{slug: "vip"})
        |> Ash.read(authorize?: false)

      admin = register_admin!()
      tagged = register_customer!("Has VIP")
      untagged = register_customer!("Plain Customer")

      {:ok, _} =
        CustomerTag
        |> Ash.Changeset.for_create(:tag, %{
          customer_id: tagged.id,
          tag_id: vip.id,
          author_id: admin.id
        })
        |> Ash.create(authorize?: false)

      conn = sign_in(conn, admin)
      conn = get(conn, ~p"/admin/customers/export.csv?tag=#{vip.id}")
      body = response(conn, 200)

      assert body =~ tagged.name
      refute body =~ untagged.name
    end

    test "escapes commas and quotes in customer names", %{conn: conn} do
      admin = register_admin!()

      {:ok, tricky} =
        Customer
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "tricky-#{System.unique_integer([:positive])}@test.com",
          password: "Password123!",
          password_confirmation: "Password123!",
          name: ~s(Smith, "Sam" Jr.),
          phone: "+15125550099"
        })
        |> Ash.create()

      conn = sign_in(conn, admin)
      conn = get(conn, ~p"/admin/customers/export.csv")
      body = response(conn, 200)

      # RFC 4180: wrap the field in quotes, double internal quotes.
      assert body =~ ~s("Smith, ""Sam"" Jr.")
      refute body =~ ~s(Smith, "Sam" Jr.,tricky-#{tricky.id})
    end
  end
end
