defmodule MobileCarWashWeb.Admin.TagsLiveTest do
  @moduledoc """
  Admin CRUD for customer tags at /admin/tags.
  """
  use MobileCarWashWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MobileCarWash.Accounts.Customer
  alias MobileCarWash.Marketing
  alias MobileCarWash.Marketing.Tag

  defp register_admin! do
    {:ok, customer} =
      Customer
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "tags-admin-#{System.unique_integer([:positive])}@test.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        name: "Tags Admin",
        phone: "+15125557700"
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

  describe "auth guard" do
    test "anonymous → sign-in", %{conn: conn} do
      conn = get(conn, ~p"/admin/tags")
      assert redirected_to(conn) == "/sign-in"
    end
  end

  describe "list" do
    setup do
      :ok = Marketing.seed_tags!()
      :ok
    end

    test "renders all tags including protected seeds", %{conn: conn} do
      admin = register_admin!()
      conn = sign_in(conn, admin)
      {:ok, _lv, html} = live(conn, ~p"/admin/tags")

      assert html =~ "VIP"
      assert html =~ "Do Not Service"
      assert html =~ "Veteran"
    end
  end

  describe "create" do
    setup do
      :ok = Marketing.seed_tags!()
      :ok
    end

    test "admin creates a new custom tag", %{conn: conn} do
      admin = register_admin!()
      conn = sign_in(conn, admin)
      {:ok, lv, _} = live(conn, ~p"/admin/tags")

      lv
      |> form("#new-tag", %{
        "tag" => %{
          "slug" => "commercial_fleet",
          "name" => "Commercial Fleet",
          "color" => "info"
        }
      })
      |> render_submit()

      {:ok, [t]} =
        Tag
        |> Ash.Query.for_read(:by_slug, %{slug: "commercial_fleet"})
        |> Ash.read(authorize?: false)

      assert t.name == "Commercial Fleet"
      assert t.color == :info
      refute t.protected
    end

    test "rejects duplicate slug", %{conn: conn} do
      admin = register_admin!()
      conn = sign_in(conn, admin)
      {:ok, lv, _} = live(conn, ~p"/admin/tags")

      html =
        lv
        |> form("#new-tag", %{
          "tag" => %{"slug" => "vip", "name" => "Another VIP", "color" => "success"}
        })
        |> render_submit()

      # Either surfaces an inline error OR flashes. Just confirm we
      # didn't create a second row.
      {:ok, rows} =
        Tag
        |> Ash.Query.for_read(:by_slug, %{slug: "vip"})
        |> Ash.read(authorize?: false)

      assert length(rows) == 1
      # And keep the surface on the page (not a crash).
      assert html =~ "Tags"
    end
  end

  describe "delete" do
    setup do
      :ok = Marketing.seed_tags!()
      :ok
    end

    test "admin can delete a custom (non-protected) tag", %{conn: conn} do
      {:ok, custom} =
        Tag
        |> Ash.Changeset.for_create(:create, %{
          slug: "temp_promo_#{System.unique_integer([:positive])}",
          name: "Temp Promo",
          color: :info
        })
        |> Ash.create(authorize?: false)

      admin = register_admin!()
      conn = sign_in(conn, admin)
      {:ok, lv, _} = live(conn, ~p"/admin/tags")

      lv |> element("#delete-tag-#{custom.id}") |> render_click()

      # Tag is gone: either :not_found error or no longer in the full list.
      all = Tag |> Ash.read!(authorize?: false) |> Enum.map(& &1.id)
      refute custom.id in all
    end

    test "protected tags cannot be deleted (no delete button rendered)",
         %{conn: conn} do
      {:ok, [vip]} =
        Tag
        |> Ash.Query.for_read(:by_slug, %{slug: "vip"})
        |> Ash.read(authorize?: false)

      admin = register_admin!()
      conn = sign_in(conn, admin)
      {:ok, _lv, html} = live(conn, ~p"/admin/tags")

      refute html =~ "delete-tag-#{vip.id}"
    end
  end
end
